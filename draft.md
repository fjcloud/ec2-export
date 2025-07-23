```shell
AWS_REGION=eu-west-3
CLUSTER_NAME=fja-hcp
```
# NFS Network Authorization

```shell
NODE=$(oc get nodes --selector=node-role.kubernetes.io/worker \
  -o jsonpath='{.items[0].metadata.name}')
VPC=$(aws ec2 describe-instances \
  --filters "Name=private-dns-name,Values=$NODE" \
  --query 'Reservations[*].Instances[*].{VpcId:VpcId}' \
  --region $AWS_REGION \
  | jq -r '.[0][0].VpcId')
CIDR=$(aws ec2 describe-vpcs \
  --filters "Name=vpc-id,Values=$VPC" \
  --query 'Vpcs[*].CidrBlock' \
  --region $AWS_REGION \
  | jq -r '.[0]')
SG=$(aws ec2 describe-instances --filters \
  "Name=private-dns-name,Values=$NODE" \
  --query 'Reservations[*].Instances[*].{SecurityGroups:SecurityGroups}' \
  --region $AWS_REGION \
  | jq -r '.[0][0].SecurityGroups[0].GroupId')
echo "CIDR - $CIDR,  SG - $SG"

aws ec2 authorize-security-group-ingress \
 --group-id $SG \
 --protocol tcp \
 --port 2049 \
 --region $AWS_REGION \
 --cidr $CIDR | jq .
```

# Add bare metal for vm

```shell
rosa create machine-pool -c fja-hcp --name bm --replicas=1 --instance-type c5n.metal
```

# Add needed operator

```shell
oc apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: openshift-cnv
  labels:
    openshift.io/cluster-monitoring: "true"
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: kubevirt-hyperconverged-group
  namespace: openshift-cnv
spec:
  targetNamespaces:
    - openshift-cnv
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: hco-operatorhub
  namespace: openshift-cnv
spec:
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  name: kubevirt-hyperconverged
  startingCSV: kubevirt-hyperconverged-operator.v4.19.1
  channel: "stable" 
EOF
oc apply -f - <<EOF
apiVersion: hco.kubevirt.io/v1beta1
kind: HyperConverged
metadata:
  name: kubevirt-hyperconverged
  namespace: openshift-cnv
spec:
EOF
````

```shell
cat << EOF | oc apply -f -
apiVersion: project.openshift.io/v1
kind: Project
metadata:
  name: openshift-mtv
EOF

cat << EOF | oc apply -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: migration
  namespace: openshift-mtv
spec:
  targetNamespaces:
    - openshift-mtv
EOF

cat << EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: mtv-operator
  namespace: openshift-mtv
spec:
  channel: release-v2.9
  installPlanApproval: Automatic
  name: mtv-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  startingCSV: "mtv-operator.v2.9.0"
EOF

sleep 10

oc rollout status deploy/forklift-operator-ansible -n openshift-mtv -w

cat << EOF | oc apply -f -
apiVersion: forklift.konveyor.io/v1beta1
kind: ForkliftController
metadata:
  name: forklift-controller
  namespace: openshift-mtv
spec:
  olm_managed: true
EOF
```

```shell
EFS=$(aws efs create-file-system --creation-token efs-token-1 \
   --region ${AWS_REGION} \
   --encrypted | jq -r '.FileSystemId')
echo $EFS
for SUBNET in $(aws ec2 describe-subnets \
  --filters Name=vpc-id,Values=$VPC Name='tag:kubernetes.io/role/internal-elb',Values='*' \
  --query 'Subnets[*].{SubnetId:SubnetId}' \
  --region $AWS_REGION \
  | jq -r '.[].SubnetId'); do \
    MOUNT_TARGET=$(aws efs create-mount-target --file-system-id $EFS \
       --subnet-id $SUBNET --security-groups $SG \
       --region $AWS_REGION \
       | jq -r '.MountTargetId'); \
    echo $MOUNT_TARGET; \
 done
```

```shell
# Set your bucket name
BUCKET_NAME="ec2-export-$CLUSTER_NAME"

# Create the S3 bucket in eu-west-3
aws s3 mb s3://$BUCKET_NAME --region $AWS_REGION

# Set object ownership to "Bucket owner preferred"
aws s3api put-bucket-ownership-controls \
    --bucket $BUCKET_NAME \
    --ownership-controls Rules='[{ObjectOwnership=BucketOwnerPreferred}]'

# Create the bucket policy file
cat > bucket-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "GrantReadAclAndWrite",
            "Effect": "Allow",
            "Principal": {
                "CanonicalUser": "c4d8eabf8db69dbe46bfe0e517100c554f01200b104d59cd408e777ba442a322"
            },
            "Action": [
                "s3:GetBucketAcl",
                "s3:PutObject"
            ],
            "Resource": [
                "arn:aws:s3:::$BUCKET_NAME",
                "arn:aws:s3:::$BUCKET_NAME/*"
            ]
        }
    ]
}
EOF

# Apply the bucket policy
aws s3api put-bucket-policy --bucket $BUCKET_NAME --policy file://bucket-policy.json

# Clean up the policy file
rm bucket-policy.json
```

```shell
# Set variables
AMI_ID="ami-0cfda8538783a8826"
INSTANCE_TYPE="t3.micro"
KEY_NAME="fja-key"
SUBNET_ID="subnet-038c2ca8fa2f5c040"

aws ec2 import-key-pair \
    --key-name $KEY_NAME \
    --public-key-material fileb://~/.ssh/id_rsa.pub \
    --region $AWS_REGION

# Create user-data script for httpd installation
cat > user-data.txt << 'EOF'
#!/bin/bash
yum update -y
yum install -y httpd
systemctl start httpd
systemctl enable httpd
echo "<h1>Hello from RHEL 10 on EC2</h1>" > /var/www/html/index.html
systemctl status httpd
EOF

# Launch the EC2 instance
aws ec2 run-instances \
    --image-id $AMI_ID \
    --count 1 \
    --instance-type $INSTANCE_TYPE \
    --key-name $KEY_NAME \
    --subnet-id $SUBNET_ID \
    --user-data file://user-data.txt \
    --associate-public-ip-address \
    --region $AWS_REGION

# Clean up user-data file
rm user-data.txt
```

```shell
aws ec2 create-instance-export-task     --instance-id i-0b7630bf472e555ad     --target-environment vmware     --export-to-s3-task DiskImageFormat=VMDK,ContainerFormat=ova,S3Bucket=ec2-export-fja-hcp,S3Prefix=ova/ --region eu-west-3
```


```shell
# Set variables
BUCKET_NAME="ec2-export-fja-hcp"
AWS_REGION="eu-west-3"  # Replace with your actual region
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)


# Create DataSync service role for S3
cat > datasync-s3-trust-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "datasync.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF

# Create S3 access policy
cat > datasync-s3-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetBucketLocation",
                "s3:ListBucket",
                "s3:ListBucketMultipartUploads"
            ],
            "Resource": "arn:aws:s3:::$BUCKET_NAME"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:AbortMultipartUpload",
                "s3:DeleteObject",
                "s3:GetObject",
                "s3:ListMultipartUploadParts",
                "s3:PutObject",
                "s3:GetObjectTagging",
                "s3:PutObjectTagging"
            ],
            "Resource": "arn:aws:s3:::$BUCKET_NAME/*"
        }
    ]
}
EOF

cat > datasync-efs-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "elasticfilesystem:ClientMount",
                "elasticfilesystem:ClientWrite",
                "elasticfilesystem:ClientRootAccess"
            ],
            "Resource": "arn:aws:elasticfilesystem:$AWS_REGION:$ACCOUNT_ID:file-system/$EFS"
        }
    ]
}
EOF

# Create IAM roles
aws iam create-role \
    --role-name DataSyncS3Role \
    --assume-role-policy-document file://datasync-s3-trust-policy.json

aws iam create-role \
    --role-name DataSyncEFSRole \
    --assume-role-policy-document file://datasync-s3-trust-policy.json

# Attach policies to roles
aws iam put-role-policy \
    --role-name DataSyncS3Role \
    --policy-name DataSyncS3Policy \
    --policy-document file://datasync-s3-policy.json

aws iam put-role-policy \
    --role-name DataSyncEFSRole \
    --policy-name DataSyncEFSPolicy \
    --policy-document file://datasync-efs-policy.json
```
```shell
# Get IAM role ARNs
S3_ROLE_ARN=$(aws iam get-role --role-name DataSyncS3Role --query 'Role.Arn' --output text)

# Create S3 location
S3_LOCATION_ARN=$(aws datasync create-location-s3 \
    --s3-bucket-arn "arn:aws:s3:::$BUCKET_NAME" \
    --s3-config BucketAccessRoleArn=$S3_ROLE_ARN \
    --subdirectory "/" \
    --region $AWS_REGION \
    --query 'LocationArn' --output text)
# Create EFS location with your existing subnet and security group
EFS_LOCATION_ARN=$(aws datasync create-location-efs \
    --efs-filesystem-arn "arn:aws:elasticfilesystem:$AWS_REGION:$(aws sts get-caller-identity --query Account --output text):file-system/$EFS" \
    --ec2-config SubnetArn=arn:aws:ec2:$AWS_REGION:$(aws sts get-caller-identity --query Account --output text):subnet/$SUBNET_ID,SecurityGroupArns=arn:aws:ec2:$AWS_REGION:$(aws sts get-caller-identity --query Account --output text):security-group/$SG \
    --subdirectory "/" \
    --region eu-west-3 \
    --query 'LocationArn' --output text)

echo "S3 Location ARN: $S3_LOCATION_ARN"
echo "EFS Location ARN: $EFS_LOCATION_ARN"

TASK_ARN=$(aws datasync create-task \
    --source-location-arn $S3_LOCATION_ARN \
    --destination-location-arn $EFS_LOCATION_ARN \
    --name "S3-to-EFS-Export-Transfer" \
    --options VerifyMode=POINT_IN_TIME_CONSISTENT,OverwriteMode=ALWAYS,Atime=BEST_EFFORT,Mtime=PRESERVE,Uid=NONE,Gid=NONE,PreserveDeletedFiles=PRESERVE,PreserveDevices=NONE,PosixPermissions=PRESERVE \
    --query 'TaskArn' --output text --region eu-west-3)
    
# Start the DataSync task execution
EXECUTION_ARN=$(aws datasync start-task-execution \
    --task-arn $TASK_ARN \
    --region eu-west-3 \
    --query 'TaskExecutionArn' --output text)

echo "Task Execution ARN: $EXECUTION_ARN"

```

```shell
kind: Secret
apiVersion: v1
metadata:
  generateName: ec2-export-
  name: ec2-export-w8j27
  labels:
    createdForProviderType: ova
    createdForResourceType: providers
data:
  insecureSkipVerify: ZmFsc2U=
  url: ZnMtMGQwMDVkNzliMTBkYWFiZmYuZWZzLmV1LXdlc3QtMy5hbWF6b25hd3MuY29tOi9vdmE=
type: Opaque
---
apiVersion: forklift.konveyor.io/v1beta1
kind: Provider
metadata:
  name: ec2-export
  namespace: openshift-mtv
spec:
  secret:
    name: ec2-export-w8j27
    namespace: openshift-mtv
  type: ova
  url: "$EFS:/ova"
```

https://docs.redhat.com/en/documentation/migration_toolkit_for_virtualization/2.9/html/installing_and_using_the_migration_toolkit_for_virtualization/migrating-virtual-machines-from-the-command-line_mtv
