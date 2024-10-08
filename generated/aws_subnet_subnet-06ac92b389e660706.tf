resource "aws_subnet" "example" {
  vpc_id            = "subnet-06ac92b389e660706"
  cidr_block        = "172.20.6.0/24"
  availability_zone = "us-east-2c"
}