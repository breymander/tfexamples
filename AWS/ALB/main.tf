# Create a VPC to launch our instances into
resource "aws_vpc" "tf_vpc" {
  cidr_block = "10.10.0.0/16"
  tags {
    Name = "TerraForm ALB Testing"
  }
}

# Pull back the available AZs 
data "aws_availability_zones" "available" {}

# Create a subnet to launch our instances into.
resource "aws_subnet" "tf_subnet" {
  vpc_id                  = "${aws_vpc.tf_vpc.id}"
  cidr_block              = "10.10.11.0/24"
  availability_zone       = "${data.aws_availability_zones.available.names[0]}"
  map_public_ip_on_launch = true
  tags {
    Name = "TerraForm ALB Testing"
  }
}

# ALBs require multiple subnets.  We need to specify a different AZ for this subnet.
resource "aws_subnet" "tf_subnet2" {
  vpc_id                  = "${aws_vpc.tf_vpc.id}"
  cidr_block              = "10.10.12.0/24"
  availability_zone       = "${data.aws_availability_zones.available.names[1]}"
  map_public_ip_on_launch = true
  tags {
    Name = "TerraForm ALB Testing"
  }
}

# IG to grant interweb access
resource "aws_internet_gateway" "tf_gateway" {
  vpc_id = "${aws_vpc.tf_vpc.id}"
}

# VPC interweb access
resource "aws_route" "tf_internet_access" {
  route_table_id         = "${aws_vpc.tf_vpc.main_route_table_id}"
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = "${aws_internet_gateway.tf_gateway.id}"
}

# A security group for the ELB so it is accessible via the web
resource "aws_security_group" "tf_sg_alb" {
  name        = "terraform_example_alb"
  description = "Used in the terraform"
  vpc_id      = "${aws_vpc.tf_vpc.id}"

  # HTTP access from anywhere
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
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
    cidr_blocks = ["10.10.0.0/16"]
  }

  # SSH access from anywhere
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_key_pair" "tf_auth" {
  key_name   = "${var.key_name}"
  public_key = "${file(var.public_key_path)}"
}

# Create our ALB object.
resource "aws_lb" "tf_alb" {
  name               = "test-lb-tf"
  internal           = false
  load_balancer_type = "application"
  security_groups    = ["${aws_security_group.tf_sg_alb.id}"]
  subnets            = ["${aws_subnet.tf_subnet.id}", "${aws_subnet.tf_subnet2.id}"]

  tags {
    Environment = "TerraForm ALB Testing"
  }
}

# Create the target group.
resource "aws_lb_target_group" "tf_alb_tg" {
  name     = "tf-alb-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = "${aws_vpc.tf_vpc.id}"
}

# Here we need to attach our EC2 instance to the ALB.
resource "aws_lb_target_group_attachment" "tf_alb_tga" {
  target_group_arn = "${aws_lb_target_group.tf_alb_tg.arn}"
  target_id = "${aws_instance.tf_frontend.id}"
}

# Confgiure the ALB to listen on a specific port and specify the protocol
# It is usually helpful to configure a default action.
resource "aws_lb_listener" "tf_alb_listener" {
  load_balancer_arn = "${aws_lb.tf_alb.arn}"
  port              = "80"
  protocol          = "HTTP"

  default_action {
    target_group_arn = "${aws_lb_target_group.tf_alb_tg.arn}"
    type             = "forward"
  }
}

# Here we need to specify rules to route our traffic.  
# In this example, we're only sending requests to /, so 
# it is pretty basic.  This is actually redundant in
# this configuration due to the default_action on the 
# aws_lb_listener.
resource "aws_alb_listener_rule" "tf_alb_listener_rule" {
  depends_on  = ["aws_lb_target_group.tf_alb_tg"]
  listener_arn = "${aws_lb_listener.tf_alb_listener.arn}"
  action {
    type  = "forward"
    target_group_arn = "${aws_lb_target_group.tf_alb_tg.arn}"
  }

  condition {
    field = "path-pattern"
    values = ["/"]
  }
}


resource "aws_instance" "tf_frontend" {
  # The connection block tells our provisioner how to
  # communicate with the resource (instance)
  connection {
    # The default username for our AMI
    user = "ubuntu"
    agent = true
  }

  instance_type = "t2.micro"

  # Lookup the correct AMI based on the region
  # we specified
  ami = "${lookup(var.aws_amis, var.aws_region)}"

  # The name of our SSH keypair we created above.
  key_name = "${aws_key_pair.tf_auth.id}"

  # Our Security group to allow HTTP and SSH access
  vpc_security_group_ids = ["${aws_security_group.tf_vpc_sg.id}"]

  # We're going to launch into the same subnet as our ELB. In a production
  # environment it's more common to have a separate private subnet for
  # backend instances.
  subnet_id = "${aws_subnet.tf_subnet2.id}"

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

  tags {
    Name = "TF Frontend"
  }
}