# LTIM Sandbox Environment

This directory contains the Terraform configuration for the LTIM sandbox environment.

## Structure

This is a root module that uses the shared modules from `../../modules/`:
- **VPC Module**: Creates VPC, subnets, NAT gateways, route tables
- **IAM Module**: Creates IAM roles for EKS cluster, nodes, and add-ons
- **EKS Module**: Creates EKS cluster, node groups, and add-ons

## Prerequisites

1. AWS CLI configured with appropriate credentials
2. Terraform >= 1.0
3. S3 bucket for Terraform state storage
4. DynamoDB table for state locking

## Configuration Files

- `main.tf`: Module composition and resource orchestration
- `variables.tf`: Variable definitions
- `outputs.tf`: Output definitions
- `provider.tf`: Terraform and provider configuration
- `terraform.tfvars`: Environment-specific values
- `vars/backend.hcl`: Backend configuration

## Deployment

### 1. Update Backend Configuration

Edit `vars/backend.hcl` with your S3 bucket details:

```hcl
bucket         = "your-terraform-state-bucket"
key            = "ltim/sandbox/terraform.tfstate"
region         = "eu-north-1"
encrypt        = true
dynamodb_table = "terraform-state-lock"
```

### 2. Customize Variables

Edit `terraform.tfvars` to customize your deployment:
- VPC CIDR blocks
- EKS cluster version
- Node group configurations
- Add-on selections

### 3. Initialize Terraform

```bash
terraform init -backend-config=vars/backend.hcl -upgrade
```

### 4. Plan

```bash
terraform plan
```

### 5. Apply

```bash
terraform apply
```

## Post-Deployment

### Configure kubectl

```bash
aws eks update-kubeconfig --name ltim-sandbox-eks --region eu-north-1
```

### Verify Cluster Access

```bash
kubectl get nodes
kubectl get pods -A
```

## Cleanup

To destroy all resources:

```bash
terraform destroy
```

**Warning**: This will delete all resources including the EKS cluster and VPC.

## GitLab CI/CD

This environment is configured for GitLab CI/CD deployment. See the root `.gitlab-ci.yml` for pipeline configuration.

## Support

For issues or questions, contact the platform team or create an issue in the repository.
