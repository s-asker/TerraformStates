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
    local unique_id=$5  # Add a new argument for the resource name


    # Debug: Output the template contents before replacement
    echo "Generating $output_file from $template_file with details $details"

    # Replace placeholders in the template with actual values, and replace "example" with unique ID
    sed -e "$details" -e "s/example/$unique_id/g" "$template_file" > "generated/$output_file"
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
generate_tf "vpc" "s|{{CIDR_BLOCK}}|$VPC_CIDR|g" "templates/vpc_template.tf.j2" "aws_vpc_$VPC_ID.tf" "$VPC_ID"

# Initialize Terraform in the generated directory
terraform -chdir=generated init

# Import the VPC into Terraform
import_resource "aws_vpc" "$VPC_ID" "$VPC_ID"

# Get Subnets in the VPC and generate/import Terraform files for each
SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query 'Subnets[*].[SubnetId,CidrBlock,AvailabilityZone]' --output text --region $REGION)
while read -r SUBNET_ID SUBNET_CIDR AZ; do
    # Use heredoc to handle multi-line AZ (if any) and other variables
    AZ=$(cat <<- EOF
$AZ
EOF
    )

    # Generate Terraform configuration for Subnet with a unique name based on Subnet ID
    generate_tf "subnet" "s|{{VPC_ID}}|$VPC_ID|g; s|{{CIDR_BLOCK}}|$SUBNET_CIDR|g; s|{{AVAILABILITY_ZONE}}|$AZ|g" "templates/subnet_template.tf.j2" "aws_subnet_${SUBNET_ID}.tf" "$SUBNET_ID"

    # Import the Subnet into Terraform
    import_resource "aws_subnet" "$SUBNET_ID" "$SUBNET_ID"
done <<< "$SUBNETS"

# Get Security Groups in the VPC and generate/import Terraform files for each
SGS=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" --query 'SecurityGroups[*].[GroupId,GroupName,Description]' --output text --region $REGION)
while read -r SG_ID SG_NAME SG_DESC; do
    # Use heredoc to handle multi-line Security Group Description
    SG_DESC=$(cat <<- EOF
$SG_DESC
EOF
    )

    # Generate Terraform configuration for Security Group with a unique name based on Security Group ID
    generate_tf "security_group" "s|{{RESOURCE_ID}}|$SG_ID|g; s|{{GROUP_NAME}}|$SG_NAME|g; s|{{DESCRIPTION}}|$SG_DESC|g" "templates/security_group_template.tf.j2" "aws_security_group_${SG_ID}.tf" "$SG_ID"

    # Import the Security Group into Terraform
    import_resource "aws_security_group" "$SG_ID" "$SG_ID"
done <<< "$SGS"

# Get EC2 Instances in the VPC and generate/import Terraform files for each
INSTANCES=$(aws ec2 describe-instances --filters "Name=vpc-id,Values=$VPC_ID" --query 'Reservations[*].Instances[*].[InstanceId,InstanceType,PrivateIpAddress,SubnetId,ImageId]' --output text --region $REGION)
while read -r INSTANCE_ID INSTANCE_TYPE PRIVATE_IP SUBNET_ID AMI_ID; do
    # Generate Terraform configuration for EC2 instance with a unique name based on Instance ID
    echo "AMI ID: $AMI_ID"
    AMI_ID=$(cat <<- EOF
$AMI_ID
EOF
    )
    generate_tf "instance" "s|{{AMI_ID}}|$AMI_ID|g; s|{{INSTANCE_TYPE}}|$INSTANCE_TYPE|g; s|{{PRIVATE_IP}}|$PRIVATE_IP|g; s|{{SUBNET_ID}}|$SUBNET_ID|g" "templates/instance_template.tf.j2" "aws_instance_${INSTANCE_ID}.tf" "$INSTANCE_ID"

    # Import the EC2 Instance into Terraform
    import_resource "aws_instance" "$INSTANCE_ID" "$INSTANCE_ID"
done <<< "$INSTANCES"

# Get Internet Gateways in the VPC and generate/import Terraform files for each
IGWS=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC_ID" --query 'InternetGateways[*].InternetGatewayId' --output text --region $REGION)
while read -r IGW_ID; do
    # Generate Terraform configuration for Internet Gateway with a unique name based on IGW ID
    generate_tf "internet_gateway" "s|{{VPC_ID}}|$VPC_ID|g" "templates/internet_gateway_template.tf.j2" "aws_internet_gateway_${IGW_ID}.tf" "$IGW_ID"

    # Import the Internet Gateway into Terraform
    import_resource "aws_internet_gateway" "$IGW_ID" "$IGW_ID"
done <<< "$IGWS"

# Get NAT Gateways in the VPC and generate/import Terraform files for each
#NAT_GWS=$(aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$VPC_ID" --query 'NatGateways[*].[NatGatewayId,SubnetId]' --output text --region $REGION)
#while read -r NAT_GW_ID SUBNET_ID; do
    # Generate Terraform configuration for NAT Gateway with a unique name based on NAT Gateway ID
    #generate_tf "nat_gateway" "s|{{NAT_GW_ID}}|$NAT_GW_ID|g; s|{{SUBNET_ID}}|$SUBNET_ID|g" "templates/nat_gateway_template.tf.j2" "aws_nat_gateway_${NAT_GW_ID}.tf" "$NAT_GW_ID"

    # Import the NAT Gateway into Terraform
    #import_resource "aws_nat_gateway" "$NAT_GW_ID" "$NAT_GW_ID"
#done <<< "$NAT_GWS"

# Get Load Balancers (ALB and NLB) in the VPC and generate/import Terraform files for each
LBS=$(aws elbv2 describe-load-balancers --query 'LoadBalancers[*].[LoadBalancerArn,LoadBalancerName,Scheme,Type,VpcId]' --output text --region "$REGION")

# Use a while loop to read each line of Load Balancer info
echo "$LBS" | while read -r LB_ARN LB_NAME LB_SCHEME LB_TYPE LB_VPC_ID; do
    # Get subnets separately for this Load Balancer
    SUBNETS=$(aws elbv2 describe-load-balancers --load-balancer-arns "$LB_ARN" --query 'LoadBalancers[0].AvailabilityZones[*].SubnetId' --output text --region "$REGION")
    echo "Here are the subnets: $SUBNETS"  # Added context for clarity
    
    # Convert multi-line SUBNETS into a comma-separated string using paste
    SUBNETS_COMMA_SEPERATED=$(echo "$SUBNETS" | paste -s -d, -)  # Combine into a single line with commas
    echo "Here are the subnets as a comma-separated string: $SUBNETS_COMMA_SEPERATED"
    
    # Print the current Load Balancer information for debugging
    echo "Checking LB_VPC_ID: $LB_VPC_ID against VPC_ID: $VPC_ID"
    
    # If the VPC IDs match, process the Load Balancer
    if [[ "$LB_VPC_ID" == "$VPC_ID" ]]; then
        echo "Match found for LB_NAME: $LB_NAME"
        echo "LB_ARN: $LB_ARN, LB_NAME: $LB_NAME, LB_SCHEME: $LB_SCHEME, LB_TYPE: $LB_TYPE, LB_VPC_ID: $LB_VPC_ID, SUBNETS: $SUBNETS_COMMA_SEPARATED"

        # Determine Load Balancer scheme (internal/external)
        if [[ "$LB_SCHEME" == "internal" ]]; then
            LB_SCHEME=false
        else
            LB_SCHEME=true
        fi

        # Generate Terraform configuration
        if ! generate_tf "load_balancer" "s|{{LB_NAME}}|$LB_NAME|g; s|{{SCHEME}}|$LB_SCHEME|g; s|{{TYPE}}|$LB_TYPE|g; s|{{VPC_ID}}|$LB_VPC_ID|g; s|{{SUBNETS}}|$SUBNETS_COMMA_SEPARATED|g" "templates/load_balancer_template.tf.j2" "aws_lb_${LB_NAME}.tf" "$LB_NAME"; then
            echo "Failed to generate TF for $LB_NAME"
        fi
        
        # Import the Load Balancer into Terraform
        import_resource "aws_lb" "$LB_ARN" "$LB_NAME"
    fi
done <<< "$LBS"

# Get Route Tables in the VPC and generate/import Terraform files for each
ROUTE_TABLES=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" --query 'RouteTables[*].[RouteTableId,VpcId]' --output text --region $REGION)
while read -r ROUTE_TABLE_ID VPC_ID; do
    # Generate Terraform configuration for Route Table
    generate_tf "route_table" "s|{{VPC_ID}}|$VPC_ID|g" "templates/route_table_template.tf.j2" "aws_route_table_${ROUTE_TABLE_ID}.tf" "$ROUTE_TABLE_ID"

    # Import the Route Table into Terraform
    import_resource "aws_route_table" "$ROUTE_TABLE_ID" "$ROUTE_TABLE_ID"

    # Get routes in the Route Table and generate/import Terraform files for each route
    ROUTES=$(aws ec2 describe-route-tables --route-table-ids "$ROUTE_TABLE_ID" --query 'RouteTables[0].Routes[*].[DestinationCidrBlock,GatewayId,NatGatewayId,InstanceId,TransitGatewayId]' --output text --region $REGION)
    while read -r DEST_CIDR GW_ID NAT_GW_ID INSTANCE_ID TGW_ID; do
        # Generate Terraform configuration for each route
        generate_tf "route" "s|{{ROUTE_TABLE_ID}}|$ROUTE_TABLE_ID|g; s|{{DESTINATION_CIDR_BLOCK}}|$DEST_CIDR|g; s|{{INTERNET_GATEWAY_ID}}|$GW_ID|g; s|{{NAT_GATEWAY_ID}}|$NAT_GW_ID|g; s|{{INSTANCE_ID}}|$INSTANCE_ID|g; s|{{TRANSIT_GATEWAY_ID}}|$TGW_ID|g" "templates/route_template.tf.j2" "aws_route_${ROUTE_TABLE_ID}_${DEST_CIDR}.tf" "${ROUTE_TABLE_ID}_${DEST_CIDR}"

        # Import each route into Terraform
        import_resource "aws_route" "${ROUTE_TABLE_ID}_${DEST_CIDR}" "${ROUTE_TABLE_ID}_${DEST_CIDR}"
    done <<< "$ROUTES"
done <<< "$ROUTE_TABLES"


# Get Target Groups associated with the VPC and generate/import Terraform files for each
TGS=$(aws elbv2 describe-target-groups --query 'TargetGroups[*].[TargetGroupArn,TargetGroupName,Protocol,Port,VpcId]' --output text --region $REGION)

while read -r TG_ARN TG_NAME TG_PROTOCOL TG_PORT TG_VPC_ID; do
    if [[ "$TG_VPC_ID" == "$VPC_ID" ]]; then
        # Generate Terraform configuration for Target Group with a unique name based on Target Group ARN
        generate_tf "target_group" "s|{{TG_NAME}}|$TG_NAME|g; s|{{PROTOCOL}}|$TG_PROTOCOL|g; s|{{PORT}}|$TG_PORT|g; s|{{VPC_ID}}|$TG_VPC_ID|g" "templates/target_group_template.tf.j2" "aws_lb_target_group_${TG_NAME}.tf" "$TG_NAME"

        # Import the Target Group into Terraform
        import_resource "aws_lb_target_group" "$TG_ARN" "$TG_NAME"
    fi
done <<< "$TGS"



echo "Terraform configuration files generated and resources imported."

# Debug: Check if files are generated
echo "Listing generated files:"
ls -l generated/
