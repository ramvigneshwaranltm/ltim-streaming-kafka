# EKS Console Access Configuration

This document describes the IAM mapping and console access configuration for the EKS cluster.

## Overview

The infrastructure is configured to provide AWS Console access to view and manage EKS cluster resources. This includes both Kubernetes RBAC permissions (via aws-auth ConfigMap) and AWS IAM permissions (via IAM policies).

## Components

### 1. AWS Auth ConfigMap (`modules/eks/aws-auth.tf`)

The aws-auth ConfigMap manages Kubernetes RBAC by mapping AWS IAM users and roles to Kubernetes groups.

**Configured in the EKS module:**
- Automatically includes the node group role for worker nodes
- Accepts additional users and roles via variables

**Variables:**
- `aws_auth_users`: List of IAM users to map
- `aws_auth_roles`: List of IAM roles to map

### 2. IAM Console Access Policy (`iam-console-access.tf`)

An IAM policy that grants permissions to view EKS resources in the AWS Console.

**Policy Name:** `ltim-sandbox-eks-console-access`

**Permissions Granted:**
- EKS cluster and resource viewing
- Node group and add-on information
- Related EC2, VPC, and IAM resource viewing
- CloudWatch Logs viewing

**Attached To:**
- `terraformuser` (IAM user)
- `terraformrole` (IAM role)

### 3. Configuration (`terraform.tfvars`)

**Current Mappings:**

```hcl
aws_auth_users = [
  {
    userarn  = "arn:aws:iam::292481751409:user/terraformuser"
    username = "terraformuser"
    groups   = ["system:masters"]
  }
]

aws_auth_roles = [
  {
    rolearn  = "arn:aws:iam::292481751409:role/terraformrole"
    username = "terraformrole"
    groups   = ["system:masters"]
  }
]
```

Both have full admin access via the `system:masters` Kubernetes group.

## Files Modified/Added

### New Files:
- `environments/sandbox/iam-console-access.tf` - IAM policy and policy attachments

### Modified Files:
- `environments/sandbox/terraform.tfvars` - Added aws_auth_roles configuration
- `environments/sandbox/outputs.tf` - Added console access outputs
- `environments/sandbox/README.md` - Added console access documentation

### Existing Files (No Changes):
- `modules/eks/aws-auth.tf` - Already existed with variable support
- `modules/eks/variables.tf` - Already had aws_auth_users and aws_auth_roles variables
- `environments/sandbox/variables.tf` - Already had console access variables defined

## Usage

### Viewing Resources in AWS Console

1. Navigate to: https://console.aws.amazon.com/eks/home?region=eu-north-1
2. Click on cluster: `ltim-sandbox-eks`
3. View tabs:
   - **Resources**: All Kubernetes resources
   - **Nodes**: Worker nodes status
   - **Workloads**: Running applications
   - **Configuration**: Add-ons and settings

### Adding New Users/Roles

Edit `terraform.tfvars` and add entries to `aws_auth_users` or `aws_auth_roles`:

```hcl
aws_auth_users = [
  {
    userarn  = "arn:aws:iam::292481751409:user/new-user"
    username = "new-user"
    groups   = ["system:masters"]  # or other RBAC groups
  }
]
```

Then apply:
```bash
terraform apply
```

### RBAC Groups

Available Kubernetes RBAC groups:
- `system:masters`: Full cluster admin access
- `system:nodes`: Node-level access
- Custom groups: Can be created with RoleBindings/ClusterRoleBindings

## Security Considerations

1. **Least Privilege**: Consider using more restrictive RBAC groups instead of `system:masters` for regular users
2. **IAM Permissions**: The console access policy uses `Resource = "*"` for read-only operations
3. **Audit**: All access is logged via CloudWatch Logs (EKS cluster logging enabled)

## Verification

Check current mappings:
```bash
kubectl get configmap aws-auth -n kube-system -o yaml
```

View Terraform outputs:
```bash
terraform output console_access_info
```

## References

- [EKS User Authentication](https://docs.aws.amazon.com/eks/latest/userguide/add-user-role.html)
- [Kubernetes RBAC](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)
- [AWS EKS Console Access](https://docs.aws.amazon.com/eks/latest/userguide/view-kubernetes-resources.html)
