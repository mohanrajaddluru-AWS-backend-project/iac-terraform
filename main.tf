variable "vpc_cidr_block" {
  description = "CIDR block for the VPC"
  default     = "10.10.0.0/16"
}

variable "vpcregion" {
  description = "region of the created VPC"
  default     = "us-east-1"
}

variable "awsAccountprofile" {
  description = "aws profile name for infra to create"
  default     = "mohan-dev-iam"
}

variable "publicRoutecidr" {
  description = "Public IP address to allow all traffic to internet"
  default     = "0.0.0.0/0"
}

variable "dbUser" {
    default = "test"
}

variable "dbName" {
    default = "testing"
}

variable "dbPasswd"{
    default = "password123"
}

variable "port" {
    default = 8080
}




terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }
  required_version = ">= 1.2.0"
}


provider "aws" {
  region  = var.vpcregion
  profile = var.awsAccountprofile
}

resource "aws_vpc" "webappVPC" {
  cidr_block = var.vpc_cidr_block
  tags = {
    Name = "Webapp VPC"
  }
}

data "aws_availability_zones" "availableZones" {
  state = "available"
}

resource "aws_subnet" "privateSubnet" {
  count             = min(3, length(data.aws_availability_zones.availableZones))
  vpc_id            = aws_vpc.webappVPC.id
  cidr_block        = cidrsubnet(var.vpc_cidr_block, 8, count.index + 1)
  availability_zone = data.aws_availability_zones.availableZones.names[count.index]
  tags = {
    Name = "private Subnet - ${data.aws_availability_zones.availableZones.names[count.index]}"
  }
}

resource "aws_subnet" "publicSubnet" {
  count             = min(3, length(data.aws_availability_zones.availableZones))
  vpc_id            = aws_vpc.webappVPC.id
  cidr_block        = cidrsubnet(var.vpc_cidr_block, 8, (count.index + 1 * 10))
  availability_zone = data.aws_availability_zones.availableZones.names[count.index]
  tags = {
    Name = "public Subnet - ${data.aws_availability_zones.availableZones.names[count.index]}"
  }
}

resource "aws_internet_gateway" "internetGateway" {
  vpc_id = aws_vpc.webappVPC.id
  tags = {
    Name = "Internet Gateway"
  }
}


resource "aws_route_table" "privateRouteTable" {
  vpc_id = aws_vpc.webappVPC.id
  tags = {
    Name = "Private Route Table"
  }
}

resource "aws_route_table" "publicRouteTable" {
  vpc_id = aws_vpc.webappVPC.id
  route {
    cidr_block = var.publicRoutecidr
    gateway_id = aws_internet_gateway.internetGateway.id
  }
  tags = {
    Name = "Public Route Table"
  }
}

resource "aws_route_table_association" "publicrouteassociation" {
  count          = min(3, length(aws_route_table.publicRouteTable))
  subnet_id      = aws_subnet.publicSubnet[count.index].id
  route_table_id = aws_route_table.publicRouteTable.id
}

resource "aws_route_table_association" "privaterouteassociation" {
  count          = min(3, length(aws_route_table.privateRouteTable))
  subnet_id      = aws_subnet.privateSubnet[count.index].id
  route_table_id = aws_route_table.privateRouteTable.id
}



resource "aws_security_group" "loadbalancerGroup" {
  name        = "Loadbalancer Security Group"
  description = "Allows HTTP Port and SSL port from internet to load balancer"
  vpc_id      = aws_vpc.webappVPC.id

  ingress {
    description = "Allows SSL Port from Internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.publicRoutecidr]
  }

  ingress {
    description = "App Port 80 from Internet "
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.publicRoutecidr]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.publicRoutecidr]
  }

  tags = {
    Name = "Load balancer Security Group"
  }
}


resource "aws_security_group" "databaseGroup" {
  name        = "Database Security Group"
  description = "Allows 3306 Port from Application Security group to database"
  vpc_id      = aws_vpc.webappVPC.id

  ingress {
    description     = "App Port 3306 from Application Security Group "
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.appSecurityGroup.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.publicRoutecidr]
  }

  tags = {
    Name = "Database Security Group"
  }
}

resource "aws_security_group" "appSecurityGroup" {
  name        = "Application Security Group"
  description = "Allows Ports 22 from Internet and 8080 from Loadbalancer Security Group"
  vpc_id      = aws_vpc.webappVPC.id

  ingress {
    description = "SSH From Internet"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.publicRoutecidr]
  }

  ingress {
    description     = "App Port From Loadbalancer Security Group"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.loadbalancerGroup.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.publicRoutecidr]
  }

  tags = {
    Name = "Application Security Group"
  }
}

resource "aws_db_parameter_group" "rdsparametergroup" {
  name   = "rdsparametergroup"
  family = "mysql8.0"

  parameter {
    name  = "character_set_server"
    value = "utf8"
  }

  parameter {
    name  = "character_set_client"
    value = "utf8"
  }
}

resource "aws_db_subnet_group" "dbSubnetGroup" {
  name       = "dbsubnetgroup"
  subnet_ids = aws_subnet.privateSubnet[*].id
  tags = {
    Name = "RDS subnet group"
  }
}


resource "aws_db_instance" "mysqlwebapprds" {
    identifier = "webapp-mysql-rds"
  allocated_storage    = 10
  db_name              = "mydb"
  engine               = "mysql"
  engine_version       = "8.0.33"
  instance_class       = "db.t2.micro"
  username             = "foo"
  password             = "foobarbaz"
  parameter_group_name = aws_db_parameter_group.rdsparametergroup.name
  skip_final_snapshot  = true
  db_subnet_group_name = aws_db_subnet_group.dbSubnetGroup.id
  multi_az = false
  port = 3306
  vpc_security_group_ids = [aws_security_group.databaseGroup.id]
  publicly_accessible = false
  tags = {
    Name = "mysql rds insance"
  }
}

resource "aws_iam_role" "cloudwatchiamrole" {
  name = "cloudwatchiamrole"
  assume_role_policy = <<EOF
{
    "Version" : "2012-10-17",
    "Statement" : [{
        "Action": "sts:AssumeRole",
        "Effect": "Allow",
        "Principal": {
            "Service": "ec2.amazonaws.com"
            }
        }
    ]
}
EOF
    tags = {
        Name = "cloud watch iam role"
    }
}

resource "aws_iam_instance_profile" "cloudwatchaccessprofile" {
  name = "EC2cloudwatchaccessprofile"
  role = aws_iam_role.cloudwatchiamrole.name
}

resource "aws_iam_role_policy_attachment" "test-attach" {
  role       = aws_iam_role.cloudwatchiamrole.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

locals {
  rds_hostname = split(":", aws_db_instance.mysqlwebapprds.endpoint)[0]
}

# data "template_file" "userdata" {
#     template = <<-EOF
#         #!/bin/bash
#         rm /home/webappuser/webapp/.env
#         echo "DATABASE_HOST: ${local.rds_hostname}" >> /home/webappuser/webapp/.env
#         echo "DATABASE_USER: ${var.dbUser}" >> /home/webappuser/webapp/.env
#         echo "DATABASE_PASSWORD: ${var.dbPasswd}" >> /home/webappuser/webapp/.env
#         echo "DATABASE_NAME: ${var.dbName}" >> /home/webappuser/webapp/.env
#         echo "PORT: ${var.port}" >> /home/webappuser/webapp/.env
#         chown webappuser:webappuser /home/webappuser/webapp/.env
#         sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:/opt/cloudwatch-config.json
#         sudo apt-get install sysstat
#         sudo systemctl restart webapp
#     EOF
# }

resource "aws_launch_template" "webapplaunchtemplate" {
    name = "webapplaunchtemplate"
    image_id = "ami-09f82f08cc8c04e53"
    instance_type = "t2.micro"
    vpc_security_group_ids = [aws_security_group.appSecurityGroup.id]
    key_name = "development"
    user_data = <<-EOF
              #!/bin/bash
              touch /path/to/your/file.txt
              EOF
    iam_instance_profile {
        name = aws_iam_instance_profile.cloudwatchaccessprofile.name
    } 
    tags = {
        Name = "Webapp Launch template"
    }
}

resource "aws_lb_target_group" "webappTargetGroup" {
  name     = "webapp-target-group"
  port     = 8080
  protocol = "HTTP"
  target_type = "instance"
  deregistration_delay = 120
  vpc_id   = aws_vpc.webappVPC.id
  health_check {
    enabled = true
    healthy_threshold = 2
    interval = 30
    matcher = 200
    path = "/healthz/"
    port = 8080
    protocol = "HTTP"
    timeout = 9
    unhealthy_threshold = 5
  }
}

resource "aws_lb" "webappLoadBalancer" {
  name               = "webapploadbalancer"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.loadbalancerGroup.id]
  subnets            = [for subnet in aws_subnet.publicSubnet : subnet.id]
  enable_deletion_protection = false
  tags = {
    Name = "Webapp Load balancer"
  }
}

resource "aws_lb_listener" "webappListener" {
  load_balancer_arn = aws_lb.webappLoadBalancer.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.webappTargetGroup.arn
  }
}

resource "aws_autoscaling_group" "webappAutoScaleGroup" {
  name                      = "webapp-autoscale-group"
  max_size                  = 3
  min_size                  = 1
  health_check_grace_period = 60
  health_check_type         = "ELB"
  desired_capacity          = 1
  
  launch_template {
    id      = aws_launch_template.webapplaunchtemplate.id
    version = aws_launch_template.webapplaunchtemplate.latest_version
  }
  vpc_zone_identifier = [aws_subnet.publicSubnet[0].id]
  target_group_arns = [aws_lb_target_group.webappTargetGroup.arn]
}


output "available_zones" {
  value = data.aws_availability_zones.availableZones.names
}

output "autoscale_ID" {
  value = aws_autoscaling_group.webappAutoScaleGroup.id
}

output "rdsendpoint" {
    value = aws_db_instance.mysqlwebapprds.endpoint
}










