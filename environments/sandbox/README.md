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

## AWS Console Access

The infrastructure automatically configures IAM user and role mappings for AWS Console access to view EKS resources.

### Configured Access

By default, the following are mapped with full admin access:
- **IAM User**: `terraformuser` → `system:masters` group
- **IAM Role**: `terraformrole` → `system:masters` group

### IAM Policy

An IAM policy `ltim-sandbox-eks-console-access` is automatically created and attached to both the user and role, providing:
- EKS cluster and resource viewing permissions
- Node group and add-on information access
- Related EC2, VPC, and IAM resource viewing

### View Resources in Console

1. Navigate to: [EKS Console](https://console.aws.amazon.com/eks/home?region=eu-north-1)
2. Click on cluster: `ltim-sandbox-eks`
3. View tabs:
   - **Resources**: All Kubernetes resources (pods, deployments, services, etc.)
   - **Nodes**: Worker nodes status and details
   - **Workloads**: Running workloads and applications
   - **Configuration**: Add-ons, networking, and logging

### Adding More Users/Roles

To add additional IAM users or roles for console access:

1. Edit `terraform.tfvars`:

```hcl
aws_auth_users = [
  {
    userarn  = "arn:aws:iam::292481751409:user/new-user"
    username = "new-user"
    groups   = ["system:masters"]  # or other RBAC groups
  }
]

aws_auth_roles = [
  {
    rolearn  = "arn:aws:iam::292481751409:role/new-role"
    username = "new-role"
    groups   = ["system:masters"]  # or other RBAC groups
  }
]
```

2. Apply the changes:

```bash
terraform apply
```

3. Attach the console access policy to the new user/role (or they will be added automatically if using the same naming pattern).

### RBAC Groups

Available Kubernetes RBAC groups:
- `system:masters`: Full cluster admin access
- `system:nodes`: Node-level access
- Custom groups: Can be created with RoleBindings/ClusterRoleBindings

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
