terraform {
  required_version = "~> 1.3"
  # cannot use variables in backend block
  # this is to store tfstate in s3
  # backend "s3" {
  #   bucket = local.bucket_name
  #   key = "tf-infra/terraform.tfstate"
  #   region = local.region
  #   dynamodb_table = local.table_name
  #   encrypt = true
  # }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

data "aws_availability_zones" "azs" {
  state = "available"
}


locals {
  tags = {
    Project = var.project
    # CreatedBy = var.createdby
    # CreatedOn = var.createdOn
    # Environment = terraform.workspace
  }
  azs = slice(data.aws_availability_zones.azs.names, 0, var.aws_az_count)
}

output "azs" {
  value = local.azs
}


# Store tf state in bucket
# module "tf-state" {
#     source = "./modules/tf-state"
#     bucket_name = local.bucket_name
#     table_name = local.table_name
# }



# ! EC2 Instance Cluster

// Security Groups
resource "aws_security_group" "ec2-cluster" {
  name   = "${local.tags.Project}-ec2-cluster"
  vpc_id = aws_vpc.main.id

  tags = local.tags

  ingress {
    from_port   = var.app_from_port
    to_port     = var.app_to_port
    protocol    = var.app_protocol
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  // wide open ingress
  # ingress {
  #   from_port        = 0
  #   to_port          = 0
  #   protocol         = "-1"
  #   cidr_blocks      = ["0.0.0.0/0"]
  #   ipv6_cidr_blocks = ["::/0"]
  # }

  // allow all outgoing traffic
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}


resource "aws_security_group" "alb" {
  name   = "${local.tags.Project}-alb"
  vpc_id = aws_vpc.main.id
  tags   = local.tags

  ingress {
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  // https
  # ingress {
  #   from_port        = 443
  #   to_port          = 443
  #   protocol         = var.protocol
  #   cidr_blocks      = ["0.0.0.0/0"]
  #   ipv6_cidr_blocks = ["::/0"]
  # }

  egress {
    from_port = var.app_from_port
    to_port   = var.app_to_port
    protocol  = var.app_protocol
    // this is very important. Otherwise lb will not be able to ping ec2 instances & will treat them as unhealthy
    cidr_blocks = [for s in aws_subnet.public-subnets : s.cidr_block]
  }
}


// Auto Scaling


resource "aws_autoscaling_group" "default" {
  name             = "auth-demo-auto-scaling-group"
  max_size         = 2
  min_size         = 1
  desired_capacity = 1
  # This is for classic load balancers only
  # load_balancers    = [aws_lb.main.id]
  # placement_group     = aws_placement_group.demo-placement-group.id
  vpc_zone_identifier = [for s in aws_subnet.private-subnets : s.id]
  target_group_arns   = [aws_lb_target_group.alb-tg.arn]
  launch_template {
    id      = aws_launch_template.default.id
    version = "$Latest"
  }
}

resource "aws_launch_template" "default" {
  name = "${local.tags.Project}-lt"
  // TODO use data block to get latest ami
  image_id      = "ami-0eb9d67c52f5c80e5"
  instance_type = "t2.micro"
  // previously created ssh key. Used to ssh into ec2 instances
  key_name = "tmx"

  // Give the instance a public IP address
  # network_interfaces {
  #   associate_public_ip_address = true
  #   security_groups             = [aws_security_group.ec2-cluster.id]
  # }

  vpc_security_group_ids = [aws_security_group.ec2-cluster.id]

  user_data = base64encode(file("bootstrap-instance.sh"))
}



// THIS AIMS TO KEEP THE AVERAGE CPU Utilization at target value
resource "aws_autoscaling_policy" "mantain-cpu-utilization" {

  name = "${local.tags.Project}-scale-up"

  policy_type               = "TargetTrackingScaling"
  autoscaling_group_name    = aws_autoscaling_group.default.name
  estimated_instance_warmup = 300

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }

    target_value = 75.0
  }
}

// LB
resource "aws_lb" "main" {
  name               = "${local.tags.Project}-alb"
  internal           = false
  load_balancer_type = "application"

  security_groups = [aws_security_group.alb.id]

  subnets = [for s in aws_subnet.public-subnets : s.id]
}

output "elb_dns_name" {
  value = aws_lb.main.dns_name
}

resource "aws_lb_listener" "main-http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"
  // TODO enable HTTPS here -> https://www.youtube.com/watch?v=81rQ5KgETs0

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb-tg.arn
  }
}

resource "aws_lb_target_group" "alb-tg" {
  name = "${local.tags.Project}-alb-tg"
  port = var.app_to_port
  // TLS termination
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id


  health_check {
    enabled = true
    # path                = "/health"
    path                = var.app_health_check_path
    protocol            = "HTTP"
    port                = var.app_to_port
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}





