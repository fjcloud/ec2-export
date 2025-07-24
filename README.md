# EC2 to OpenShift Virtualization Migration Tutorial

**Objective:** Migrate an EC2 instance to OpenShift Virtualization by exporting it to S3, syncing to EFS, and importing as a VM.

## Set Environment Variables
```bash
export CLUSTER_NAME="your-cluster-name"
export AWS_REGION="your-aws-region"
export EC2_OS="rhel10"  # Options: rhel10, ubuntu
```

### OS Options:
- **rhel10**: Red Hat Enterprise Linux 10 (default)
- **ubuntu**: Ubuntu 24.04 LTS Server

**Note**: All instances use t3.micro and are configured for **SSH key authentication only** - password authentication is disabled for security.

## Prerequisites:
- ROSA 4.19.x cluster running
- AWS CLI configured
- SSH public key at `~/.ssh/id_rsa.pub` (**REQUIRED** - password auth disabled)
- Terraform installed
- oc CLI connected to cluster
- virtctl

## Tutorial

### 1. Add Bare Metal Worker Node
```bash
rosa create machine-pool -c $CLUSTER_NAME --name bm --replicas=1 --instance-type c5n.metal
```

### 2. Deploy Operators
```bash
oc apply -k yaml/operators/
```

### 3. Wait for CRDs
```bash
oc get crd hyperconvergeds.hco.kubevirt.io
oc get crd forkliftcontrollers.forklift.konveyor.io
```

### 4. Deploy Custom Resources
```bash
oc apply -k yaml/custom-resources/
```

### 5. Deploy Infrastructure
```bash
terraform apply -var="aws_region=$AWS_REGION" -var="cluster_name=$CLUSTER_NAME" -var="ec2_os=$EC2_OS"
```

### 6. Test EC2 Instance
```bash
$(terraform output -raw curl_test_command)
```

### 7. Export EC2 to OVA and store it to S3
```bash
$(terraform output -raw ec2_export_command)
# Show status of task
aws ec2 describe-export-tasks --region $AWS_REGION | jq .ExportTasks[0].State
# Wait for export completed
aws ec2 wait export-task-completed --region $AWS_REGION
```
*Could take 15min ☕*

### 8. Start DataSync Task (when export is done)
```bash
$(terraform output -raw datasync_execution_command)
```

### 9. Create OVA Provider in OpenShift Console
1. Navigate to **Migration → Providers for virtualization**
2. Click **Create Provider**
3. Select **Open Virtual Appliance (OVA)**
4. Enter provider name and EFS NFS URL: `terraform output -raw efs_dns_name` and path `:/ova`
5. Click **Create**
*(Provider should be created in openshift-mtv namespace)*

### 10. Create Migration Plan
1. Create destination namespace: `oc new-project ec2-vm`
2. Navigate to **Migration → Plans for virtualization**
3. Click **Create Plan**
4. Select your OVA provider as source
5. Select VMs to migrate
6. Create network and storage mappings
7. Select ec2-vm as target namespace
8. Click **Create migration plan**
*(Migration should be created in openshift-mtv namespace)*

### 11. Start Migration and VM
1. Click **Start** on your migration plan
2. Wait for migration to complete
3. Navigate to **Virtualization → Virtual Machines**
4. Select ec2-vm namespace
5. Your migrated VM will appear - click to start it
*(VM will be created in ec2-vm namespace)*

### 12. Expose VM via Service and Route
```bash
VM_NAME=$(oc get vm -n ec2-vm -o jsonpath='{.items[0].metadata.name}')
oc create service clusterip vm-service --tcp=80:80 -n ec2-vm
oc patch service vm-service -n ec2-vm -p '{"spec":{"selector":{"app":"'$VM_NAME'"}}}'
oc create route edge vm-route --service=vm-service -n ec2-vm
```

### 13. Test VM via Route
```bash
ROUTE_URL=$(oc get route vm-route -n ec2-vm -o jsonpath='{.spec.host}')
curl -s https://$ROUTE_URL
```

### 14. One More Thing...
```bash
# SSH user depends on OS: 
# - ec2-user (RHEL)
# - ubuntu (Ubuntu)
# 
# Note: SSH key authentication only - use your private key
virtctl ssh ec2-user@$VM_NAME -n ec2-vm  # Adjust username based on your OS

# Modify the web page content
sudo sed -i "s/EC2/OpenShift Virt/g" /var/www/html/index.html

exit
curl -s https://$ROUTE_URL
```
*Now it says "Hello from RHEL 10 on OpenShift Virt" - Migration complete! 🎉*

## Cleanup

### Remove S3 Bucket and AWS Resources
```bash
# Get bucket name from terraform (if it exists)
BUCKET_NAME=$(terraform output -raw s3_bucket_name)

# Empty bucket
aws s3 rm s3://$BUCKET_NAME --recursive --region $AWS_REGION

# Destroy Terraform infrastructure
terraform destroy -var="aws_region=$AWS_REGION" -var="cluster_name=$CLUSTER_NAME" -var="ec2_os=$EC2_OS"
```

### Remove Bare Metal Machine Pool
```bash
rosa delete machine-pool bm -c $CLUSTER_NAME --yes
```