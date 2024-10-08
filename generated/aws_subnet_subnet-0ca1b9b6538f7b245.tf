resource "aws_subnet" "example" {
  vpc_id            = "subnet-0ca1b9b6538f7b245"
  cidr_block        = "172.20.3.0/24"
  availability_zone = "us-east-2c"
}