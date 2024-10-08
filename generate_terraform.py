import boto3
from jinja2 import Environment, FileSystemLoader
import os

# Initialize AWS SDK
ec2_client = boto3.client('ec2', region_name='us-east-1')  # Adjust region if necessary

# Fetch the VPC ID for the specified tag
vpcs = ec2_client.describe_vpcs(
    Filters=[
        {
            'Name': 'tag:AnsibleCloudProject',
            'Values': ['*']  # Use '*' to get all VPCs with the specified tag
        }
    ]
)

# Get the VPC ID if available
vpc_id = vpcs['Vpcs'][0]['VpcId'] if vpcs['Vpcs'] else None

if not vpc_id:
    print("No VPC found with the tag 'AnsibleCloudProject'.")
    exit(1)

# Jinja2 environment setup
env = Environment(loader=FileSystemLoader('templates'))


def get_instances(vpc_id):
    response = ec2_client.describe_instances(
        Filters=[
            {
                'Name': 'vpc-id',
                'Values': [vpc_id]
            }
        ]
    )

    instances = []
    for reservation in response['Reservations']:
        for instance in reservation['Instances']:
            instances.append({
                'resource_name': instance['InstanceId'],
                'ami': instance['ImageId'],
                'instance_type': instance['InstanceType'],
                'subnet_id': instance['SubnetId'],
                'security_group_ids': [sg['GroupId'] for sg in instance['SecurityGroups']],
                'name': next((tag['Value'] for tag in instance.get('Tags', []) if tag['Key'] == 'Name'), 'Unnamed')
            })
    return instances

def get_security_groups(vpc_id):
    response = ec2_client.describe_security_groups(
        Filters=[
            {
                'Name': 'vpc-id',
                'Values': [vpc_id]
            }
        ]
    )
    security_groups = []
    for sg in response['SecurityGroups']:
        ingress_rules = []
        egress_rules = []

        # Collect Ingress Rules
        for ip_permission in sg.get('IpPermissions', []):
            for ip_range in ip_permission.get('IpRanges', []):
                ingress_rules.append({
                    'from_port': ip_permission['FromPort'],
                    'to_port': ip_permission['ToPort'],
                    'protocol': ip_permission['IpProtocol'],
                    'cidr_block': ip_range['CidrIp']
                })

        # Collect Egress Rules
        for ip_permission in sg.get('IpPermissionsEgress', []):
            for ip_range in ip_permission.get('IpRanges', []):
                egress_rules.append({
                    'from_port': ip_permission['FromPort'],
                    'to_port': ip_permission['ToPort'],
                    'protocol': ip_permission['IpProtocol'],
                    'cidr_block': ip_range['CidrIp']
                })

        security_groups.append({
            'resource_name': sg['GroupId'],
            'vpc_id': sg['VpcId'],
            'name': next((tag['Value'] for tag in sg.get('Tags', []) if tag['Key'] == 'Name'), 'Unnamed'),
            'ingress_rules': ingress_rules,
            'egress_rules': egress_rules
        })
    return security_groups


def get_subnets(vpc_id):
    response = ec2_client.describe_subnets(
        Filters=[
            {
                'Name': 'vpc-id',
                'Values': [vpc_id]
            }
        ]
    )

    subnets = []
    for subnet in response['Subnets']:
        subnets.append({
            'resource_name': subnet['SubnetId'],
            'vpc_id': subnet['VpcId'],
            'cidr_block': subnet['CidrBlock'],
            'availability_zone': subnet['AvailabilityZone'],
            'name': next((tag['Value'] for tag in subnet.get('Tags', []) if tag['Key'] == 'Name'), 'Unnamed')
        })
    return subnets