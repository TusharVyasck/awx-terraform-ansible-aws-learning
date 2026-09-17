terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Left empty on purpose (a "partial configuration"). The actual bucket,
  # key, region, and lock table come from ansible/group_vars/all/terraform_backend.yml
  # via the playbook's backend_config, so this file has no hardcoded
  # values that would tie it to one AWS account.
  backend "s3" {}
}

# NOTE: No access_key/secret_key here on purpose.
# When this runs as an AWX Job Template with an "Amazon Web Services"
# credential attached, AWX injects AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY
# (and AWS_SESSION_TOKEN if using temporary creds) as environment variables
# automatically, and the AWS provider picks them up on its own.
provider "aws" {
  region = var.aws_region
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

resource "aws_security_group" "awx_learning_sg" {
  name        = "${var.project_tag}-sg"
  description = "Allow SSH and HTTP for the AWX learning project"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Project = var.project_tag
  }
}

resource "aws_instance" "node" {
  count                  = var.instance_count
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.awx_learning_sg.id]

  tags = {
    Name    = "${var.project_tag}-node-${count.index}"
    Project = var.project_tag
    Role    = "web"
  }
}

output "instance_public_ips" {
  value = aws_instance.node[*].public_ip
}

output "instance_ids" {
  value = aws_instance.node[*].id
}
