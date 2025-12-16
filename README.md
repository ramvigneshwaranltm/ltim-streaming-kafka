# LTIM EKS Infrastructure

This repository contains modularized Terraform infrastructure code for deploying Amazon EKS clusters with supporting AWS resources. The infrastructure follows best practices with reusable modules and environment-specific configurations.

## Repository Structure

```
.
├── modules/                    # Shared Terraform modules
│   ├── vpc/                   # VPC module (networking)
│   ├── eks/                   # EKS cluster module
│   └── iam/                   # IAM roles and policies module
├── environments/              # Environment-specific configurations
│   ├── sandbox/              # Sandbox environment
│   ├── dev/                  # Development environment
│   └── prod/                 # Production environment
├── .gitlab-ci.yml            # CI/CD pipeline
├── .gitignore                # Git ignore rules
└── README.md                 # This file
```

## Architecture Overview

### Modular Design

This repository follows a modularized approach with:

**Shared Modules** (`modules/`):
- **VPC Module**: Creates multi-AZ VPC, subnets, NAT gateways, route tables
- **EKS Module**: Creates EKS cluster, node groups, security groups, add-ons
- **IAM Module**: Creates IAM roles for cluster, nodes, and add-ons (IRSA)

**Root Modules** (`environments/`):
- Each environment (sandbox, dev, prod) is a root module
- Composes shared modules with environment-specific values
- Maintains separate state files

### Features

#### Networking
- Multi-AZ VPC with public and private subnets
- Internet Gateway for public subnets
- NAT Gateways for private subnet internet access
- Configurable CIDR blocks and availability zones
- Automatic subnet tagging for EKS integration

#### EKS Cluster
- Configurable Kubernetes version
- Public and/or private API endpoint access
- Cluster logging to CloudWatch
- OIDC provider for IAM Roles for Service Accounts (IRSA)
- Security groups with proper ingress/egress rules
- Multiple node groups with custom configurations

#### Node Groups
- Flexible instance types and capacity (ON_DEMAND/SPOT)
- Auto-scaling configuration
- Custom labels and taints for workload segregation
- Managed node group lifecycle

#### IAM & Security
- EKS cluster IAM role with required policies
- Node group IAM role with ECR, CNI, and worker node policies
- EBS CSI driver IAM role with IRSA
- AWS Load Balancer Controller IAM role with IRSA
- EFS CSI driver IAM role with IRSA (optional)
- Principle of least privilege

#### Add-ons
- VPC CNI (Amazon VPC CNI plugin)
- CoreDNS
- kube-proxy
- EBS CSI Driver (optional, for persistent volumes)
- AWS Load Balancer Controller setup (optional)
- EFS CSI Driver (optional, for shared file systems)

## Getting Started

### Prerequisites

1. **AWS Account** with appropriate permissions
2. **Terraform** >= 1.0 installed
3. **AWS CLI** configured with credentials
4. **S3 Bucket** for Terraform state storage
5. **DynamoDB Table** for state locking

### Quick Start

#### 1. Clone the Repository

```bash
git clone <repository-url>
cd eks-kafka
```

#### 2. Choose an Environment

Navigate to the environment you want to deploy:

```bash
cd environments/sandbox  # or dev, prod
```

#### 3. Configure Backend Storage

Edit `vars/backend.hcl`:

```hcl
bucket         = "your-terraform-state-bucket"
key            = "ltim/sandbox/terraform.tfstate"
region         = "eu-north-1"
encrypt        = true
dynamodb_table = "terraform-state-lock"
```

#### 4. Customize Variables

Edit `terraform.tfvars` with your desired configuration:
- VPC CIDR blocks
- EKS cluster version
- Node group configurations
- Add-on selections
- Tags

#### 5. Deploy

```bash
# Initialize Terraform
terraform init -backend-config=vars/backend.hcl -upgrade

# Validate configuration
terraform validate

# Plan deployment
terraform plan

# Apply configuration
terraform apply
```

#### 6. Configure kubectl

```bash
aws eks update-kubeconfig --name ltim-sandbox-eks --region eu-north-1
kubectl get nodes
```

## Module Usage

### VPC Module

```hcl
module "vpc" {
  source = "../../modules/vpc"

  project_name         = "ltim"
  environment          = "sandbox"
  vpc_cidr             = "10.0.0.0/16"
  private_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnet_cidrs  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
  enable_nat_gateway   = true
  single_nat_gateway   = false
  cluster_name         = "ltim-sandbox-eks"

  tags = {
    Environment = "sandbox"
    ManagedBy   = "Terraform"
  }
}
```

### IAM Module

```hcl
module "iam" {
  source = "../../modules/iam"

  project_name                        = "ltim"
  environment                         = "sandbox"
  oidc_provider_arn                   = module.eks.oidc_provider_arn
  oidc_provider_url                   = module.eks.oidc_provider_url
  enable_ebs_csi_driver               = true
  enable_aws_load_balancer_controller = true
  enable_efs_csi_driver               = false

  tags = {
    Environment = "sandbox"
    ManagedBy   = "Terraform"
  }
}
```

### EKS Module

```hcl
module "eks" {
  source = "../../modules/eks"

  project_name        = "ltim"
  environment         = "sandbox"
  cluster_name        = "ltim-sandbox-eks"
  cluster_version     = "1.32"
  cluster_role_arn    = module.iam.eks_cluster_role_arn
  node_role_arn       = module.iam.eks_node_group_role_arn
  vpc_id              = module.vpc.vpc_id
  private_subnet_ids  = module.vpc.private_subnet_ids
  public_subnet_ids   = module.vpc.public_subnet_ids

  node_groups = {
    general = {
      desired_size   = 2
      min_size       = 1
      max_size       = 4
      instance_types = ["t3.medium"]
      capacity_type  = "ON_DEMAND"
      disk_size      = 50
      labels         = { role = "general" }
      taints         = []
    }
  }

  tags = {
    Environment = "sandbox"
    ManagedBy   = "Terraform"
  }
}
```

## Creating Additional Environments

To create a new environment:

1. **Copy an existing environment**:
```bash
cp -r environments/sandbox environments/staging
```

2. **Update the configuration**:
   - Edit `main.tf`: Update `locals` block with new environment name
   - Edit `vars/backend.hcl`: Update state file path
   - Edit `terraform.tfvars`: Customize environment-specific values

3. **Update GitLab CI/CD** (optional):
   - Add new environment variables in `.gitlab-ci.yml`
   - Create corresponding jobs for the new environment

## Configuration Variables

### Core Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `aws_region` | AWS region | `eu-north-1` |
| `vpc_cidr` | VPC CIDR block | `10.0.0.0/16` |
| `cluster_version` | Kubernetes version | `1.28` |

### Node Group Configuration

```hcl
node_groups = {
  general = {
    desired_size   = 2
    min_size       = 1
    max_size       = 4
    instance_types = ["t3.medium"]
    capacity_type  = "ON_DEMAND"
    disk_size      = 50
    labels         = { role = "general" }
    taints         = []
  }
}
```

## CI/CD Pipeline

The repository includes a GitLab CI/CD pipeline with the following stages:

1. **Authenticate**: Assume AWS role using OIDC
2. **Validate**: Validate Terraform configuration
3. **Plan**: Generate execution plan
4. **Apply**: Apply changes (manual trigger)

### Pipeline Variables

Set these in GitLab CI/CD settings:

- `AWS_ROLE_ARN_SANDBOX`: IAM role ARN for sandbox environment
- `AWS_ROLE_ARN_DEV`: IAM role ARN for dev environment
- `AWS_ROLE_ARN_PROD`: IAM role ARN for production environment

### Running the Pipeline

The pipeline runs automatically on push. To deploy:

1. Review the plan stage output
2. Manually trigger the apply stage for the desired environment

## Security Best Practices

1. **Network Isolation**
   - Use private subnets for worker nodes
   - Restrict API endpoint access with CIDR blocks
   - Enable VPC flow logs

2. **IAM**
   - Use IRSA for pod-level permissions
   - Follow least privilege principle
   - Regularly review and rotate credentials

3. **Encryption**
   - Enable encryption at rest for EBS volumes
   - Use encrypted S3 buckets for state
   - Enable secrets encryption in EKS

4. **Monitoring**
   - Enable CloudWatch logging
   - Set up alerts for critical events
   - Use Container Insights

5. **Compliance**
   - Tag all resources appropriately
   - Enable AWS Config rules
   - Regular security audits

## Troubleshooting

### Common Issues

**Terraform state lock error**:
```bash
terraform force-unlock <LOCK_ID>
```

**Node groups fail to create**:
- Check IAM permissions
- Verify subnet tags for EKS
- Review security group rules

**Cannot access cluster API**:
- Verify public access CIDR blocks
- Check security group rules
- Ensure AWS credentials are correct

**Circular dependency with IAM module**:
- The IAM module handles this automatically
- OIDC-dependent roles are created only when OIDC provider exists
- Apply may take two passes for first deployment

## Cleanup

To destroy all resources in an environment:

```bash
cd environments/sandbox  # or dev, prod
terraform destroy
```

**Warning**: This will delete all resources including the EKS cluster and VPC.

## Contributing

1. Create a feature branch
2. Make your changes
3. Test in sandbox environment
4. Submit merge request
5. Get approval and merge

## Module Documentation

Each module has its own README with detailed documentation:

- [VPC Module](modules/vpc/README.md)
- [EKS Module](modules/eks/README.md)
- [IAM Module](modules/iam/README.md)

## Support

For issues and questions:
- Create an issue in the repository
- Contact the platform team
- Refer to AWS EKS documentation

## Additional Resources

- [AWS EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Terraform Module Best Practices](https://www.terraform.io/docs/modules/index.html)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [AWS IAM Roles for Service Accounts](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)
