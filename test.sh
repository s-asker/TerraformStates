#!/bin/bash


REGION="us-east-2"
TAG_KEY="Project"
TAG_VALUE="AnsibleCloudProject"
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:$TAG_KEY,Values=$TAG_VALUE" --query 'Vpcs[0].VpcId' --output text --region $REGION)


# Get NAT Gateways in the VPC and generate/import Terraform files for each
NAT_GWS=$(aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$VPC_ID" --query 'NatGateways[*].[NatGatewayId,SubnetId]' --output text --region $REGION)
while read -r NAT_GW_ID SUBNET_ID; do
    echo "$NAT_GW_ID"
    echo "Hello"
done <<< "$NAT_GWS"

