#!/bin/bash
REGION="us-east-2"
TAG_KEY="Project"
TAG_VALUE="AnsibleCloudProject"

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

# Fetch the VPC ID based on tags
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:$TAG_KEY,Values=$TAG_VALUE" --query 'Vpcs[0].VpcId' --output text --region $REGION)

# Get Load Balancer details and store each Load Balancer's info in a new line
LBS=$(aws elbv2 describe-load-balancers --query 'LoadBalancers[*].[LoadBalancerArn,LoadBalancerName,Scheme,Type,VpcId]' --output text --region "$REGION")

# Use a while loop to read each line of Load Balancer info
echo "$LBS" | while read -r LB_ARN LB_NAME LB_SCHEME LB_TYPE LB_VPC_ID; do
    # Get subnets separately for this Load Balancer
    SUBNETS=$(aws elbv2 describe-load-balancers --load-balancer-arns "$LB_ARN" --query 'LoadBalancers[0].AvailabilityZones[*].SubnetId' --output text --region "$REGION")
    echo "Here are the subnets: $SUBNETS"  # Added context for clarity
    
    # Convert multi-line SUBNETS into a comma-separated string using paste
    SUBNETS_COMMA_SEPARATED=$(echo "$SUBNETS" | paste -s -d, -)  # Combine into a single line with commas
    echo "Here are the subnets as a comma-separated string: $SUBNETS_COMMA_SEPARATED"
    
    # Print the current Load Balancer information for debugging
    echo "Checking LB_VPC_ID: $LB_VPC_ID against VPC_ID: $VPC_ID"
    
    # If the VPC IDs match, process the Load Balancer
    if [[ "$LB_VPC_ID" == "$VPC_ID" ]]; then
        echo "Match found for LB_NAME: $LB_NAME"
        echo "LB_ARN: $LB_ARN, LB_NAME: $LB_NAME, LB_SCHEME: $LB_SCHEME, LB_TYPE: $LB_TYPE, LB_VPC_ID: $LB_VPC_ID, SUBNETS: $SUBNETS_COMMA_SEPERATED"

        # Determine Load Balancer scheme (internal/external)
        if [[ "$LB_SCHEME" == "internal" ]]; then
            LB_SCHEME=false
        else
            LB_SCHEME=true
        fi

        # Generate Terraform configuration
        if ! generate_tf "load_balancer" "s|{{LB_NAME}}|$LB_NAME|g; s|{{SCHEME}}|$LB_SCHEME|g; s|{{TYPE}}|$LB_TYPE|g; s|{{VPC_ID}}|$LB_VPC_ID|g; s|{{SUBNETS}}|$SUBNETS_COMMA_SEPERATED|g" "templates/load_balancer_template.tf.j2" "aws_lb_${LB_NAME}.tf" "$LB_NAME"; then
            echo "Failed to generate TF for $LB_NAME"
        fi
        
        # Import the Load Balancer into Terraform
        import_resource "aws_lb" "$LB_ARN" "$LB_NAME"
    fi
done <<< "$LBS"
