# Configure the AWS Provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"  # Replace with your desired region
}

# Create a VPC
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "two-tier-alb-vpc"
  }
}

# Create an Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "two-tier-alb-igw"
  }
}

# Create Public Subnets
resource "aws_subnet" "public_subnet1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "two-tier-alb-public-subnet1"
  }
}

resource "aws_subnet" "public_subnet2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true

  tags = {
    Name = "two-tier-alb-public-subnet2"
  }
}

# Create Private Subnets
resource "aws_subnet" "private_subnet1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.10.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = false

  tags = {
    Name = "two-tier-alb-private-subnet1"
  }
}

resource "aws_subnet" "private_subnet2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.20.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = false

  tags = {
    Name = "two-tier-alb-private-subnet2"
  }
}

# Create a Public Route Table
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "two-tier-alb-public-rt"
  }
}

# Associate Public Subnets with Public Route Table
resource "aws_route_table_association" "public_subnet1_assoc" {
  subnet_id      = aws_subnet.public_subnet1.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public_subnet2_assoc" {
  subnet_id      = aws_subnet.public_subnet2.id
  route_table_id = aws_route_table.public_rt.id
}

# Create a Security Group for Web Servers
resource "aws_security_group" "web_sg" {
  name = "two-tier-alb-web-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Allow SSH from anywhere (for now)
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "two-tier-alb-web-sg"
  }
}

# Create a Security Group for Application Load Balancer
resource "aws_security_group" "alb_sg" {
  name = "two-tier-alb-sg"
  vpc_id = aws_vpc.main.id

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

  tags = {
    Name = "two-tier-alb-sg"
  }
}

# Create a Security Group for Database Servers
resource "aws_security_group" "db_sg" {
  name = "two-tier-alb-db-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 3306 # Replace with your database port
    to_port     = 3306
    protocol    = "tcp"
    security_groups = [aws_security_group.web_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "two-tier-alb-db-sg"
  }
}

# Launch EC2 Instances for Web Tier
resource "aws_instance" "web_server1" {
  ami                    = "ami-0c94855ba95c574c8"  # Replace with your desired AMI
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.public_subnet1.id
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  key_name               = "your_key_pair" # Replace with your key pair name
  user_data              = <<-EOF
#!/bin/bash
echo "Hello from web server 1" > /var/www/html/index.html
  EOF

  tags = {
    Name = "two-tier-alb-web-server1"
  }
}

resource "aws_instance" "web_server2" {
  ami                    = "ami-0c94855ba95c574c8"  # Replace with your desired AMI
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.public_subnet2.id
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  key_name               = "your_key_pair" # Replace with your key pair name
  user_data              = <<-EOF
#!/bin/bash
echo "Hello from web server 2" > /var/www/html/index.html
  EOF

  tags = {
    Name = "two-tier-alb-web-server2"
  }
}

# Launch EC2 Instance for Database Tier
resource "aws_instance" "db_server" {
  ami                    = "ami-0c94855ba95c574c8"  # Replace with your desired AMI
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.private_subnet1.id
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  key_name               = "your_key_pair" # Replace with your key pair name

  tags = {
    Name = "two-tier-alb-db-server"
  }
}

# Create Application Load Balancer
resource "aws_lb" "alb" {
  name               = "two-tier-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.public_subnet1.id, aws_subnet.public_subnet2.id]

  tags = {
    Name = "two-tier-alb"
  }
}

# Create Target Group
resource "aws_lb_target_group" "tg" {
  name     = "two-tier-alb-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path = "/"
  }
}

# Register Targets with Target Group
resource "aws_lb_target_group_attachment" "web_server1_attachment" {
  target_group_arn = aws_lb_target_group.tg.arn
  target_id        = aws_instance.web_server1.id
  port             = 80
}

resource "aws_lb_target_group_attachment" "web_server2_attachment" {
  target_group_arn = aws_lb_target_group.tg.arn
  target_id        = aws_instance.web_server2.id
  port             = 80
}

# Create Listener
resource "aws_lb_listener" "listener" {
  load_balancer_arn = aws_lb.alb.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}