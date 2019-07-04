variable "region" {
  default = "ap-northeast-1"
}

variable "aws_access_key" {}

variable "aws_secret_key" {}

variable "role_arn" {}

variable "vpc_id" {
  default = "vpc-XXXXXXXX"
}

variable "subnets" {
  default = [
    "subnet-XXXXXXXX",
    "subnet-XXXXXXXX",
    "subnet-XXXXXXXX"
  ]
}

variable "github_token" {}

variable "github_organization" {}
