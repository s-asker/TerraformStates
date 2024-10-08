resource "aws_subnet" "example" {
  vpc_id            = "subnet-07cff5786a0025d25"
  cidr_block        = "172.20.5.0/24"
  availability_zone = "us-east-2b"
}