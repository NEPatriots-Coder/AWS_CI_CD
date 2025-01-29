terraform {
  backend "s3" {
    bucket         = "cicd-terraform-state-lw"
    key            = "terraform.tfstate"
    region         = "us-east-2"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
  }
}