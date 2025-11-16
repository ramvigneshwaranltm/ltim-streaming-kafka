# Backend configuration for Terraform state
# Update these values according to your S3 bucket and DynamoDB table

bucket         = "your-terraform-state-bucket"
key            = "ltim/prod/terraform.tfstate"
region         = "eu-west-1"
encrypt        = true
dynamodb_table = "terraform-state-lock"
