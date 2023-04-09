# Provider configuration
provider "aws" {
  region = "us-east-2"
}

# 1. Create vpc

resource "aws_vpc" "prod-vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "task"
  }
}

# 2. Create Internet Gateway

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.prod-vpc.id
  
  tags = {
    Name = "task"
  }
}
# 3. Create Custom Route Table

resource "aws_route_table" "prod-route-table" {
  vpc_id = aws_vpc.prod-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "task"
  }
}

# 4. Create a Subnet 

resource "aws_subnet" "subnet-1" {
  vpc_id            = aws_vpc.prod-vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-2a"

  tags = {
    Name = "task"
  }
}

# 5. Associate subnet with Route Table
resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.subnet-1.id
  route_table_id = aws_route_table.prod-route-table.id
}

# 6. Create Security Group to allow port 80
resource "aws_security_group" "allow_web" {
  name        = "allow_web_traffic"
  description = "Allow Web inbound traffic"
  vpc_id      = aws_vpc.prod-vpc.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["91.231.246.50/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_web"
  }
}

# 7. Create a network interface

resource "aws_network_interface" "web-server-nic" {
  subnet_id       = aws_subnet.subnet-1.id
  private_ips     = ["10.0.1.50"]
  security_groups = [aws_security_group.allow_web.id]

}
# 8. Assign an elastic IP to the network interface

resource "aws_eip" "one" {
  vpc                       = true
  network_interface         = aws_network_interface.web-server-nic.id
  associate_with_private_ip = "10.0.1.50"
  depends_on                = [aws_internet_gateway.gw]
}

output "server_public_ip" {
  value = aws_eip.one.public_ip
}

# 9. Create Ec2 server and install apache2

resource "aws_instance" "web-server-instance" {
  ami               = "ami-0533def491c57d991"
  instance_type     = "t2.micro"
  availability_zone = "us-east-2a"
  key_name          = "task-key"

  network_interface {
    device_index         = 0
    network_interface_id = aws_network_interface.web-server-nic.id
  }

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y httpd
              systemctl start httpd
              systemctl enable httpd
              EOF

  tags = {
    Name = "web-server"
  }
}

output "server_id" {
  value = aws_instance.web-server-instance.id
}


# Create a Network Load Balancer
resource "aws_lb" "web-server-lb" {
  name               = "web-server-lb"
  internal           = false
  load_balancer_type = "network"

  subnet_mapping {
    subnet_id = aws_subnet.subnet-1.id
  }

  tags = {
    Name = "web-server-lb"
  }
}

# Create a Target Group
resource "aws_lb_target_group" "web-server-tg" {
  name        = "web-server-tg"
  port               = 80
  protocol           = "TCP"
  vpc_id             = aws_vpc.prod-vpc.id
  target_type        = "instance"

  health_check {
    enabled            = true
    interval           = 30
    path               = "/"
    port               = "traffic-port"
    protocol           = "HTTP"
    timeout            = 10
    unhealthy_threshold = 3
  }

  tags = {
    Name = "web-server-tg"
  }
}

# Register target instances with Target Group
resource "aws_lb_target_group_attachment" "web-server-tg-attachment" {
  target_group_arn = aws_lb_target_group.web-server-tg.arn
  target_id        = aws_instance.web-server-instance.id
  port             = 80
}

# Create a listener to forward traffic to Target Group
resource "aws_lb_listener" "web-server-listener" {
  load_balancer_arn = aws_lb.web-server-lb.arn
  port              = "80"
  protocol          = "TCP"

  default_action {
    target_group_arn = aws_lb_target_group.web-server-tg.arn
    type             = "forward"
  }
}

