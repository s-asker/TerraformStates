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

    # Replace placeholders in the template with actual values and save to generated files
    sed "$details" "$template_file" > "generated/$output_file"
}

# Function to automatically import resource into Terraform
import_resource() {
    local resource_type=$1
    local resource_id=$2

    # Use terraform import to bring resource into the state
    terraform import "$resource_type" "$resource_id"
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
generate_tf "vpc" "s/{{RESOURCE_ID}}/$VPC_ID/g; s/{{CIDR_BLOCK}}/$VPC_CIDR/g" "templates/vpc_template.tf.j2" "aws_vpc_$VPC_ID.tf"

# Import the VPC into Terraform
import_resource "aws_vpc.example" "$VPC_ID"

# Get Subnets in the VPC and generate/import Terraform files for each
SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query 'Subnets[*].[SubnetId,CidrBlock,AvailabilityZone]' --output text --region $REGION)
while read -r SUBNET_ID SUBNET_CIDR AZ; do
    generate_tf "subnet" "s/{{RESOURCE_ID}}/$SUBNET_ID/g; s/{{CIDR_BLOCK}}/$SUBNET_CIDR/g; s/{{AVAILABILITY_ZONE}}/$AZ/g" "templates/subnet_template.tf.j2" "aws_subnet_$SUBNET_ID.tf"
    import_resource "aws_subnet.example" "$SUBNET_ID"
done <<< "$SUBNETS"

# Get Security Groups in the VPC and generate/import Terraform files for each
SGS=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" --query 'SecurityGroups[*].[GroupId,GroupName,Description]' --output text --region $REGION)
while read -r SG_ID SG_NAME SG_DESC; do
    generate_tf "security_group" "s/{{RESOURCE_ID}}/$SG_ID/g; s/{{GROUP_NAME}}/$SG_NAME/g; s/{{DESCRIPTION}}/$SG_DESC/g" "templates/security_group_template.tf.j2" "aws_security_group_$SG_ID.tf"
    import_resource "aws_security_group.example" "$SG_ID"
done <<< "$SGS"

# Get EC2 Instances in the VPC and generate/import Terraform files for each
INSTANCES=$(aws ec2 describe-instances --filters "Name=vpc-id,Values=$VPC_ID" --query 'Reservations[*].Instances[*].[InstanceId,InstanceType,PrivateIpAddress]' --output text --region $REGION)
while read -r INSTANCE_ID INSTANCE_TYPE PRIVATE_IP; do
    generate_tf "instance" "s/{{RESOURCE_ID}}/$INSTANCE_ID/g; s/{{INSTANCE_TYPE}}/$INSTANCE_TYPE/g; s/{{PRIVATE_IP}}/$PRIVATE_IP/g" "templates/instance_template.tf.j2" "aws_instance_$INSTANCE_ID.tf"
    import_resource "aws_instance.example" "$INSTANCE_ID"
done <<< "$INSTANCES"

echo "Terraform configuration files generated and resources imported."
