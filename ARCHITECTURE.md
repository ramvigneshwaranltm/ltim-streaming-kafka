# EKS Infrastructure Architecture Documentation

## Table of Contents
- [Overview](#overview)
- [Architecture Diagram](#architecture-diagram)
- [Module Breakdown](#module-breakdown)
  - [VPC Module](#1-vpc-module)
  - [IAM Module](#2-iam-module)
  - [EKS Module](#3-eks-module)
  - [IAM OIDC Module](#4-iam-oidc-module)
  - [EKS Add-ons](#5-environment-specific-eks-add-ons)
- [Environment Structure](#environment-structure)
- [How It All Works Together](#how-it-all-works-together)
- [Key Terraform Concepts](#key-terraform-concepts-used)
- [Security Best Practices](#security-best-practices)
- [Next Steps](#next-steps)

---

## Overview

This repository implements a **production-ready Amazon EKS (Elastic Kubernetes Service) infrastructure** with:
- ✅ Multi-environment support (dev, prod, sandbox)
- ✅ Modular Terraform architecture
- ✅ IAM roles with IRSA (IAM Roles for Service Accounts)
- ✅ EKS cluster with managed node groups
- ✅ VPC networking with public and private subnets
- ✅ Kubernetes add-ons (EBS CSI, CoreDNS, kube-proxy, VPC CNI)
- ✅ Security best practices (private subnets, security groups, IRSA)

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                      AWS Account                                │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │                    VPC Module                             │ │
│  │  ┌──────────────────────────────────────────────────┐    │ │
│  │  │  Public Subnets (across AZs)                      │    │ │
│  │  │  - NAT Gateways                                   │    │ │
│  │  │  - Internet Gateway                               │    │ │
│  │  └──────────────────────────────────────────────────┘    │ │
│  │  ┌──────────────────────────────────────────────────┐    │ │
│  │  │  Private Subnets (across AZs)                     │    │ │
│  │  │  - EKS Worker Nodes                               │    │ │
│  │  │  - Application Pods                               │    │ │
│  │  └──────────────────────────────────────────────────┘    │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │                  IAM Module (Base)                        │ │
│  │  - EKS Cluster Role                                       │ │
│  │  - EKS Node Group Role                                    │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │                    EKS Module                             │ │
│  │  ┌─────────────────────────────────────────────────┐     │ │
│  │  │  EKS Control Plane                               │     │ │
│  │  │  - API Server                                    │     │ │
│  │  │  - etcd                                          │     │ │
│  │  │  - Controller Manager                            │     │ │
│  │  │  - Scheduler                                     │     │ │
│  │  │  - OIDC Provider                                 │     │ │
│  │  └─────────────────────────────────────────────────┘     │ │
│  │  ┌─────────────────────────────────────────────────┐     │ │
│  │  │  Managed Node Groups                             │     │ │
│  │  │  - EC2 instances in private subnets              │     │ │
│  │  │  - Auto Scaling Groups                           │     │ │
│  │  └─────────────────────────────────────────────────┘     │ │
│  │  ┌─────────────────────────────────────────────────┐     │ │
│  │  │  EKS Add-ons                                     │     │ │
│  │  │  - VPC CNI (networking)                          │     │ │
│  │  │  - kube-proxy (network proxy)                    │     │ │
│  │  │  - CoreDNS (DNS)                                 │     │ │
│  │  └─────────────────────────────────────────────────┘     │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │              IAM OIDC Module                              │ │
│  │  - EBS CSI Driver Role (for persistent volumes)           │ │
│  │  - AWS Load Balancer Controller Role                      │ │
│  │  - EFS CSI Driver Role (for shared storage)               │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │              EKS Add-ons (with IRSA)                      │ │
│  │  - EBS CSI Driver (uses OIDC role)                        │ │
│  └───────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

---

## Module Breakdown

### 1. VPC Module

**Location:** `modules/vpc/`

**Purpose:** Creates the networking foundation for EKS

#### What it creates:
- **VPC** - Virtual Private Cloud with custom CIDR block
- **Public Subnets** - For load balancers, NAT gateways (distributed across availability zones)
- **Private Subnets** - For EKS worker nodes and pods (distributed across availability zones)
- **Internet Gateway** - Allows public subnets to access the internet
- **NAT Gateways** - Allow private subnets to access internet (outbound only)
- **Route Tables** - Routes traffic between subnets, NAT, and internet gateway
- **Subnet Tags** - Special Kubernetes tags for subnet discovery

#### Key Features:
```hcl
# Kubernetes subnet tags for service discovery
tags = {
  "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  "kubernetes.io/role/elb"                   = "1"  # For public load balancers
  "kubernetes.io/role/internal-elb"          = "1"  # For internal load balancers
}
```

#### Configuration Options:
- CIDR blocks for VPC and subnets
- Number of availability zones
- Single vs multiple NAT gateways (cost vs high availability)

---

### 2. IAM Module

**Location:** `modules/iam/`

**Purpose:** Creates basic IAM roles for EKS cluster and worker nodes

#### What it creates:

##### A. EKS Cluster Role
- **Purpose:** Allows EKS service to manage AWS resources on your behalf
- **Trust Policy:** Allows `eks.amazonaws.com` to assume this role
- **Attached Policies:**
  - `AmazonEKSClusterPolicy` - Kubernetes cluster management
  - `AmazonEKSVPCResourceController` - ENI management for pods

```json
{
  "Principal": {
    "Service": "eks.amazonaws.com"
  }
}
```

##### B. EKS Node Group Role
- **Purpose:** Allows EC2 instances (worker nodes) to join the cluster
- **Trust Policy:** Allows `ec2.amazonaws.com` to assume this role
- **Attached Policies:**
  - `AmazonEKSWorkerNodePolicy` - Worker node management
  - `AmazonEKS_CNI_Policy` - VPC networking for pods
  - `AmazonEC2ContainerRegistryReadOnly` - Pull container images from ECR

```json
{
  "Principal": {
    "Service": "ec2.amazonaws.com"
  }
}
```

#### Why separate from OIDC roles?
- These roles don't require the EKS cluster to exist first
- They use standard AWS service principals
- No dependency on OIDC provider
- Breaks the circular dependency

---

### 3. EKS Module

**Location:** `modules/eks/`

**Purpose:** Creates the EKS cluster, worker nodes, and add-ons

#### What it creates:

##### A. EKS Control Plane
```hcl
resource "aws_eks_cluster" "main" {
  name     = "ltim-dev-eks"  # example
  version  = "1.28"
  role_arn = "arn:aws:iam::...eks-cluster-role"

  vpc_config {
    subnet_ids              = [private_subnets, public_subnets]
    endpoint_private_access = true   # Nodes can reach API server via VPC
    endpoint_public_access  = true   # You can reach API server from internet
    security_group_ids      = [cluster_sg]
  }
}
```

**Features:**
- Control plane managed by AWS
- Multi-AZ for high availability
- Configurable public/private API endpoint access
- CloudWatch logging for audit, API, authenticator, controller, scheduler

##### B. OIDC Provider
```hcl
resource "aws_iam_openid_connect_provider" "eks" {
  # Enables IRSA (IAM Roles for Service Accounts)
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [certificate_fingerprint]
  url             = "https://oidc.eks.region.amazonaws.com/id/CLUSTER_ID"
}
```

**What is IRSA?**
- Allows Kubernetes pods to assume IAM roles
- More secure than storing AWS credentials in pods
- Fine-grained permissions per service account

##### C. Security Groups

**Cluster Security Group:**
- Controls traffic to/from EKS control plane
- Allows HTTPS (443) from worker nodes

**Node Security Group:**
- Controls traffic to/from worker nodes
- Allows all traffic between nodes
- Allows traffic from control plane (1025-65535)

##### D. Managed Node Groups
```hcl
resource "aws_eks_node_group" "main" {
  cluster_name    = "ltim-dev-eks"
  node_group_name = "ltim-dev-eks-workers"
  node_role_arn   = "arn:aws:iam::...node-group-role"
  subnet_ids      = [private_subnets]

  scaling_config {
    desired_size = 2
    max_size     = 5
    min_size     = 1
  }

  instance_types = ["t3.medium"]
  capacity_type  = "ON_DEMAND"  # or "SPOT" for cost savings
  disk_size      = 20
}
```

**Features:**
- Managed by AWS (automatic updates, patching)
- Auto Scaling Group integration
- Support for labels (for pod scheduling)
- Support for taints (for pod placement restrictions)
- Configurable instance types and sizes

##### E. Default Add-ons

**VPC CNI:**
- Provides VPC networking to pods
- Each pod gets an IP from your VPC
- Enables pod-to-pod communication

**kube-proxy:**
- Network proxy running on each node
- Maintains network rules for service discovery
- Enables Kubernetes Services

**CoreDNS:**
- DNS server for Kubernetes
- Enables service discovery by name
- Resolves service.namespace.svc.cluster.local

---

### 4. IAM OIDC Module

**Location:** `modules/iam-oidc/`

**Purpose:** Creates IAM roles for Kubernetes service accounts using IRSA

#### What it creates:

##### A. EBS CSI Driver Role
- **Purpose:** Allows EBS CSI driver to create/attach EBS volumes
- **Used by:** ebs-csi-controller service account
- **Permissions:** AmazonEBSCSIDriverPolicy

```json
{
  "Principal": {
    "Federated": "arn:aws:iam::123456789:oidc-provider/oidc.eks.region.amazonaws.com/id/CLUSTER_ID"
  },
  "Condition": {
    "StringEquals": {
      "oidc.eks.region.amazonaws.com/id/CLUSTER_ID:sub": "system:serviceaccount:kube-system:ebs-csi-controller-sa",
      "oidc.eks.region.amazonaws.com/id/CLUSTER_ID:aud": "sts.amazonaws.com"
    }
  }
}
```

**What this means:**
- Only the `ebs-csi-controller-sa` service account in `kube-system` namespace can assume this role
- Verified via OIDC token authentication

##### B. AWS Load Balancer Controller Role
- **Purpose:** Manages Application/Network Load Balancers for Kubernetes ingress
- **Used by:** aws-load-balancer-controller service account
- **Permissions:** Custom policy with EC2, ELB, and WAF permissions

**What it can do:**
- Create/delete Application Load Balancers
- Create/delete Network Load Balancers
- Manage target groups
- Manage security groups
- Associate WAF web ACLs

##### C. EFS CSI Driver Role
- **Purpose:** Allows EFS CSI driver to manage EFS access points
- **Used by:** efs-csi-controller service account
- **Permissions:** Custom policy for EFS operations

**What it can do:**
- Create/delete EFS access points
- Describe file systems
- Manage mount targets

#### Why IRSA?

**Traditional Approach (❌):**
- Store AWS credentials in Kubernetes secrets
- All pods in namespace can access credentials
- Hard to rotate credentials
- Broad permissions

**IRSA Approach (✅):**
- No credentials stored in cluster
- Each service account has specific role
- Automatic credential rotation (tokens expire)
- Fine-grained permissions per workload

---

### 5. Environment-Specific EKS Add-ons

#### EBS CSI Driver Add-on
```hcl
resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name             = "ltim-dev-eks"
  addon_name               = "aws-ebs-csi-driver"
  service_account_role_arn = "arn:aws:iam::...ebs-csi-driver-role"
}
```

**What it does:**
- Manages EBS volumes for persistent storage
- Enables dynamic provisioning of volumes
- Supports volume snapshots and resizing

**Example usage in Kubernetes:**
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-pvc
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: gp3
  resources:
    requests:
      storage: 10Gi
# EBS CSI driver automatically creates an EBS volume
```

---

## Environment Structure

```
environments/
├── dev/
│   ├── main.tf          # Combines all modules for dev environment
│   ├── variables.tf     # Dev-specific variables
│   ├── outputs.tf       # Dev environment outputs
│   ├── provider.tf      # AWS provider config
│   └── terraform.tfvars # Dev variable values
├── prod/
│   ├── main.tf          # Combines all modules for prod environment
│   ├── variables.tf     # Prod-specific variables
│   ├── outputs.tf       # Prod environment outputs
│   ├── provider.tf      # AWS provider config
│   └── terraform.tfvars # Prod variable values
└── sandbox/
    ├── main.tf          # Combines all modules for sandbox environment
    ├── variables.tf     # Sandbox-specific variables
    ├── outputs.tf       # Sandbox environment outputs
    ├── provider.tf      # AWS provider config
    └── terraform.tfvars # Sandbox variable values
```

### Environment Differences Example:
```hcl
# Dev Environment - Cost-optimized
node_groups = {
  workers = {
    desired_size   = 2
    min_size       = 1
    max_size       = 3
    instance_types = ["t3.medium"]
    capacity_type  = "SPOT"  # Cost-optimized
  }
}

# Prod Environment - Reliable
node_groups = {
  workers = {
    desired_size   = 3
    min_size       = 3
    max_size       = 10
    instance_types = ["t3.large"]
    capacity_type  = "ON_DEMAND"  # Reliable
  }
}
```

---

## How It All Works Together

### 1. Infrastructure Creation Flow

```
terraform apply
    │
    ├─> Creates VPC, subnets, NAT gateways, route tables
    │
    ├─> Creates IAM roles (cluster + node)
    │
    ├─> Creates EKS cluster
    │   ├─> Uses IAM cluster role
    │   ├─> Places control plane in VPC
    │   └─> Creates OIDC provider
    │
    ├─> Creates node groups
    │   ├─> Uses IAM node role
    │   ├─> Launches EC2 instances in private subnets
    │   └─> Joins nodes to cluster
    │
    ├─> Creates OIDC-dependent IAM roles
    │   ├─> EBS CSI driver role
    │   ├─> Load balancer controller role
    │   └─> EFS CSI driver role
    │
    └─> Installs EKS add-ons
        ├─> VPC CNI
        ├─> kube-proxy
        ├─> CoreDNS
        └─> EBS CSI driver (with IRSA role)
```

### 2. Pod to AWS Service Flow (with IRSA)

```
1. Pod starts with service account
   │
   ├─> Kubernetes injects OIDC token
   │
2. Pod makes AWS API call
   │
   ├─> AWS SDK uses token to call AssumeRoleWithWebIdentity
   │
3. AWS STS validates token
   │
   ├─> Checks OIDC provider
   ├─> Verifies service account name
   ├─> Verifies namespace
   │
4. STS returns temporary credentials
   │
   ├─> Valid for 1 hour
   ├─> Scoped to specific permissions
   │
5. Pod uses credentials to access AWS services
   └─> EBS volumes, S3 buckets, DynamoDB, etc.
```

### 3. Networking Flow

```
Internet
    │
    ├─> Internet Gateway (for public subnets)
    │
Public Subnets
    │
    ├─> NAT Gateway (for outbound from private subnets)
    ├─> Application Load Balancer (for incoming traffic)
    │
Private Subnets
    │
    ├─> EKS Worker Nodes
    │   │
    │   ├─> Pods (each with VPC IP)
    │   │   │
    │   │   ├─> Pod-to-pod communication (direct VPC routing)
    │   │   ├─> Pod-to-internet (via NAT Gateway)
    │   │   └─> Pod-to-AWS services (via VPC endpoints or NAT)
    │   │
    │   └─> kubelet communicates with EKS API server
    │
    └─> EBS volumes attached to nodes
```

---

## Key Terraform Concepts Used

### 1. Module Outputs
```hcl
# Module outputs values
output "cluster_id" {
  value = aws_eks_cluster.main.id
}

# Another module uses the output
module "eks" {}

resource "something" {
  cluster_id = module.eks.cluster_id  # Using output
}
```

### 2. Count for Conditional Resources
```hcl
resource "aws_eks_addon" "ebs_csi_driver" {
  count = var.enable_ebs_csi_driver ? 1 : 0
  # Creates resource if variable is true, doesn't create if false
}
```

### 3. Dynamic Blocks
```hcl
dynamic "taint" {
  for_each = each.value.taints
  content {
    key    = taint.value.key
    value  = taint.value.value
    effect = taint.value.effect
  }
}
# Creates multiple taint blocks from a list
```

### 4. for_each for Multiple Resources
```hcl
resource "aws_eks_node_group" "main" {
  for_each = var.node_groups  # Map of node group configs

  node_group_name = "${var.cluster_name}-${each.key}"
  # Creates one node group per map entry
}
```

### 5. depends_on for Explicit Dependencies
```hcl
module "iam_oidc" {
  depends_on = [module.eks]
  # Ensures EKS module completes before OIDC module starts
}
```

### 6. try() for Safe Conditional References
```hcl
output "ebs_csi_driver_role_arn" {
  value = try(aws_iam_role.ebs_csi_driver[0].arn, null)
  # Returns null if resource doesn't exist, no error
}
```

---

## Security Best Practices

### 1. Network Isolation
- Worker nodes in private subnets (no direct internet access)
- Control plane endpoint can be public or private
- Security groups restrict traffic flow

### 2. IAM Roles for Service Accounts (IRSA)
- No AWS credentials stored in cluster
- Fine-grained permissions per workload
- Automatic credential rotation

### 3. Least Privilege Access
- Each role has minimal required permissions
- Service-specific policies
- Conditional IAM policies based on service account

### 4. Encryption
- EKS secrets encryption at rest (via KMS)
- TLS for data in transit
- Encrypted EBS volumes for persistent data

### 5. Logging and Monitoring
- CloudWatch logs for control plane
- VPC Flow Logs for network monitoring
- AWS CloudTrail for API audit logging

---

## Deployment Instructions

### Prerequisites
- AWS CLI configured with appropriate credentials
- Terraform >= 1.0
- kubectl installed

### Deploy to Dev Environment

```bash
# Navigate to dev environment
cd environments/dev

# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Apply the configuration
terraform apply

# Configure kubectl
aws eks update-kubeconfig --name ltim-dev-eks --region us-east-1
```

### Deploy to Prod Environment

```bash
# Navigate to prod environment
cd environments/prod

# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Apply the configuration
terraform apply

# Configure kubectl
aws eks update-kubeconfig --name ltim-prod-eks --region us-east-1
```

---

## Next Steps

After deploying the infrastructure, you typically want to:

### 1. Install AWS Load Balancer Controller
```bash
helm repo add eks https://aws.github.io/eks-charts
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=ltim-dev-eks \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
```

### 2. Set up Monitoring
- Install Prometheus and Grafana
- Configure CloudWatch Container Insights
- Set up alerting

### 3. Deploy Applications
- Create namespaces
- Deploy workloads
- Configure ingress

### 4. Set up CI/CD
- Configure GitHub Actions / GitLab CI
- Implement automated deployments
- Set up rollback procedures

### 5. Implement Additional Security
- Pod Security Standards
- Network Policies
- OPA/Gatekeeper for policy enforcement

---

## Troubleshooting

### Common Issues

#### 1. Circular Dependency Error
**Error:** `Error: Cycle: module.eks.data.tls_certificate.eks, module.iam...`

**Solution:** This has been fixed by splitting IAM resources into two modules (iam and iam-oidc)

#### 2. Invalid Count Argument
**Error:** `The "count" value depends on resource attributes that cannot be determined`

**Solution:** Use simplified count conditions based on variables, not computed values:
```hcl
# ✅ Correct
count = var.enable_ebs_csi_driver ? 1 : 0

# ❌ Incorrect
count = var.enable_ebs_csi_driver && module.iam_oidc.role_arn != null ? 1 : 0
```

#### 3. Nodes Not Joining Cluster
**Check:**
- IAM node role has correct policies attached
- Security groups allow communication
- Subnets have proper tags

---

## Summary

**What we've built:**
- Complete EKS infrastructure with networking, IAM, and compute
- Multi-environment support (dev, prod, sandbox)
- Security best practices (IRSA, private subnets, security groups)
- Modular, reusable Terraform code
- Support for persistent storage (EBS CSI)
- Support for load balancing (AWS LB Controller ready)

**What you can do with it:**
- Deploy containerized applications on Kubernetes
- Scale workloads automatically
- Use AWS services securely from pods
- Create persistent storage for databases
- Expose applications via load balancers
- Run production-grade workloads

This is a **production-ready EKS foundation** that follows AWS and Kubernetes best practices! 🚀

---

## Contributing

When making changes:
1. Update documentation
2. Test in dev environment first
3. Create pull requests for review
4. Follow Terraform best practices

## License

[Your License Here]

## Support

For issues or questions, please open an issue in the repository.
