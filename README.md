# LTIM EKS Infrastructure

Terraform infrastructure for deploying Amazon EKS with full supporting AWS resources for the LTIM Streaming Kafka platform. Follows a modular design with environment-specific configurations.

## Repository Structure

```
.
├── modules/                         # Shared Terraform modules
│   ├── vpc/                        # VPC, subnets, NAT gateway, IGW
│   ├── eks/                        # EKS cluster + OIDC provider
│   ├── iam/                        # Cluster + node group IAM roles
│   └── iam-oidc/                   # IRSA roles (EBS CSI, LB Controller)
├── environments/
│   └── sandbox/                    # Sandbox environment (active)
│       ├── main.tf                 # Module orchestration
│       ├── variables.tf            # Environment variables
│       ├── outputs.tf              # Terraform outputs
│       ├── external-dns.tf         # Route53 zone + ExternalDNS IAM
│       ├── glue-schema-registry.tf # Glue Schema Registry + IRSA role
│       ├── kafka-security.tf       # Security group rules for Kafka
│       └── iam-console-access.tf   # AWS Console access policy
├── external-dns-values.yaml        # ExternalDNS Helm configuration
└── README.md
```

## What Gets Deployed

### Networking

| Resource | Value |
|---|---|
| Region | `eu-north-1` (Stockholm) |
| VPC CIDR | `10.0.0.0/16` |
| Availability Zones | 3 |
| Private Subnets | 3 (EKS nodes) |
| Public Subnets | 3 (Load Balancers) |
| NAT Gateway | 1 (single, sandbox) |

### EKS Cluster

| Resource | Value |
|---|---|
| Cluster Name | `ltim-sandbox-eks` |
| Kubernetes Version | `1.32` |
| OIDC Provider | Enabled (required for IRSA) |
| EBS CSI Driver | Managed add-on |

### IAM Roles (IRSA — no static credentials anywhere)

| Role | Trusted Service Account | Purpose |
|---|---|---|
| `ltim-sandbox-eks-cluster-role` | EKS control plane | Cluster management |
| `ltim-sandbox-eks-node-group-role` | Worker nodes | ECR, CNI, worker policies |
| `ltim-sandbox-ebs-csi-driver-role` | `kube-system:ebs-csi-controller-sa` | EBS volume provisioning |
| `ltim-sandbox-aws-load-balancer-controller-role` | `kube-system:aws-load-balancer-controller` | NLB provisioning |
| `ltim-sandbox-external-dns-role` | `external-dns:external-dns` | Route53 record management |
| `ltim-sandbox-kafka-schema-registry-role` | `kafka:kafka-schema-registry-sa` | Glue Schema Registry access |

### DNS — Route53 Private Hosted Zone (`aws.internal`)

DNS records are created automatically by ExternalDNS when Kafka services come up:

| DNS Name | Port | Points To |
|---|---|---|
| `kafka-sandbox.aws.internal` | `9094` | Kafka external bootstrap NLB |
| `kafka-ui-sandbox.aws.internal` | `8080` | Kafka UI NLB |

> Records are VPC-scoped (private). Not publicly resolvable.

### AWS Glue Schema Registry

| Resource | Value |
|---|---|
| Registry Name | `ltim-sandbox-kafka-registry` |
| Region | `eu-north-1` |
| Supported Formats | Avro, JSON Schema, Protobuf |
| Auth Method | IRSA (no credentials needed in application code) |

---

## Getting Started

### Prerequisites

- AWS CLI configured with appropriate permissions
- Terraform >= 1.0 installed
- S3 bucket for Terraform state: `ltim-kafka-state-bucket`

### Deploy

```bash
# 1. Clone and navigate to sandbox
git clone <repository-url>
cd eks-kafka/environments/sandbox

# 2. Initialize
terraform init

# 3. Review what will be created
terraform plan

# 4. Apply
terraform apply

# 5. Configure kubectl
aws eks update-kubeconfig --name ltim-sandbox-eks --region eu-north-1
kubectl get nodes
```

### Key Outputs After Apply

```bash
terraform output eks_cluster_id                    # Cluster name
terraform output kubectl_config_command            # kubeconfig command
terraform output external_dns_role_arn             # ExternalDNS IRSA role
terraform output kafka_schema_registry_role_arn    # Glue IRSA role — copy for Helm
terraform output glue_schema_registry_name         # Registry name
terraform output kafka_dns_name                    # Kafka DNS endpoint
```

> **Important:** Copy `kafka_schema_registry_role_arn` — it is required as input to the Helm deployment in `ltim-streaming-kafka`.

---

## Module Details

### VPC Module

Creates multi-AZ VPC with public/private subnets, NAT gateway, Internet Gateway, and all required subnet tags for EKS and NLB integration.

```hcl
module "vpc" {
  source               = "../../modules/vpc"
  project_name         = "ltim"
  environment          = "sandbox"
  vpc_cidr             = "10.0.0.0/16"
  availability_zones   = ["eu-north-1a", "eu-north-1b", "eu-north-1c"]
  private_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnet_cidrs  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
  enable_nat_gateway   = true
  single_nat_gateway   = true
}
```

### EKS Module

Creates EKS cluster with OIDC provider, node groups, security groups, CloudWatch logging, and aws-auth configmap for user/role mapping.

### IAM-OIDC Module

Creates OIDC-based IAM roles for EKS add-ons (EBS CSI, Load Balancer Controller). Runs after EKS module since it requires the OIDC provider ARN and URL.

### Sandbox-Level Resources (environment-specific, not in modules)

| File | What it creates |
|---|---|
| `external-dns.tf` | Route53 private zone `aws.internal` + ExternalDNS IRSA role/policy |
| `glue-schema-registry.tf` | Glue registry `ltim-sandbox-kafka-registry` + Kafka app IRSA role |
| `kafka-security.tf` | Security group rule — port 9095 open for Kafka POC access |
| `iam-console-access.tf` | EKS console access policy attached to `terraformrole` and `terraformuser` |

---

## Adding a New Environment

```bash
# 1. Copy sandbox
cp -r environments/sandbox environments/dev

# 2. Update locals in main.tf
#    environment = "dev"

# 3. Update backend config key
#    key = "ltim/dev/terraform.tfstate"

# 4. Adjust terraform.tfvars for the new environment

terraform init
terraform apply
```

---

## Destroying an Environment

Before running `terraform destroy`, clean up Kubernetes-managed AWS resources first to avoid orphaned NLBs blocking VPC deletion:

```bash
# 1. Connect to cluster
aws eks update-kubeconfig --name ltim-sandbox-eks --region eu-north-1

# 2. Uninstall Helm releases (removes NLBs)
helm uninstall kafka-eks -n kafka
helm uninstall external-dns -n external-dns

# 3. Delete PVCs (removes EBS volumes)
kubectl delete pvc --all -n kafka

# 4. Delete namespaces
kubectl delete namespace kafka external-dns

# 5. Now destroy Terraform
cd environments/sandbox
terraform destroy
```

> Skipping steps 1–4 will leave orphaned Load Balancers and EBS volumes that block VPC deletion.

---

## Troubleshooting

**Terraform state lock:**
```bash
terraform force-unlock <LOCK_ID>
```

**VPC stuck during destroy (orphaned ENIs from NLBs):**
```bash
# List NLBs in the VPC and delete manually
aws elbv2 describe-load-balancers --query 'LoadBalancers[?VpcId==`<vpc-id>`].LoadBalancerArn'
aws elbv2 delete-load-balancer --load-balancer-arn <arn>

# Also check classic ELBs
aws elb describe-load-balancers
aws elb delete-load-balancer --load-balancer-name <name>
```

**ExternalDNS not creating DNS records:**
- Ensure `external-dns-values.yaml` does not contain a hardcoded `zoneIdFilters` block (it should use `domainFilters` only)
- Check logs: `kubectl logs -n external-dns -l app.kubernetes.io/name=external-dns`
- Verify services have annotation: `external-dns.alpha.kubernetes.io/hostname: <name>.aws.internal`

**Cannot access EKS API:**
```bash
aws eks update-kubeconfig --name ltim-sandbox-eks --region eu-north-1
```

**IAM policy stuck during destroy (attached to users):**
```bash
aws iam detach-user-policy --user-name <username> --policy-arn <arn>
```

---

## Related Repository

**`ltim-streaming-kafka`** — Kafka application deployment (Helm) that runs on this infrastructure.

Deployment dependency:
```
terraform apply (this repo)
       ↓
copy: kafka_schema_registry_role_arn output
       ↓
paste into: ltim-streaming-kafka/helm/kafka-eks/values-sandbox.yaml
       ↓
./deploy.sh sandbox (ltim-streaming-kafka repo)
```

---

## Resources

- [Strimzi Kafka Operator](https://strimzi.io/docs/)
- [AWS EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [AWS Glue Schema Registry](https://docs.aws.amazon.com/glue/latest/dg/schema-registry.html)
- [IAM Roles for Service Accounts (IRSA)](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)
- [ExternalDNS on AWS](https://kubernetes-sigs.github.io/external-dns/v0.14.0/tutorials/aws/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
