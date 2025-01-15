resource "aws_vpc" "myvpc" {
  cidr_block = var.cidr
}

#Public subnet
resource "aws_subnet" "sub1" {
  vpc_id                  = aws_vpc.myvpc.id
  cidr_block              = "10.0.0.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
  tags = {
    Name = "sub-1"
  }
}

resource "aws_subnet" "sub2" {
  vpc_id                  = aws_vpc.myvpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true
  tags = {
    Name = "sub-2"
  }
}

# Private Subnets TEST
resource "aws_subnet" "two-tier-pvt-sub-1" {
  vpc_id                  = aws_vpc.myvpc.id
  cidr_block              = "10.0.128.0/18"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = false
  tags = {
    Name = "two-tier-pvt-sub-1"
  }
}
resource "aws_subnet" "two-tier-pvt-sub-2" {
  vpc_id                  = aws_vpc.myvpc.id
  cidr_block              = "10.0.192.0/18"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = false
  tags = {
    Name = "two-tier-pvt-sub-2"
  }
}

# Subnet group database TEST
resource "aws_db_subnet_group" "two-tier-db-sub" {
  name       = "two-tier-db-sub"
  subnet_ids = [aws_subnet.two-tier-pvt-sub-1.id, aws_subnet.two-tier-pvt-sub-2.id]
  tags = {
    Name = "two-tier-db-sub"
  }
}

# # Internet Gateway
# resource "aws_internet_gateway" "two-tier-igw" {
#   tags = {
#     Name = "two-tier-igw"
#   }
#   vpc_id = aws_vpc.two-tier-vpc.id
# }

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.myvpc.id
}

resource "aws_route_table" "RT" {
  vpc_id = aws_vpc.myvpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "rta1" {
  subnet_id      = aws_subnet.sub1.id
  route_table_id = aws_route_table.RT.id
}

resource "aws_route_table_association" "rta2" {
  subnet_id      = aws_subnet.sub2.id
  route_table_id = aws_route_table.RT.id
}

resource "aws_security_group" "webSg" {
  name   = "web"
  vpc_id = aws_vpc.myvpc.id

  ingress {
    description = "HTTP from VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "SSH"
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

  tags = {
    Name = "Web-sg"
  }
}

# Database tier Security gruop TEST
resource "aws_security_group" "two-tier-db-sg" {
  name        = "two-tier-db-sg"
  description = "allow traffic from internet"
  vpc_id      = aws_vpc.myvpc.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    #security_groups = [aws_security_group.two-tier-ec2-sg.id]
    cidr_blocks     = ["0.0.0.0/0"]
  }

  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    #security_groups = [aws_security_group.two-tier-ec2-sg.id]
    cidr_blocks     = ["10.0.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_s3_bucket" "example" {
  bucket = "vishnuterraformprojectforrei"
}


resource "aws_instance" "webserver1" {
  ami                    = "ami-0261755bbcb8c4a84"
  instance_type          = "t2.micro"
  vpc_security_group_ids = [aws_security_group.webSg.id]
  subnet_id              = aws_subnet.sub1.id
  user_data              = base64encode(file("userdata.sh"))
}

resource "aws_instance" "webserver2" {
  ami                    = "ami-0261755bbcb8c4a84"
  instance_type          = "t2.micro"
  vpc_security_group_ids = [aws_security_group.webSg.id]
  subnet_id              = aws_subnet.sub2.id
  user_data              = base64encode(file("userdata1.sh"))
}

#create alb
resource "aws_lb" "myalb" {
  name               = "myalb"
  internal           = false
  load_balancer_type = "application"

  security_groups = [aws_security_group.webSg.id]
  subnets         = [aws_subnet.sub1.id, aws_subnet.sub2.id]

  tags = {
    Name = "web"
  }
}

resource "aws_lb_target_group" "tg" {
  name     = "myTG"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.myvpc.id

  health_check {
    path = "/"
    port = "traffic-port"
  }
}

resource "aws_lb_target_group_attachment" "attach1" {
  target_group_arn = aws_lb_target_group.tg.arn
  target_id        = aws_instance.webserver1.id
  port             = 80
}

resource "aws_lb_target_group_attachment" "attach2" {
  target_group_arn = aws_lb_target_group.tg.arn
  target_id        = aws_instance.webserver2.id
  port             = 80
}

resource "aws_lb_listener" "listener" {
  load_balancer_arn = aws_lb.myalb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    target_group_arn = aws_lb_target_group.tg.arn
    type             = "forward"
  }
}

output "loadbalancerdns" {
  value = aws_lb.myalb.dns_name
}

# RDS MYSQL database TEST
resource "aws_db_instance" "two-tier-db-1" {
  allocated_storage           = 5
  #storage_type                = "gp2"
  engine                      = "mysql"
  engine_version              = "8.0"
  instance_class              = "db.t3.micro"
  db_subnet_group_name        = "two-tier-db-sub"
  vpc_security_group_ids      = [aws_security_group.two-tier-db-sg.id]
  parameter_group_name        = "default.mysql8.0"
  db_name                     = "two_tier_db1"
  username                    = "admin"
  password                    = "password"
  allow_major_version_upgrade = true
  auto_minor_version_upgrade  = true
  backup_retention_period     = 35
  backup_window               = "22:00-23:00"
  maintenance_window          = "Sat:00:00-Sat:03:00"
  multi_az                    = false
  skip_final_snapshot         = true
}
