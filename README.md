# EC2 to OpenShift Virtualization Migration Tutorial

**Objective:** Migrate an EC2 instance to OpenShift Virtualization by exporting it to S3, syncing to EFS, and importing as a VM.

## Prerequisites:
- ROSA cluster running
- AWS CLI configured
- SSH public key at `~/.ssh/id_rsa.pub`
- Terraform installed
- oc CLI connected to cluster

## Tutorial

### 1. Deploy Operators
```bash
oc apply -k yaml/operators/
```

### 2. Verify CRDs
```bash
oc get crd hyperconvergeds.hco.kubevirt.io
oc get crd forkliftcontrollers.forklift.konveyor.io
```

### 3. Deploy Custom Resources
```bash
oc apply -k yaml/custom-resources/
```

### 4. Deploy Infrastructure
```bash
terraform apply -var="aws_region=eu-west-3" -var="cluster_name=fja-hcp"
```

### 5. Test EC2 Instance
```bash
$(terraform output -raw curl_test_command)
```

### 6. Export EC2 to S3
```bash
$(terraform output -raw ec2_export_command)
```

### 7. Start DataSync Task (when export is done)
```bash
$(terraform output -raw datasync_execution_command)
```

### 8. Start Migration in OpenShift Console
Navigate to Migration → Virtualization in the OpenShift console to complete the migration. 