resource "aws_instance" "example" {
  ami             = "ami-037774efca2da0726"
  instance_type   = "t2.micro"
  private_ip      = "172.20.1.13"
  subnet_id       = "subnet-0feb3162043f88376"

}