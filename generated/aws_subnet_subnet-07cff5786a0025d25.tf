resource "aws_subnet" "example" {
  vpc_id            = "vpc-084b431028ca46aa4"
  cidr_block        = "172.20.5.0/24"
  availability_zone = "us-east-2b"
}