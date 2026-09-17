variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t2.micro"
}

variable "instance_count" {
  description = "Number of EC2 instances to create"
  type        = number
  default     = 2
}

variable "key_name" {
  description = "Name of an existing EC2 key pair. Created automatically by ../bootstrap — no AWS Console step needed. Only override this if you changed key_pair_name in bootstrap/variables.tf."
  type        = string
  default     = "awx-learning-key"
}

variable "project_tag" {
  description = "Tag applied to all resources so AWX's dynamic inventory can find them"
  type        = string
  default     = "awx-learning"
}

variable "allowed_ssh_cidr" {
  description = "CIDR allowed to SSH into instances. REPLACE with your own IP/32 for safety instead of 0.0.0.0/0."
  type        = string
  default     = "0.0.0.0/0"
}
