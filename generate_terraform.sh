#!/bin/bash

# Set variables
REGION="us-east-2"
TAG_KEY="Project"
TAG_VALUE="AnsibleCloudProject"

# Directory for generated terraform files
mkdir -p generated

# Function to generate Terraform files
generate_tf() {
    local resource_type=$1
    local details=$2
    local template_file=$3
    local output_file=$4

    # Debug: Output the template contents before replacement
    echo "Generating $output_file from $template_file with details $details"

    # Replace placeholders in the template with actual values and save to generated files
    sed -e "$details" "$template_file" > "generated/$output_file"
}

# Function to automatically import resource into Terraform
import_resource() {
    local resource_type=$1
    local resource_id=$2
    local resource_name=$3

    # Use terraform import to bring resource into the state
    terraform -chdir=generated import "$resource_type.$resource_name" "$resource_id"
}

# Get the VPC with the specified tag
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:$TAG_KEY,Values=$TAG_VALUE" --query 'Vpcs[0].VpcId' --output text --region $REGION)

if [[ $VPC_ID == "None" ]]; then
    echo "No VPC found with tag $TAG_KEY: $TAG_VALUE"
    exit 1
fi

# Fetch VPC CIDR block
VPC_CIDR=$(aws ec2 describe-vpcs --vpc-ids $VPC_ID --query 'Vpcs[0].CidrBlock' --output text --region $REGION)

# Generate Terraform configuration for VPC
generate_tf "vpc" "s|{{CIDR_BLOCK}}|$VPC_CIDR|g" "templates/vpc_template.tf.j2" "aws_vpc_$VPC_ID.tf"

# Initialize Terraform in the generated directory
terraform -chdir=generated init

# Import the VPC into Terraform
import_resource "aws_vpc" "$VPC_ID" "example"

# Get Subnets in the VPC and generate/import Terraform files for each
SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query 'Subnets[*].[SubnetId,CidrBlock,AvailabilityZone]' --output text --region $REGION)
while read -r SUBNET_ID SUBNET_CIDR AZ; do
    # Use heredoc to handle multi-line AZ (if any) and other variables
    AZ=$(cat <<- EOF
$AZ
EOF
    )
    # Generate Terraform configuration for Subnet
    generate_tf "subnet" "s|{{VPC_ID}}|$VPC_ID|g; s|{{CIDR_BLOCK}}|$SUBNET_CIDR|g; s|{{AVAILABILITY_ZONE}}|$AZ|g" "templates/subnet_template.tf.j2" "aws_subnet_$SUBNET_ID.tf"

    # Import the Subnet into Terraform
    import_resource "aws_subnet" "$SUBNET_ID" "example"
done <<< "$SUBNETS"

# Get Security Groups in the VPC and generate/import Terraform files for each
SGS=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" --query 'SecurityGroups[*].[GroupId,GroupName,Description]' --output text --region $REGION)
while read -r SG_ID SG_NAME SG_DESC; do
    # Use heredoc to handle multi-line Security Group Description
    SG_DESC=$(cat <<- EOF
$SG_DESC
EOF
    )
    # Generate Terraform configuration for Security Group
    generate_tf "security_group" "s|{{RESOURCE_ID}}|$SG_ID|g; s|{{GROUP_NAME}}|$SG_NAME|g; s|{{DESCRIPTION}}|$SG_DESC|g" "templates/security_group_template.tf.j2" "aws_security_group_$SG_ID.tf"

    # Import the Security Group into Terraform
    import_resource "aws_security_group" "$SG_ID" "example"
done <<< "$SGS"

# Get EC2 Instances in the VPC and generate/import Terraform files for each
INSTANCES=$(aws ec2 describe-instances --filters "Name=vpc-id,Values=$VPC_ID" --query 'Reservations[*].Instances[*].[InstanceId,InstanceType,PrivateIpAddress,SubnetId,ImageId]' --output text --region $REGION)
while read -r INSTANCE_ID INSTANCE_TYPE PRIVATE_IP SUBNET_ID AMI_ID; do
    # Generate Terraform configuration for EC2 instance
    echo "AMI ID: $AMI_ID"
    generate_tf "instance" "s|{{AMI_ID}}|$AMI_ID|g; s|{{INSTANCE_TYPE}}|$INSTANCE_TYPE|g; s|{{PRIVATE_IP}}|$PRIVATE_IP|g; s|{{SUBNET_ID}}|$SUBNET_ID|g" "templates/instance_template.tf.j2" "aws_instance_$INSTANCE_ID.tf"

    # Import the EC2 Instance into Terraform
    import_resource "aws_instance" "$INSTANCE_ID" "example"
done <<< "$INSTANCES"

echo "Terraform configuration files generated and resources imported."

# Debug: Check if files are generated
echo "Listing generated files:"
ls -l generated/
