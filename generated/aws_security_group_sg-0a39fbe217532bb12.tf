resource "aws_security_group" "example" {
  name        = "default"
  description = "default VPC security group"
  vpc_id      = "sg-0a39fbe217532bb12"
}