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

### 8. Create OVA Provider in OpenShift Console
1. Navigate to **Migration → Providers for virtualization**
2. Click **Create Provider**
3. Select **Open Virtual Appliance (OVA)**
4. Enter provider name and EFS NFS URL: `$(terraform output -raw efs_dns_name):/ova`
5. Click **Create**
*(Provider should be created in openshift-mtv namespace)*

### 9. Create Migration Plan
1. Create destination namespace: `oc new-project ec2-vm`
2. Navigate to **Migration → Plans for virtualization**
3. Click **Create Plan**
4. Select your OVA provider as source
5. Select VMs to migrate
6. Create network and storage mappings
7. Select ec2-vm as target namespace
8. Click **Create migration plan**
*(Migration should be created in openshift-mtv namespace)*

### 10. Start Migration and VM
1. Click **Start** on your migration plan
2. Wait for migration to complete
3. Navigate to **Virtualization → Virtual Machines**
4. Select ec2-vm namespace
5. Your migrated VM will appear - click to start it
*(VM will be created in ec2-vm namespace)*

### 11. Expose VM via Service and Route
```bash
VM_NAME=$(oc get vm -n ec2-vm -o jsonpath='{.items[0].metadata.name}')
oc create service clusterip vm-service --tcp=80:80 -n ec2-vm
oc patch service vm-service -n ec2-vm -p '{"spec":{"selector":{"app":"'$VM_NAME'"}}}'
oc create route edge vm-route --service=vm-service -n ec2-vm
```

### 12. Test VM via Route
```bash
ROUTE_URL=$(oc get route vm-route -n ec2-vm -o jsonpath='{.spec.host}')
curl -s https://$ROUTE_URL
```

### 13. One More Thing...
```bash
virtctl ssh fedora@$VM_NAME -n ec2-vm
sudo sed -i "s/EC2/OpenShift Virt/g" /var/www/html/index.html
exit
curl -s https://$ROUTE_URL
```
*Now it says "Hello from RHEL 10 on OpenShift Virt" - Migration complete! 🎉* 