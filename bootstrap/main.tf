# -----------------------------------------------------------------------
# Run this ONCE, locally, with your AWS keys as inputs (env vars or your
# default AWS CLI profile both work — this just needs the aws provider
# to be able to authenticate).
#
#   cd bootstrap
#   terraform init
#   terraform apply
#
# Replaces AWS Console → EC2 → Key Pairs → Create.
# -----------------------------------------------------------------------

resource "tls_private_key" "node_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "node_key" {
  key_name   = var.key_pair_name
  public_key = tls_private_key.node_key.public_key_openssh
}

# Saved locally so you can paste it into an AWX Machine credential.
# Git-ignored — never commit this.
resource "local_sensitive_file" "private_key_pem" {
  content         = tls_private_key.node_key.private_key_pem
  filename        = "${path.module}/${var.key_pair_name}.pem"
  file_permission = "0600"
}

data "aws_caller_identity" "current" {}

# --- Remote state backend for terraform/ — S3 bucket + DynamoDB lock table.
# This is the one exception to "always use remote state": bootstrap itself
# has to use local state, because these resources don't exist yet.
resource "aws_s3_bucket" "tf_state" {
  bucket = "awx-learning-tfstate-${data.aws_caller_identity.current.account_id}"

  # Convenient for a learning project so `terraform destroy` here can
  # clean the bucket up too. Remove this in anything that matters.
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tf_state" {
  bucket                  = aws_s3_bucket.tf_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "tf_lock" {
  name         = "awx-learning-tfstate-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}

output "tf_state_bucket" {
  value = aws_s3_bucket.tf_state.bucket
}

output "tf_state_dynamodb_table" {
  value = aws_dynamodb_table.tf_lock.name
}

output "key_pair_name" {
  value = aws_key_pair.node_key.key_name
}

output "private_key_local_path" {
  value = local_sensitive_file.private_key_pem.filename
}
