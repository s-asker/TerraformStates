#!/bin/bash


REGION="us-east-2"
TAG_KEY="Project"
TAG_VALUE="AnsibleCloudProject"
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:$TAG_KEY,Values=$TAG_VALUE" --query 'Vpcs[0].VpcId' --output text --region $REGION)


LBS=$(aws elbv2 describe-load-balancers --query 'LoadBalancers[*].[LoadBalancerArn,LoadBalancerName,Scheme,Type,VpcId]' --output text --region "$REGION")

# Use a while loop to read each line of Load Balancer info
echo "$LBS" | while read -r LB_ARN LB_NAME LB_SCHEME LB_TYPE LB_VPC_ID; do  
    # Get subnets for the load balancer
    SUBNETS=$(aws elbv2 describe-load-balancers --load-balancer-arns "$LB_ARN" \
        --query 'LoadBalancers[0].AvailabilityZones[*].SubnetId' --output text --region "$REGION")

    echo "Here are the subnets: $SUBNETS"  # Debugging output

    # Clean and convert to comma-separated string by removing extra spaces/tabs
    SUBNETS_COMMA_SEPARATED=$(echo "$SUBNETS" | tr -s '[:space:]' ',' | sed 's/,$//')
    SUBNETS_TF_STRING=$(echo "\"$(echo $SUBNETS_COMMA_SEPARATED | sed 's/,/","/g')\"")

    echo "Here are the subnets as a comma-separated string: $SUBNETS_TF_STRING"
done

