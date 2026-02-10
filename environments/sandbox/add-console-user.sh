#!/bin/bash

# Script to add an IAM user or role to EKS console access
# Usage: ./add-console-user.sh <IAM_ARN> <USERNAME>

set -e

if [ $# -lt 2 ]; then
    echo "Usage: $0 <IAM_ARN> <USERNAME>"
    echo ""
    echo "Examples:"
    echo "  $0 'arn:aws:iam::292481751409:user/john' john"
    echo "  $0 'arn:aws:iam::292481751409:role/AdminRole' AdminRole"
    exit 1
fi

IAM_ARN=$1
USERNAME=$2

# Determine if it's a user or role based on ARN
if [[ $IAM_ARN == *":user/"* ]]; then
    TYPE="user"
    echo "Adding IAM User: $USERNAME"
elif [[ $IAM_ARN == *":role/"* ]]; then
    TYPE="role"
    echo "Adding IAM Role: $USERNAME"
else
    echo "Error: Invalid ARN format. Must be user or role ARN."
    exit 1
fi

# Update terraform.tfvars
echo ""
echo "Updating terraform.tfvars..."

if [ "$TYPE" == "user" ]; then
    # Add to aws_auth_users
    cat >> terraform.tfvars <<EOF

# Added console user: $USERNAME
aws_auth_users = [
  {
    userarn  = "arn:aws:iam::292481751409:user/terraformuser"
    username = "terraformuser"
    groups   = ["system:masters"]
  },
  {
    userarn  = "$IAM_ARN"
    username = "$USERNAME"
    groups   = ["system:masters"]
  }
]
EOF
else
    # Add to aws_auth_roles
    cat >> terraform.tfvars <<EOF

# Added console role: $USERNAME
aws_auth_roles = [
  {
    rolearn  = "arn:aws:iam::292481751409:role/terraformrole"
    username = "terraformrole"
    groups   = ["system:masters"]
  },
  {
    rolearn  = "$IAM_ARN"
    username = "$USERNAME"
    groups   = ["system:masters"]
  }
]
EOF
fi

echo "✓ Updated terraform.tfvars"
echo ""
echo "Next steps:"
echo "1. Review the changes: cat terraform.tfvars"
echo "2. Apply the changes: terraform apply"
echo "3. Attach IAM policy to the user/role:"
if [ "$TYPE" == "user" ]; then
    echo "   aws iam attach-user-policy --user-name $USERNAME --policy-arn arn:aws:iam::292481751409:policy/ltim-sandbox-eks-console-access"
else
    echo "   aws iam attach-role-policy --role-name $USERNAME --policy-arn arn:aws:iam::292481751409:policy/ltim-sandbox-eks-console-access"
fi
