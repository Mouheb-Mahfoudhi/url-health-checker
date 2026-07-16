data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_iam_role" "monitoring" {
  name = "${var.name_prefix}-monitoring"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "ec2.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "monitoring_observability" {
  name = "${var.name_prefix}-monitoring-observability"
  role = aws_iam_role.monitoring.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "tag:GetResources",
          "cloudwatch:GetMetricData",
          "cloudwatch:ListMetrics",
          "cloudwatch:GetMetricStatistics",
          "logs:DescribeLogGroups",
          "logs:GetLogEvents",
          "logs:FilterLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "monitoring" {
  name = "${var.name_prefix}-monitoring"
  role = aws_iam_role.monitoring.name
}

resource "aws_instance" "monitoring" {
  ami                          = data.aws_ami.al2023.id
  instance_type                = var.instance_type
  subnet_id                    = var.public_subnet_id
  vpc_security_group_ids       = [var.monitoring_sg_id]
  iam_instance_profile         = aws_iam_instance_profile.monitoring.name
  associate_public_ip_address  = true
  key_name                     = var.key_name

  root_block_device {
    volume_size           = 30
    volume_type            = "gp3"
    delete_on_termination  = true
  }

  user_data = templatefile("${path.module}/templates/user_data.sh.tpl", {
    aws_region                 = var.aws_region
    discovery_tag_key          = var.discovery_tag_key
    discovery_tag_value        = var.discovery_tag_value
    alb_dns_name               = var.alb_dns_name
    graylog_root_password_sha2 = var.graylog_root_password_sha2
    graylog_password_secret    = var.graylog_password_secret
  })

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-monitoring"
  })
}

resource "aws_lb_target_group_attachment" "grafana" {
  target_group_arn = var.grafana_target_group_arn
  target_id        = aws_instance.monitoring.id
  port              = 3000
}

resource "aws_lb_target_group_attachment" "prometheus" {
  target_group_arn = var.prometheus_target_group_arn
  target_id        = aws_instance.monitoring.id
  port              = 9090
}

resource "aws_lb_target_group_attachment" "graylog" {
  target_group_arn = var.graylog_target_group_arn
  target_id         = aws_instance.monitoring.id
  port              = 9000
}