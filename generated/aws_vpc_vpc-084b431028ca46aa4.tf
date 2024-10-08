resource "aws_vpc" "example" {
  cidr_block = "172.20.0.0/16"
  vpc_id     = "vpc-084b431028ca46aa4"
  tags = {
    Project = "AnsibleCloudProject"
  }
}