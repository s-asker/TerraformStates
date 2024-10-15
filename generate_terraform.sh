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
SGS=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" --query 'SecurityGroups[*].[GroupId,GroupName,VpcId,Description]' --output text --region $REGION)
while read -r SG_ID SG_NAME SG_VPC_ID SG_DESC; do
    # Use heredoc to handle multi-line Security Group Description
    SG_DESC=$(cat <<- EOF
$SG_DESC
EOF
    )
    SG_VPC_ID=$(cat <<- EOF
$SG_VPC_ID
EOF
    )

    # Generate Terraform configuration for Security Group with a unique name based on Security Group ID
    generate_tf "security_group" "s|{{RESOURCE_ID}}|$SG_VPC_ID|g; s|{{GROUP_NAME}}|$SG_NAME|g; s|{{DESCRIPTION}}|$SG_DESC|g" "templates/security_group_template.tf.j2" "aws_security_group_${SG_ID}.tf" "$SG_ID"

    # Import the Security Group into Terraform
    import_resource "aws_security_group" "$SG_ID" "$SG_ID"
done <<< "$SGS"

# # Get EC2 Instances in the VPC and generate/import Terraform files for each
# INSTANCES=$(aws ec2 describe-instances --filters "Name=vpc-id,Values=$VPC_ID" --query 'Reservations[*].Instances[*].[InstanceId,InstanceType,PrivateIpAddress,SubnetId,ImageId]' --output text --region $REGION)
# while read -r INSTANCE_ID INSTANCE_TYPE PRIVATE_IP SUBNET_ID AMI_ID; do
#     # Generate Terraform configuration for EC2 instance with a unique name based on Instance ID
#     echo "AMI ID: $AMI_ID"
#     AMI_ID=$(cat <<- EOF
# $AMI_ID
# EOF
#     )
#     generate_tf "instance" "s|{{AMI_ID}}|$AMI_ID|g; s|{{INSTANCE_TYPE}}|$INSTANCE_TYPE|g; s|{{PRIVATE_IP}}|$PRIVATE_IP|g; s|{{SUBNET_ID}}|$SUBNET_ID|g" "templates/instance_template.tf.j2" "aws_instance_${INSTANCE_ID}.tf" "$INSTANCE_ID"

#     # Import the EC2 Instance into Terraform
#     import_resource "aws_instance" "$INSTANCE_ID" "$INSTANCE_ID"
# done <<< "$INSTANCES"

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

# Get Target Groups associated with the VPC and generate/import Terraform files for each
TGS=$(aws elbv2 describe-target-groups --query 'TargetGroups[*].[TargetGroupArn,TargetGroupName,Protocol,Port,VpcId]' --output text --region "$REGION")

while read -r TG_ARN TG_NAME TG_PROTOCOL TG_PORT TG_VPC_ID; do
    if [[ "$TG_VPC_ID" == "$VPC_ID" ]]; then
        echo "Processing Target Group: $TG_NAME with ARN: $TG_ARN"

        # Generate Terraform configuration for Target Group
        generate_tf "target_group" "s|{{TG_NAME}}|$TG_NAME|g; s|{{PROTOCOL}}|$TG_PROTOCOL|g; s|{{PORT}}|$TG_PORT|g; s|{{VPC_ID}}|$TG_VPC_ID|g" "templates/target_group_template.tf.j2" "aws_lb_target_group_${TG_NAME}.tf" "$TG_NAME"

        # Import the Target Group into Terraform
        import_resource "aws_lb_target_group" "$TG_ARN" "$TG_NAME"

        # Now, find ASGs associated with this Target Group
        ASGS=$(aws autoscaling describe-auto-scaling-groups --query "AutoScalingGroups[?contains(TargetGroupARNs, '$TG_ARN')].[AutoScalingGroupName,DesiredCapacity,MaxSize,MinSize,LaunchTemplate.LaunchTemplateId,LaunchTemplate.Version]" --output text --region "$REGION")

        while read -r ASG_NAME DESIRED_CAPACITY MAX_SIZE MIN_SIZE LT_ID LT_VERSION; do
            if [[ -n "$LT_ID" && -n "$LT_VERSION" ]]; then
                echo "Processing Auto Scaling Group: $ASG_NAME with Launch Template ID: $LT_ID and Version: $LT_VERSION"
                
                # Generate Terraform configuration for ASG
                generate_tf "autoscaling_group" \
                    "s|{{DESIRED}}|$DESIRED_CAPACITY|g; s|{{MAX}}|$MAX_SIZE|g; s|{{MIN}}|$MIN_SIZE|g; s|{{LT_ID}}|$LT_ID|g; s|{{LATEST}}|$LT_VERSION|g" \
                    "templates/asg_template.tf.j2" \
                    "aws_autoscaling_group_${ASG_NAME}.tf" "$ASG_NAME"

                # Import the Auto Scaling Group into Terraform
                import_resource "aws_autoscaling_group" "$ASG_NAME" "$ASG_NAME"
            else
                echo "Skipping Auto Scaling Group: $ASG_NAME (missing Launch Template information)"
            fi
        done <<< "$ASGS"
    fi
done <<< "$TGS"




# Get Load Balancers (ALB and NLB) in the VPC and generate/import Terraform files for each
LBS=$(aws elbv2 describe-load-balancers --query 'LoadBalancers[*].[LoadBalancerArn,LoadBalancerName,Scheme,Type,VpcId]' --output text --region "$REGION")

# Use a while loop to read each line of Load Balancer info
echo "$LBS" | while read -r LB_ARN LB_NAME LB_SCHEME LB_TYPE LB_VPC_ID; do  
    # Get subnets for the load balancer
    SUBNETS=$(aws elbv2 describe-load-balancers --load-balancer-arns "$LB_ARN" \
        --query 'LoadBalancers[0].AvailabilityZones[*].SubnetId' --output text --region "$REGION")

    echo "Here are the subnets: $SUBNETS"  # Debugging output

    # Clean and convert to comma-separated string by removing extra spaces/tabs
    SUBNETS_COMMA_SEPERATED=$(echo "$SUBNETS" | tr -s '[:space:]' ',' | sed 's/,$//')

    echo "Here are the subnets as a comma-separated string: $SUBNETS_COMMA_SEPERATED"

    # If the VPC IDs match, process the Load Balancer
    if [[ "$LB_VPC_ID" == "$VPC_ID" ]]; then
        echo "Match found for LB_NAME: $LB_NAME"
        echo "LB_ARN: $LB_ARN, LB_NAME: $LB_NAME, LB_SCHEME: $LB_SCHEME, LB_TYPE: $LB_TYPE, LB_VPC_ID: $LB_VPC_ID"

        # Determine Load Balancer scheme (internal/external)
        if [[ "$LB_SCHEME" == "internal" ]]; then
            LB_SCHEME=true
        else
            LB_SCHEME=false
        fi

        # Generate Terraform configuration
        if ! generate_tf "load_balancer" "s|{{LB_NAME}}|$LB_NAME|g; s|{{SCHEME}}|$LB_SCHEME|g; s|{{TYPE}}|$LB_TYPE|g; s|{{VPC_ID}}|$LB_VPC_ID|g; s|{{SUBNETS}}|$SUBNETS_COMMA_SEPERATED|g" "templates/load_balancer_template.tf.j2" "aws_lb_${LB_NAME}.tf" "$LB_NAME"; then
            echo "Failed to generate TF for $LB_NAME"
        fi
        
        # Import the Load Balancer into Terraform
        import_resource "aws_lb" "$LB_ARN" "$LB_NAME"
    fi
done <<< "$LBS"

# Get VPC Peering Connections filtered by VPC ID
VPC_PEERINGS=$(aws ec2 describe-vpc-peering-connections \
    --query "VpcPeeringConnections[?RequesterVpcInfo.VpcId=='$VPC_ID' || AccepterVpcInfo.VpcId=='$VPC_ID'].[VpcPeeringConnectionId,RequesterVpcInfo.VpcId,RequesterVpcInfo.OwnerId,AccepterVpcInfo.VpcId]" \
    --output text --region "$REGION")

while read -r PEERING_ID REQUESTER_VPC_ID OWNER_ID PEER_VPC_ID; do
    if [[ -n "$REQUESTER_VPC_ID" && -n "$OWNER_ID" && -n "$PEER_VPC_ID" ]]; then
        echo "Processing VPC Peering Connection: $PEERING_ID"
        generate_tf "vpc_peering_connection" \
            "s|{{OWNER}}|$OWNER_ID|g; s|{{PEER}}|$PEER_VPC_ID|g; s|{{VPC_ID}}|$REQUESTER_VPC_ID|g" \
            "templates/vpc_peering_template.tf.j2" \
            "aws_vpc_peering_connection_${PEERING_ID}.tf" "$PEERING_ID"
        import_resource "aws_vpc_peering_connection" "$PEERING_ID" "$PEERING_ID"
    else
        echo "Skipping VPC Peering Connection: $PEERING_ID (missing details)"
    fi
done <<< "$VPC_PEERINGS"






echo "Terraform configuration files generated and resources imported."

# Debug: Check if files are generated
echo "Listing generated files:"
ls -l generated/
