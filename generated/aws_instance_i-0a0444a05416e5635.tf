resource "aws_instance" "example" {
  instance_id   = "i-0a0444a05416e5635"
  instance_type = "t2.micro"
  private_ip    = "172.20.1.13"
}