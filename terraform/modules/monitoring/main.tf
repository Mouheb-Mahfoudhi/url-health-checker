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

# What YACE needs to discover tagged resources and pull CloudWatch metrics,
# and what Grafana needs to query CloudWatch Logs directly.
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

# Lets you reach the box with `aws ssm start-session --target <id>` instead of
# SSH - no key pair, no inbound port open on the security group at all.
resource "aws_iam_role_policy_attachment" "monitoring_ssm" {
  role       = aws_iam_role.monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "monitoring" {
  name = "${var.name_prefix}-monitoring"
  role = aws_iam_role.monitoring.name
}

resource "aws_instance" "monitoring" {
  ami                         = data.aws_ami.al2023.id
  instance_type                = var.instance_type
  subnet_id                    = var.private_subnet_id
  vpc_security_group_ids       = [var.monitoring_sg_id]
  iam_instance_profile         = aws_iam_instance_profile.monitoring.name
  associate_public_ip_address  = false

  user_data = templatefile("${path.module}/templates/user_data.sh.tpl", {
    aws_region          = var.aws_region
    discovery_tag_key   = var.discovery_tag_key
    discovery_tag_value = var.discovery_tag_value
  })

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-monitoring"
  })
}
