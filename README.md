# EC2 Export to EFS via DataSync - Terraform

This Terraform configuration sets up the complete infrastructure for exporting EC2 instances to EFS via AWS DataSync.

## What it creates:
- S3 bucket (with random name) for EC2 export
- EFS file system for storage
- DataSync locations and task
- IAM roles and policies
- EC2 instance for export (with automatic RHEL 10 AMI detection)
- Security groups and networking
- **Automatic region-specific canonical user ID selection** for S3 bucket policy

## Usage:

1. **Configure variables:**
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your values
   ```

2. **Deploy infrastructure:**
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

3. **Run EC2 export:**
   ```bash
   # Use the command from terraform output
   terraform output ec2_export_command
   ```

4. **Start DataSync transfer:**
   ```bash
   # Use the command from terraform output  
   terraform output datasync_execution_command
   ```

5. **Get EFS mount URL for Forklift:**
   ```bash
   terraform output efs_mount_command
   ```

6. **Verify selected RHEL 10 AMI (optional):**
   ```bash
   terraform output rhel10_ami_id
   terraform output rhel10_ami_name
   ```

7. **Verify canonical user ID (optional):**
   ```bash
   terraform output canonical_user_id
   ```

## Required Variables:
- `aws_region`: AWS region to deploy resources
- `subnet_id`: Subnet ID for EFS mount target and EC2 instance
- `cluster_name`: Name prefix for resources (optional, defaults to "hcp")

## Features:

### Automatic Canonical User ID Selection
The configuration automatically selects the correct AWS canonical user ID based on your region. This is required for EC2 VM export to S3. The mapping includes:

- Special regions (GovCloud, new regions like Jakarta, Malaysia, etc.)
- Falls back to the default canonical user ID for standard regions
- No manual configuration needed - just specify your region

### Automatic RHEL 10 AMI Detection
The configuration automatically finds the latest RHEL 10 AMI for your specified region:

- Searches for the most recent RHEL 10 AMI in the target region
- Uses Red Hat's official AWS account (309956199498)
- Filters for x86_64 architecture and HVM virtualization
- No need to hardcode region-specific AMI IDs

## Prerequisites:
- AWS CLI configured
- SSH public key at `~/.ssh/id_rsa.pub`
- Terraform installed 