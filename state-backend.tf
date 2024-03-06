terraform {
 # Reference: https://www.terraform.io/language/settings/backends/s3
 backend "s3" {
 bucket = "rtc2024q1-terraform-state-1"
 key = "stage/services/webserver-cluster/terraform.tfstate"
 region = "ap-south-1"
 dynamodb_table = "terraform_locks"
 encrypt = true
 }
}