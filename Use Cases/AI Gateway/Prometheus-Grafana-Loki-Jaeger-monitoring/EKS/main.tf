################################################################################
# Common local
################################################################################
locals {
  name   = "ai-gateway"
  region = "us-west-2"
  vpc_cidr   = "10.0.0.0/16"
  num_of_azs = 2

  # this namespace should be already present in F5 XC
  f5_xc_namespace = "aigw"

  # Make sure this name matches with the new CE token created in F5 XC
  ce_site_name      = "aigw-eks"

  f5_xc_chatbot_dns = ["chatbot.example.com"]
  f5_xc_minio_dns = ["minio.example.com"]
  f5_xc_prometheus_dns = ["prometheus.example.com"]
  f5_xc_grafana_dns = ["grafana.example.com"]
  f5_xc_jaeger_dns = ["jaeger.example.com"]

  # nginx one and plus licenses
  nginx_one_jwt     = var.nginx_one_jwt
  nginx_plus_jwt    = var.nginx_plus_jwt
  nginx_registry    = "private-registry.f5.com"
  nginx_pwd         = "none"

  tags = {}
}


################################################################################
# Providers
################################################################################

provider "volterra" {
  api_p12_file     = "</path/to/api_credential>.p12"
  url              = "https://<tenant_name>.console.ves.volterra.io/api"
}

provider "aws" {
  region = local.region
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    # This requires the awscli to be installed locally where Terraform is executed
    args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", local.region, "--output", "json"]
  }

}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      # This requires the awscli to be installed locally where Terraform is executed
      args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", local.region, "--output", "json"]
    }

  }
}

provider "kubectl" {
  apply_retry_count      = 5
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  load_config_file       = false

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    # This requires the awscli to be installed locally where Terraform is executed
    args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", local.region, "--output", "json"]
  }

}

################################################################################
# Data
################################################################################
# us-east-1 required for public ECR where Karpenter artifacts are hosted
provider "aws" {
  region = "us-east-1"
  alias  = "us-east-1"
}

data "aws_availability_zones" "available" {}

data "aws_ecrpublic_authorization_token" "token" {
  provider = aws.us-east-1
}

################################################################################
# Network
################################################################################
locals {
  azs = slice(data.aws_availability_zones.available.names, 1, 3)
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = local.name
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 48)]

  enable_nat_gateway = true
  single_nat_gateway = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }

  tags = local.tags
}


################################################################################
# Cluster
################################################################################
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.21"

  cluster_name    = local.name
  cluster_version = "1.29"

  vpc_id                         = module.vpc.vpc_id
  subnet_ids                     = module.vpc.private_subnets

  cluster_endpoint_public_access = true
  manage_aws_auth_configmap = true

  # EKS Addons
  cluster_addons = {
    coredns                = {}
    eks-pod-identity-agent = {}
    kube-proxy             = {}
    vpc-cni                = {}
  }

  node_security_group_additional_rules = {
    vllm_health_port = {
      description                   = "vLLM port for health checking"
      protocol                      = "tcp"
      from_port                     = 8000
      to_port                       = 8000
      type                          = "ingress"
      source_cluster_security_group = true
    }
    aigw_health_port = {
      description                   = "aigw port for health checking"
      protocol                      = "tcp"
      from_port                     = 8080
      to_port                       = 8080
      type                          = "ingress"
      source_cluster_security_group = true
    }
  }

  eks_managed_node_groups = {
    default_node_group = {
      # Starting on 1.30, AL2023 is the default AMI type for EKS managed node groups
      ami_type       = "AL2_x86_64"
      instance_types = ["t3.2xlarge"]

      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = 1024
            volume_type           = "gp3"
            iops                  = 3000
            throughput            = 125
            encrypted             = true
            delete_on_termination = true
          }
        }
      }


      capacity_type  = "ON_DEMAND"

      min_size = 1
      max_size = 5
      # This value is ignored after the initial creation
      # https://github.com/bryantbiggs/eks-desired-size-hack
      desired_size = 1

      iam_role_additional_policies = { AmazonEBSCSIDriverPolicy = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy" }
    }
    gpu_node_group = {
      # Starting on 1.30, AL2023 is the default AMI type for EKS managed node groups
      ami_type       = "AL2_x86_64_GPU"
      instance_types = ["g4dn.2xlarge"]

#      use_custom_launch_template = false
#      disk_size = 1024

      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = 1024
            volume_type           = "gp3"
            iops                  = 3000
            throughput            = 125
            encrypted             = true
            delete_on_termination = true
          }
        }
      }

      capacity_type  = "SPOT"

      min_size = 1
      max_size = 2
      # This value is ignored after the initial creation
      # https://github.com/bryantbiggs/eks-desired-size-hack
      desired_size = 2

      iam_role_additional_policies = { AmazonEBSCSIDriverPolicy = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy" }

      labels = {
        "nvidia.com/gpu.present" = "true"
      }

      taints = {
        dedicated = {
          key    = "nvidia.com/gpu"
          operator  = "Exists"
          effect = "NO_SCHEDULE"
        }
      }
    }
  }

  tags = local.tags
}

resource "time_sleep" "wait_3_minutes" {
  depends_on = [module.eks]

  create_duration = "3m"
}

resource "aws_eks_addon" "aws-ebs-csi-driver" {
  cluster_name      = module.eks.cluster_name
  addon_name        = "aws-ebs-csi-driver"
  depends_on = [time_sleep.wait_3_minutes]
}



################################################################################
# Additional addons
################################################################################
resource "helm_release" "nvidia-plugin" {
  name       = "nvidia-plugin"
  repository       = "https://nvidia.github.io/k8s-device-plugin"
  chart            = "nvidia-device-plugin"
  version    = "0.15.0"
  namespace        = "nvidia-device-plugin"
  create_namespace = true

  depends_on = [aws_eks_addon.aws-ebs-csi-driver]

}


module "additional_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.16"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  # Install Prometheus and Grafana
  enable_metrics_server        = true
  enable_kube_prometheus_stack = true

  # Disable Prometheus node exporter
  kube_prometheus_stack = {
    values = [
      jsonencode({
        nodeExporter = {
          enabled = false
        },
        alertmanager = {
          enabled = false
        }
      })
    ]
  }

  # Install the nvidia-device-plugin
  helm_releases = {
    #nvidia-plugin = {
    #  repository       = "https://nvidia.github.io/k8s-device-plugin"
    #  chart            = "nvidia-device-plugin"
    #  chart_version    = "0.15.0"
    #  namespace        = "nvidia-device-plugin"
    #  create_namespace = true
    #}

    # This Helm chart configures the KubeRay Operator, which can be used for advanced setups.
    # For instance, serving a model across multiple nodes.
    # For more details: https://github.com/eliran89c/self-hosted-llm-on-eks/multi-node-serving.md
    # kuberay = {
    #   repository       = "https://ray-project.github.io/kuberay-helm/"
    #   chart            = "kuberay-operator"
    #   version          = "1.1.0"
    #   namespace        = "kuberay-operator"
    #   create_namespace = true
    # }
  }

  tags = local.tags

  depends_on = [helm_release.nvidia-plugin]
}


################################################################################
# Ollama Helm chart
################################################################################

resource "helm_release" "ollama" {
  name             = "ollama"
  repository       = "https://otwld.github.io/ollama-helm/"
  chart            = "ollama"
  version          = "1.4.0"
  namespace        = "llm"
  create_namespace = true

  values = ["${file("ollama_helm_chart/values.yaml")}"]

  depends_on = [module.additional_addons]
}

################################################################################
# AI Gateway Helm
################################################################################

data "kubectl_path_documents" "aigw-ns-manifest" {
  pattern = "${path.module}/ai-gateway/aigw-ns.yaml"
}

resource "kubectl_manifest" "aigw-ns" {
  count     = length(data.kubectl_path_documents.aigw-ns-manifest.documents)
  yaml_body = element(data.kubectl_path_documents.aigw-ns-manifest.documents, count.index)

  depends_on = [helm_release.ollama]
}


resource "kubernetes_secret" "f5-license" {
    metadata {
        name = "f5-license"
        namespace = "ai-gateway"
    }

    type = "Opaque"
    data = {
     token = local.nginx_plus_jwt
    }
  depends_on = [kubectl_manifest.aigw-ns]
}

resource "kubernetes_secret" "nginx-registry" {
    metadata {
        name = "f5-registry-secret"
        namespace = "ai-gateway"
    }

    type = "kubernetes.io/dockerconfigjson"

    data = {
        ".dockerconfigjson" = jsonencode({
            auths = {
                "${local.nginx_registry}" = {
                    "username" = local.nginx_one_jwt
                    "password" = local.nginx_pwd
                    "auth" = base64encode("${local.nginx_one_jwt}:${local.nginx_pwd}")
                }
            }
        })
    }
  depends_on = [kubernetes_secret.f5-license]
}

resource "helm_release" "aigw" {
  name             = "aigw"
  repository       = "oci://private-registry.f5.com/aigw"
  repository_username = local.nginx_one_jwt
  repository_password = "none"
  chart            = "aigw"
  namespace        = "ai-gateway"

  values = ["${file("ai-gateway/values.yaml")}"]

  timeout = 600

  set {
    name = "imagePullSecrets[0].name"
    value = "f5-registry-secret"
  }

  depends_on = [kubernetes_secret.nginx-registry]
}


################################################################################
# Telemetry - Prometheus/Grafana
################################################################################

resource "helm_release" "prometheus" {
  name             = "prometheus"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "prometheus"
  namespace        = "prometheus"
  create_namespace = true

  values = ["${file("telemetry/prometheus.yaml")}"]

  depends_on = [helm_release.aigw]
}

resource "helm_release" "grafana" {
  name             = "grafana"
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "grafana"
  namespace        = "prometheus"

  values = ["${file("telemetry/grafana.yaml")}"]

  depends_on = [helm_release.prometheus]
}

################################################################################
# OpenTelemetry Collector
################################################################################

resource "helm_release" "otel-collector" {
  name             = "otel-collector"
  repository       = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  chart            = "opentelemetry-collector"
  namespace        = "ai-gateway"

  values = ["${file("telemetry/otel.collector.yaml")}"]

  depends_on = [helm_release.grafana]
}

################################################################################
# Audit (AIGW transactions) - MinIO
################################################################################

resource "helm_release" "minio" {
  name             = "minio"
  repository       = "oci://registry-1.docker.io/bitnamicharts"
  chart            = "minio"
  namespace        = "audit"
  create_namespace = true

  values = ["${file("audit/minio.yaml")}"]

  depends_on = [helm_release.otel-collector]
}


################################################################################
# Logging (Grafana Loki)
################################################################################
# Alternative to Elastic
# Can be deployed with internal MinIO, here we'll use the same MinIO cluster used for audit


resource "helm_release" "loki" {
  name             = "loki"
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "loki"
  namespace        = "loki"
  create_namespace = true

  values = ["${file("telemetry/loki.yaml")}"]

  depends_on = [helm_release.minio]
}

resource "helm_release" "alloy-k8s-monitoring" {
  name             = "alloy-k8s-monitoring"
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "k8s-monitoring"
  namespace        = "loki"
  create_namespace = true

  values = ["${file("telemetry/k8s-monitoring.yaml")}"]

  depends_on = [helm_release.loki]
}

################################################################################
# Tracing (Jaeger)
################################################################################
# Alternative to Elastic
# Export traces from OTel Collector

resource "helm_release" "jaeger" {
  name             = "jaeger"
  repository       = "https://jaegertracing.github.io/helm-charts"
  chart            = "jaeger"
  namespace        = "jaeger"
  create_namespace = true

  values = ["${file("telemetry/jaeger.yaml")}"]

  depends_on = [helm_release.alloy-k8s-monitoring]
}


################################################################################
# Chatbot
################################################################################
data "kubectl_path_documents" "chatbot-ns-manifest" {
  pattern = "${path.module}/chatbot/chatbot_ns.yaml"
}

resource "kubectl_manifest" "chatbot-ns" {
  count     = length(data.kubectl_path_documents.chatbot-ns-manifest.documents)
  yaml_body = element(data.kubectl_path_documents.chatbot-ns-manifest.documents, count.index)

  depends_on = [helm_release.jaeger]
}

data "kubectl_path_documents" "chatbot-deployment-manifest" {
  pattern = "${path.module}/chatbot/chatbot_deployment.yaml"
}

resource "kubectl_manifest" "chatbot-deployment" {
  count     = length(data.kubectl_path_documents.chatbot-deployment-manifest.documents)
  yaml_body = element(data.kubectl_path_documents.chatbot-deployment-manifest.documents, count.index)

  depends_on = [kubectl_manifest.chatbot-ns]
}

data "kubectl_path_documents" "chatbot-service-manifest" {
  pattern = "${path.module}/chatbot/chatbot_service.yaml"
}

resource "kubectl_manifest" "chatbot-service" {
  count     = length(data.kubectl_path_documents.chatbot-service-manifest.documents)
  yaml_body = element(data.kubectl_path_documents.chatbot-service-manifest.documents, count.index)

  depends_on = [kubectl_manifest.chatbot-deployment]
}

################################################################################
# F5 XC CE (Kubernetes site)
################################################################################
data "kubectl_path_documents" "f5-ce-k8s-ns-manifest" {
  pattern = "${path.module}/f5_ce_k8s/f5_ce_k8s_ns.yaml"
}

resource "kubectl_manifest" "f5-ce-k8s-ns" {
  count     = length(data.kubectl_path_documents.f5-ce-k8s-ns-manifest.documents)
  yaml_body = element(data.kubectl_path_documents.f5-ce-k8s-ns-manifest.documents, count.index)
  depends_on = [kubectl_manifest.chatbot-service]
}

data "kubectl_path_documents" "f5-ce-k8s-config-rbac-manifest" {
  pattern = "${path.module}/f5_ce_k8s/f5_ce_k8s_config_RBAC.yaml"
}

resource "kubectl_manifest" "f5-ce-k8s-config-rbac" {
  count     = length(data.kubectl_path_documents.f5-ce-k8s-config-rbac-manifest.documents)
  yaml_body = element(data.kubectl_path_documents.f5-ce-k8s-config-rbac-manifest.documents, count.index)
  depends_on = [kubectl_manifest.f5-ce-k8s-ns]
}


data "kubectl_path_documents" "f5-ce-k8s-deployments-manifest" {
  pattern = "${path.module}/f5_ce_k8s/f5_ce_k8s_deployments.yaml"
}

resource "kubectl_manifest" "f5-ce-k8s-deployments" {
  count     = length(data.kubectl_path_documents.f5-ce-k8s-deployments-manifest.documents)
  yaml_body = element(data.kubectl_path_documents.f5-ce-k8s-deployments-manifest.documents, count.index)
  depends_on = [kubectl_manifest.f5-ce-k8s-config-rbac]
}


data "kubectl_path_documents" "f5-ce-k8s-services-manifest" {
  pattern = "${path.module}/f5_ce_k8s/f5_ce_k8s_services.yaml"
}

resource "kubectl_manifest" "f5-ce-k8s-services" {
  count     = length(data.kubectl_path_documents.f5-ce-k8s-services-manifest.documents)
  yaml_body = element(data.kubectl_path_documents.f5-ce-k8s-services-manifest.documents, count.index)
  depends_on = [kubectl_manifest.f5-ce-k8s-deployments]
}

resource "volterra_registration_approval" "k8s-ce" {
  cluster_name    = local.ce_site_name
  cluster_size    = 1
  retry           = 5
  wait_time       = 60
  hostname        = "vp-manager-0"
  provisioner "local-exec" {
  command     = "sleep 30"
  }
  depends_on = [kubectl_manifest.f5-ce-k8s-services]
}

# temporary file which is needed for site cleanup
resource "volterra_site_state" "site" {
  name            = local.ce_site_name
  state           = "DECOMMISSIONING"
  when            = "delete"
  retry           = 5
  wait_time       = 60
}

################################################################################
# F5 XC LBs and Pools
################################################################################

resource "volterra_origin_pool" "chatbot" {
  name                   = "chatbot"
  namespace              = local.f5_xc_namespace
  endpoint_selection     = "LOCAL_PREFERRED"
  loadbalancer_algorithm = "LB_OVERRIDE"

  origin_servers {
    k8s_service {
      service_name  = "chatbot.chatbot"
      outside_network = true
      site_locator {
        site {
          name      = local.ce_site_name
          namespace = "system"
          }
        }
      }
  }

  port = "8501"

  no_tls = true

  advanced_options {
    http1_config {
      header_transformation {
        legacy_header_transformation = true
      }
    }
  }

  depends_on = [kubectl_manifest.f5-ce-k8s-services]
}

resource "volterra_http_loadbalancer" "chatbot" {

  name                   = "chatbot"
  namespace              = local.f5_xc_namespace
  description            = format("HTTPS loadbalancer object for AI Chatbot origin server")

  advertise_on_public_default_vip = true

  domains                = local.f5_xc_chatbot_dns

  https_auto_cert {
    add_hsts              = false
    http_redirect         = true
    no_mtls               = true
    enable_path_normalize = true
    tls_config {
      default_security = true
    }
  }

  routes {
    simple_route {
      path {
        prefix = "/"
      }
      origin_pools {
        pool {
          name = "chatbot"
          namespace = local.f5_xc_namespace
        }
      }
      advanced_options {
        web_socket_config {
          use_websocket = true
        }
      }
    }
  }

  app_firewall {
    name = "default"
    namespace = "shared"
  }

  depends_on =  [volterra_origin_pool.chatbot]

}

resource "volterra_origin_pool" "minio" {
  name                   = "minio"
  namespace              = local.f5_xc_namespace
  endpoint_selection     = "LOCAL_PREFERRED"
  loadbalancer_algorithm = "LB_OVERRIDE"

  origin_servers {
    k8s_service {
      service_name  = "minio.audit"
      outside_network = true
      site_locator {
        site {
          name      = local.ce_site_name
          namespace = "system"
          }
        }
      }
  }

  port = "9001"

  no_tls = true

  advanced_options {
    http1_config {
      header_transformation {
        legacy_header_transformation = true
      }
    }
  }

  depends_on = [volterra_http_loadbalancer.chatbot]
}

resource "volterra_http_loadbalancer" "minio" {

  name                   = "minio"
  namespace              = local.f5_xc_namespace
  description            = format("HTTPS loadbalancer object for MinIO origin server")

  advertise_on_public_default_vip = true

  domains                = local.f5_xc_minio_dns

  https_auto_cert {
    add_hsts              = false
    http_redirect         = true
    no_mtls               = true
    enable_path_normalize = true
    tls_config {
      default_security = true
    }
  }

  routes {
    simple_route {
      path {
        prefix = "/"
      }
      origin_pools {
        pool { 
          name = "minio"
          namespace = local.f5_xc_namespace
        }
      }
      advanced_options {
        web_socket_config {
          use_websocket = true
        }
      }
    }
  }

  default_route_pools {
      pool {
        name = volterra_origin_pool.minio.name
        namespace = local.f5_xc_namespace
      }
      weight = 1
  }

  app_firewall {
    name = "default"
    namespace = "shared"
  }

  depends_on =  [volterra_origin_pool.minio]

}



resource "volterra_origin_pool" "prometheus" {
  name                   = "prometheus"
  namespace              = local.f5_xc_namespace
  endpoint_selection     = "LOCAL_PREFERRED"
  loadbalancer_algorithm = "LB_OVERRIDE"

  origin_servers {
    k8s_service {
      service_name  = "prometheus-server.prometheus"
      outside_network = true
      site_locator {
        site {
          name      = local.ce_site_name
          namespace = "system"
          }
        }
      }
  }

  port = "80"

  no_tls = true

  depends_on = [volterra_http_loadbalancer.minio]
}

resource "volterra_http_loadbalancer" "prometheus" {

  name                   = "prometheus"
  namespace              = local.f5_xc_namespace
  description            = format("HTTPS loadbalancer object for Prometheus origin server")

  advertise_on_public_default_vip = true

  domains                = local.f5_xc_prometheus_dns

  https_auto_cert {
    add_hsts              = false
    http_redirect         = true
    no_mtls               = true
    enable_path_normalize = true
    tls_config {
      default_security = true
    }
  }

  default_route_pools {
      pool {
        name = "prometheus"
        namespace = local.f5_xc_namespace
      }
      weight = 1
  }

  app_firewall {
    name = "default"
    namespace = "shared"
  }

  depends_on =  [volterra_origin_pool.prometheus]

}

resource "volterra_origin_pool" "grafana" {
  name                   = "grafana"
  namespace              = local.f5_xc_namespace
  endpoint_selection     = "LOCAL_PREFERRED"
  loadbalancer_algorithm = "LB_OVERRIDE"

  origin_servers {
    k8s_service {
      service_name  = "grafana.prometheus"
      outside_network = true
      site_locator {
        site {
          name      = local.ce_site_name
          namespace = "system"
          }
        }
      }
  }

  port = "80"

  no_tls = true

  depends_on = [volterra_http_loadbalancer.prometheus]
}

resource "volterra_http_loadbalancer" "grafana" {

  name                   = "grafana"
  namespace              = local.f5_xc_namespace
  description            = format("HTTPS loadbalancer object for Grafana/Prometheus/Loki origin server")

  advertise_on_public_default_vip = true

  domains                = local.f5_xc_grafana_dns

  https_auto_cert {
    add_hsts              = false
    http_redirect         = true
    no_mtls               = true
    enable_path_normalize = true
    tls_config {
      default_security = true
    }
  }

  default_route_pools {
      pool {
        name = "grafana"
        namespace = local.f5_xc_namespace
      }
      weight = 1
  }

  app_firewall {
    name = "default"
    namespace = "shared"
  }

  depends_on =  [volterra_origin_pool.grafana]

}


resource "volterra_origin_pool" "jaeger" {
  name                   = "jaeger"
  namespace              = local.f5_xc_namespace
  endpoint_selection     = "LOCAL_PREFERRED"
  loadbalancer_algorithm = "LB_OVERRIDE"

  origin_servers {
    k8s_service {
      service_name  = "jaeger-query.jaeger"
      outside_network = true
      site_locator {
        site {
          name      = local.ce_site_name
          namespace = "system"
          }
        }
      }
  }

  port = "80"

  no_tls = true

  depends_on = [volterra_http_loadbalancer.grafana]
}

resource "volterra_http_loadbalancer" "jaeger" {

  name                   = "jaeger"
  namespace              = local.f5_xc_namespace
  description            = format("HTTPS loadbalancer object for Jaeger origin server")

  advertise_on_public_default_vip = true

  domains                = local.f5_xc_jaeger_dns

  https_auto_cert {
    add_hsts              = false
    http_redirect         = true
    no_mtls               = true
    enable_path_normalize = true
    tls_config {
      default_security = true
    }
  }

  default_route_pools {
      pool {
        name = "jaeger"
        namespace = local.f5_xc_namespace
      }
      weight = 1
  }

  app_firewall {
    name = "default"
    namespace = "shared"
  }

  depends_on =  [volterra_origin_pool.jaeger]

}
