terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Variables
variable "aws_region" {
  description = "AWS region"
  type        = string
}



variable "cluster_name" {
  description = "Cluster name for naming resources"
  type        = string
  default     = "hcp"
}

variable "ec2_os" {
  description = "Operating system for EC2 instance"
  type        = string
  default     = "rhel10"
  validation {
    condition = contains(["rhel10", "ubuntu"], var.ec2_os)
    error_message = "Supported OS types: rhel10, ubuntu"
  }
}

# Data sources
data "aws_caller_identity" "current" {}

# Find ELB with specific labels to get its subnet
data "aws_lb" "reference_elb" {
  tags = {
    "api.openshift.com/name" = var.cluster_name
  }
}

# Get subnet from the reference ELB
data "aws_subnet" "public" {
  id = tolist(data.aws_lb.reference_elb.subnets)[0]
}

data "aws_vpc" "selected" {
  id = data.aws_subnet.public.vpc_id
}

# Region-specific canonical user IDs for VM Export
locals {
  canonical_user_ids = {
    "af-south-1"     = "3f7744aeebaf91dd60ab135eb1cf908700c8d2bc9133e61261e6c582be6e33ee"  # Africa (Cape Town)
    "ap-east-1"      = "97ee7ab57cc9b5034f31e107741a968e595c0d7a19ec23330eae8d045a46edfb"  # Asia Pacific (Hong Kong)
    "ap-south-2"     = "77ab5ec9eac9ade710b7defed37fe0640f93c5eb76ea65a64da49930965f18ca"  # Asia Pacific (Hyderabad)
    "ap-southeast-3" = "de34aaa6b2875fa3d5086459cb4e03147cf1a9f7d03d82f02bedb991ff3d1df5"  # Asia Pacific (Jakarta)
    "ap-southeast-5" = "ed006f67543afcfe0779e356e52d5ed53fa45f95bcd7d277147dfc027aaca0e7"  # Asia Pacific (Malaysia)
    "ap-southeast-4" = "8b8ea36ab97c280aa8558c57a380353ac7712f01f82c21598afbb17e188b9ad5"  # Asia Pacific (Melbourne)
    "ap-northeast-3" = "40f22ffd22d6db3b71544ed6cd00c8952d8b0a63a87d58d5b074ec60397db8c9"  # Asia Pacific (Osaka)
    "ap-northeast-4" = "a9fa0eb7c8483f9558cd14b24d16e9c4d1555261a320b586a3a06908ff0047ce"  # Asia Pacific (Taipei)
    "ap-southeast-6" = "d011fe83abcc227a7ac0f914ce411d3630c4ef735e92e88ce0aa796dcfecfbdd"  # Asia Pacific (Thailand)
    "ca-west-1"      = "78e12f8d798f89502177975c4ccdac686c583765cea2bf06e9b34224e2953c83"  # Canada West (Calgary)
    "eu-south-1"     = "04636d9a349e458b0c1cbf1421858b9788b4ec28b066148d4907bb15c52b5b9c"  # Europe (Milan)
    "eu-south-2"     = "6e81c4c52a37a7f59e103625162ed97bcd0e646593adb107d21310d093151518"  # Europe (Spain)
    "eu-central-2"   = "5d9fcea77b2fb3df05fc15c893f212ae1d02adb4b24c13e18586db728a48da67"  # Europe (Zurich)
    "il-central-1"   = "328a78de7561501444823ebeb59152eca7cb58fee2fe2e4223c2cdd9f93ae931"  # Israel (Tel Aviv)
    "mx-central-1"   = "edaff67fe25d544b855bd0ba9a74a99a2584ab89ceda0a9661bdbeca530d0fca"  # Mexico (Central)
    "me-south-1"     = "aa763f2cf70006650562c62a09433f04353db3cba6ba6aeb3550fdc8065d3d9f"  # Middle East (Bahrain)
    "me-central-1"   = "7d3018832562b7b6c126f5832211fae90bd3eee3ed3afde192d990690267e475"  # Middle East (UAE)
    "us-gov-east-1"  = "af913ca13efe7a94b88392711f6cfc8aa07c9d1454d4f190a624b126733a5602"  # AWS GovCloud (US-East)
    "us-gov-west-1"  = "af913ca13efe7a94b88392711f6cfc8aa07c9d1454d4f190a624b126733a5602"  # AWS GovCloud (US-West)
  }
  
  # Get the canonical user ID for the current region, fallback to default for all other regions
  canonical_user_id = lookup(local.canonical_user_ids, var.aws_region, "c4d8eabf8db69dbe46bfe0e517100c554f01200b104d59cd408e777ba442a322")
}

# AMI lookups for different OS types
data "aws_ami" "rhel10" {
  most_recent = true
  owners      = ["309956199498"] # Red Hat's AWS account ID

  filter {
    name   = "name"
    values = ["RHEL-10.*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}





# Local values for AMI selection and user data
locals {
  ami_map = {
    rhel10 = data.aws_ami.rhel10.id
    ubuntu = data.aws_ami.ubuntu.id
  }

  user_data_map = {
    rhel10 = <<-EOF
#!/bin/bash
# Update packages
yum update -y

# Install and configure Apache
yum install -y httpd
systemctl start httpd
systemctl enable httpd

# Create web content
echo "<h1>Hello from RHEL 10 on EC2</h1>" > /var/www/html/index.html

# Ensure Apache is running
systemctl restart httpd
systemctl status httpd
EOF

    ubuntu = <<-EOF
#!/bin/bash
# Update packages
apt update -y

# Install and configure Apache
apt install -y apache2
systemctl start apache2
systemctl enable apache2

# Create web content with proper permissions
echo "<h1>Hello from Ubuntu 24.04 on EC2</h1>" > /var/www/html/index.html
chown www-data:www-data /var/www/html/index.html
chmod 644 /var/www/html/index.html

# Ensure Apache is running
systemctl restart apache2
systemctl status apache2
EOF




  }
}

# Random bucket name
resource "random_id" "bucket_suffix" {
  byte_length = 8
}

# S3 Bucket for EC2 Export
resource "aws_s3_bucket" "ec2_export" {
  bucket = "ec2-export-${var.cluster_name}-${random_id.bucket_suffix.hex}"
}

resource "aws_s3_bucket_ownership_controls" "ec2_export" {
  bucket = aws_s3_bucket.ec2_export.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_policy" "ec2_export" {
  bucket = aws_s3_bucket.ec2_export.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "GrantReadAclAndWrite"
        Effect = "Allow"
        Principal = {
          CanonicalUser = local.canonical_user_id
        }
        Action = [
          "s3:GetBucketAcl",
          "s3:PutObject"
        ]
        Resource = [
          aws_s3_bucket.ec2_export.arn,
          "${aws_s3_bucket.ec2_export.arn}/*"
        ]
      }
    ]
  })
}

# Security Group for EFS
resource "aws_security_group" "efs" {
  name_prefix = "efs-${var.cluster_name}-"
  vpc_id      = data.aws_vpc.selected.id

  ingress {
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.selected.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "efs-${var.cluster_name}"
  }
}

# Security Group for EC2 Instance
resource "aws_security_group" "ec2_web" {
  name_prefix = "ec2-web-${var.cluster_name}-"
  vpc_id      = data.aws_vpc.selected.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP from anywhere"
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH from anywhere"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ec2-web-${var.cluster_name}"
  }
}

# EFS File System
resource "aws_efs_file_system" "export" {
  creation_token = "ec2-export-${var.cluster_name}-${random_id.bucket_suffix.hex}"
  
  tags = {
    Name = "ec2-export-${var.cluster_name}-${random_id.bucket_suffix.hex}"
  }
}

# EFS Mount Target
resource "aws_efs_mount_target" "export" {
  file_system_id  = aws_efs_file_system.export.id
  subnet_id       = data.aws_subnet.public.id
  security_groups = [aws_security_group.efs.id]
}

# IAM Role for DataSync S3 Access
resource "aws_iam_role" "datasync_s3" {
  name = "DataSyncS3Role-${var.cluster_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "datasync.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "datasync_s3" {
  name = "DataSyncS3Policy"
  role = aws_iam_role.datasync_s3.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetBucketLocation",
          "s3:ListBucket",
          "s3:ListBucketMultipartUploads"
        ]
        Resource = aws_s3_bucket.ec2_export.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:AbortMultipartUpload",
          "s3:DeleteObject",
          "s3:GetObject",
          "s3:ListMultipartUploadParts",
          "s3:PutObject",
          "s3:GetObjectTagging",
          "s3:PutObjectTagging"
        ]
        Resource = "${aws_s3_bucket.ec2_export.arn}/*"
      }
    ]
  })
}

# IAM Role for DataSync EFS Access
resource "aws_iam_role" "datasync_efs" {
  name = "DataSyncEFSRole-${var.cluster_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "datasync.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "datasync_efs" {
  name = "DataSyncEFSPolicy"
  role = aws_iam_role.datasync_efs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "elasticfilesystem:ClientMount",
          "elasticfilesystem:ClientWrite",
          "elasticfilesystem:ClientRootAccess"
        ]
        Resource = aws_efs_file_system.export.arn
      }
    ]
  })
}

# DataSync S3 Location
resource "aws_datasync_location_s3" "export" {
  s3_bucket_arn = aws_s3_bucket.ec2_export.arn
  subdirectory  = "/"

  s3_config {
    bucket_access_role_arn = aws_iam_role.datasync_s3.arn
  }

  depends_on = [aws_iam_role_policy.datasync_s3]
}

# DataSync EFS Location
resource "aws_datasync_location_efs" "export" {
  efs_file_system_arn = aws_efs_file_system.export.arn
  subdirectory        = "/"

  ec2_config {
    security_group_arns = [aws_security_group.efs.arn]
    subnet_arn         = "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:subnet/${data.aws_subnet.public.id}"
  }

  depends_on = [aws_efs_mount_target.export]
}

# DataSync Task
resource "aws_datasync_task" "s3_to_efs" {
  destination_location_arn = aws_datasync_location_efs.export.arn
  name                     = "S3-to-EFS-Export-Transfer-${var.cluster_name}"
  source_location_arn      = aws_datasync_location_s3.export.arn

  options {
    verify_mode                = "POINT_IN_TIME_CONSISTENT"
    overwrite_mode            = "ALWAYS"
    atime                     = "BEST_EFFORT"
    mtime                     = "PRESERVE"
    uid                       = "NONE"
    gid                       = "NONE"
    preserve_deleted_files    = "PRESERVE"
    preserve_devices          = "NONE"
    posix_permissions         = "PRESERVE"
  }
}

# Key Pair (assumes you have a public key)
resource "aws_key_pair" "export_key" {
  key_name   = "${var.cluster_name}-export-key"
  public_key = file("~/.ssh/id_rsa.pub")
}

# EC2 Instance for Export
resource "aws_instance" "export_instance" {
  ami                    = local.ami_map[var.ec2_os]
  instance_type          = "t3.micro"
  key_name               = aws_key_pair.export_key.key_name
  subnet_id              = data.aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.ec2_web.id]

  associate_public_ip_address = true

  user_data = base64encode(local.user_data_map[var.ec2_os])

  tags = {
    Name = "export-instance-${var.cluster_name}"
  }
}

# Outputs

output "ec2_export_command" {
  description = "CLI to export EC2"
  value = "aws ec2 create-instance-export-task --instance-id ${aws_instance.export_instance.id} --target-environment vmware --export-to-s3-task DiskImageFormat=VMDK,ContainerFormat=ova,S3Bucket=${aws_s3_bucket.ec2_export.bucket},S3Prefix=ova/ --region ${var.aws_region}"
}

output "datasync_execution_command" {
  description = "CLI to run DataSync task"
  value = "aws datasync start-task-execution --task-arn ${aws_datasync_task.s3_to_efs.arn} --region ${var.aws_region}"
}

output "curl_test_command" {
  description = "CLI to test webserver"
  value = "curl -s http://${aws_instance.export_instance.public_dns}"
}

output "efs_dns_name" {
  description = "DNS name of EFS"
  value = aws_efs_file_system.export.dns_name
}

output "s3_bucket_name" {
  description = "S3 bucket name for EC2 export"
  value = aws_s3_bucket.ec2_export.bucket
}

output "ec2_os_selected" {
  description = "Operating system deployed on EC2 instance"
  value = var.ec2_os
}