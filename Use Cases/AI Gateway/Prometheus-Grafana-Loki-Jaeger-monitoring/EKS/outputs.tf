output "configure_kubectl_user" {
  description = "Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig"
  value       = "aws eks --region ${local.region} update-kubeconfig --name ${module.eks.cluster_name} --alias ${local.name}"
}

output "configure_kubectl_local" {
  description = "Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to create a kubeconfig file in your local directory"
  value       = "aws eks --region ${local.region} update-kubeconfig --name ${module.eks.cluster_name} --kubeconfig ./kubeconfig"
}

output "grafana_credentials" {
  description = "For Grafana credentials, see grafana secret under prometheus namespace, keys: admin-user, admin-password (base64 decode)"
  value       = "For Grafana credentials, see grafana secret under prometheus namespace, keys: admin-user, admin-password (base64 decode)"
}

output "minio_credentials" {
  description = "For MinIO credentials, see minio secret under elastic audit, keys: root-user, root-password (base64 decode)"
  value       = "For MinIO credentials, see minio secret under elastic audit, keys: root-user, root-password (base64 decode)"
}
