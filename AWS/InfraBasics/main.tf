# Create a VPC to launch our instances into
resource "aws_vpc" "tf_vpc" {
  cidr_block = "10.10.11.0/24"
  tags {
    Name = "TerraForm Testing"
  }
}

# Create a subnet to launch our instances into
resource "aws_subnet" "tf_subnet" {
  vpc_id                  = "${aws_vpc.tf_vpc.id}"
  cidr_block              = "10.10.11.0/24"
  map_public_ip_on_launch = true
  tags {
    Name = "TerraForm Testing"
  }
}

# IG to grant interweb access
resource "aws_internet_gateway" "tf_gateway" {
  vpc_id = "${aws_vpc.tf_vpc.id}"
}

# VPC interweb access
resource "aws_route" "internet_access" {
  route_table_id         = "${aws_vpc.tf_vpc.main_route_table_id}"
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = "${aws_internet_gateway.tf_gateway.id}"
}

# A security group for the ELB so it is accessible via the web
resource "aws_security_group" "tf_sg_elb" {
  name        = "terraform_example_elb"
  description = "Used in the terraform"
  vpc_id      = "${aws_vpc.tf_vpc.id}"

  # HTTP access from anywhere
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "tf_vpc_sg" {
  name        = "terraform_example"
  description = "Used in the terraform"
  vpc_id      = "${aws_vpc.tf_vpc.id}"

  # HTTP access from the VPC
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }
}

resource "aws_elb" "tf_elb_frontend" {
  name = "TFFrontend"

  subnets         = ["${aws_subnet.tf_subnet.id}"]
  security_groups = ["${aws_security_group.tf_sg_elb.id}"]
  instances       = ["${aws_instance.tf_frontend.id}"]

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }
}

resource "aws_instance" "tf_frontend" {
  # The connection block tells our provisioner how to
  # communicate with the resource (instance)
  connection {
    # The default username for our AMI
    user = "ubuntu"

    # The connection will use the local SSH agent for authentication.
  }

  instance_type = "t2.micro"

  # Lookup the correct AMI based on the region
  # we specified
  ami = "${lookup(var.aws_amis, var.aws_region)}"

  # Our Security group to allow HTTP and SSH access
  vpc_security_group_ids = ["${aws_security_group.tf_vpc_sg.id}"]

  # We're going to launch into the same subnet as our ELB. In a production
  # environment it's more common to have a separate private subnet for
  # backend instances.
  subnet_id = "${aws_subnet.tf_subnet.id}"

  # We run a remote provisioner on the instance after creating it.
  # In this case, we just install nginx and start it. By default,
  # this should be on port 80
  provisioner "remote-exec" {
    inline = [
      "sudo apt-get -y update",
      "sudo apt-get -y install nginx",
      "sudo service nginx start",
    ]
  }
}