resource "aws_subnet" "example" {
  vpc_id            = "subnet-00554da62a81109f6"
  cidr_block        = "172.20.4.0/24"
  availability_zone = "us-east-2a"
}