provider "aws" {
  access_key = "${var.aws_access_key}"
  secret_key = "${var.aws_secret_key}"
  region     = "${var.region}"

  assume_role {
    role_arn = "${var.role_arn}"
  }
}

provider "github" {
  token        = "${var.github_token}"
  organization = "${var.github_organization}"
}
