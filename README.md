# F5 AI Use Case Examples

## Overview

Examples of F5 AI Use Cases. For more information on the use cases covered by this project, please see the following articles and workflow guides:


### **F5 AI Gateway**

  | **DevCentral Overview Articles**                                                                                                                          | **Use Case**                                                                                                                                                | **Deployment**                                          |
  | --------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -----------|
  | [*Coming soon*]() | [Monitor F5 AI Gateway with OTel, ELK and MinIO](https://github.com/f5devcentral/F5-AI-Use-Case-Examples/blob/main/Use%20Cases/AI%20Gateway/ELK-monitoring/README.rst)                         |  [XC + AWS EKS](https://github.com/f5devcentral/F5-AI-Use-Case-Examples/tree/main/Use%20Cases/AI%20Gateway/ELK-monitoring/EKS) <br>  NGINX + GCP GKE (*Coming soon*) |
  | [*Coming soon*]() | [Monitor F5 AI Gateway with OTel, Prometheus/Grafana/Loki, Jaeger and MinIO](https://github.com/f5devcentral/F5-AI-Use-Case-Examples/blob/main/Use%20Cases/AI%20Gateway/Prometheus-Grafana-Loki-Jaeger-monitoring/README.rst) |   [XC + AWS EKS](https://github.com/f5devcentral/F5-AI-Use-Case-Examples/tree/main/Use%20Cases/AI%20Gateway/Prometheus-Grafana-Loki-Jaeger-monitoring/EKS) <br> BIG-IP CIS + Azure AKS (*Coming soon*) |
  | [*Coming soon*]() | AI Gateway Connection Abstraction (*Coming soon*)                        |  NGINX + GCP GKE (*Coming soon*) |
  | [*Coming soon*]() | AI Gateway Context Routing (*Coming soon*) |   XC + AWS EKS (*Coming soon*)  |
 | [*Coming soon*]() | AI Gateway Prompt Injection Protection (*Coming soon*)                       |  BIG-IP CIS + Azure AKS (*Coming soon*)  |

 
 

  
## Getting Started

## Prerequisites

* [F5 Distributed Cloud Account (F5XC)](https://console.ves.volterra.io/signup/usage_plan)
  * [F5XC API certificate](https://docs.cloud.f5.com/docs/how-to/user-mgmt/credentials)
  * [User Domain delegated](https://docs.cloud.f5.com/docs/how-to/app-networking/domain-delegation)
* [AWS Account](https://aws.amazon.com) - Due to the assets being created, free tier will not work.
  * Please make sure resources like VPC and Elastic IP's are below the threshold limit in that aws region
* [GitHub Account](https://github.com)
* [NGINX ONE_License](https://www.f5.com/products/nginx/one) - Access to NGINX ONE license is needed for ai gateway.
* [NGINX PLUS_License](https://docs.nginx.com/nginx/admin-guide/installing-nginx/installing-nginx-plus/) - Access to NGINX PLUS license is needed for ai gateway.


## Development

Outline any requirements to setup a development environment if someone would like to contribute.  You may also link to another file for this information.

## Support

For support, please open a GitHub issue.  Note, the code in this repository is community supported and is not supported by F5 Networks.  

## Community Code of Conduct

Please refer to the [F5 DevCentral Community Code of Conduct](code_of_conduct.md).

## License

[Apache License 2.0](LICENSE)

## Copyright

Copyright 2014-2020 F5 Networks Inc.

### F5 Networks Contributor License Agreement

Before you start contributing to any project sponsored by F5 Networks, Inc. (F5) on GitHub, you will need to sign a Contributor License Agreement (CLA).

If you are signing as an individual, we recommend that you talk to your employer (if applicable) before signing the CLA since some employment agreements may have restrictions on your contributions to other projects.
Otherwise by submitting a CLA you represent that you are legally entitled to grant the licenses recited therein.

If your employer has rights to intellectual property that you create, such as your contributions, you represent that you have received permission to make contributions on behalf of that employer, that your employer has waived such rights for your contributions, or that your employer has executed a separate CLA with F5.

If you are signing on behalf of a company, you represent that you are legally entitled to grant the license recited therein.
You represent further that each employee of the entity that submits contributions is authorized to submit such contributions on behalf of the entity pursuant to the CLA.
