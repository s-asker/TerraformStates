resource "aws_security_group" "example" {
  name        = "bastion-sg"
  description = "Security Group of Bastion Host"
  vpc_id      = "sg-0f359b6f7c37a85a6"
}