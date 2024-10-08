resource "aws_vpc" "example" {
  cidr_block = "172.20.0.0/16"
  tags = {
    Project = "AnsibleCloudProject"
  }
}