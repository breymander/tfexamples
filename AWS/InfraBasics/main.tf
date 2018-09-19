# Create a VPC to launch our instances into
resource "aws_vpc" "default" {
  cidr_block = "10.10.11.0/24"
  tags {
    Name = "TerraForm Testing"
  }
}

# Create a subnet to launch our instances into
resource "aws_subnet" "default" {
  vpc_id                  = "${aws_vpc.default.id}"
  cidr_block              = "10.10.11.0/24"
  map_public_ip_on_launch = true
  tags {
    Name = "TerraForm Testing"
  }
}