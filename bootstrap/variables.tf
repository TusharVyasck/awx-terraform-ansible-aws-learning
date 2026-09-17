variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "key_pair_name" {
  description = "Name for the EC2 key pair this bootstrap creates. Must match terraform/variables.tf key_name."
  type        = string
  default     = "awx-learning-key"
}
