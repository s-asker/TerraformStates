resource "aws_subnet" "example" {
  vpc_id            = "subnet-0162ea12115007d6b"
  cidr_block        = "172.20.2.0/24"
  availability_zone = "us-east-2b"
}