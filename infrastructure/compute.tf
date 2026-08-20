data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

resource "aws_security_group" "app_instance" {
  name        = "wynnmarket-app-instance"
  description = "Outbound-only security group for the WynnMarket container host."
  vpc_id      = aws_vpc.main.id

  egress {
    description = "Allow outbound traffic for package installs, ECR pulls, and AWS APIs."
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "wynnmarket-app-instance"
  })
}

resource "aws_instance" "app" {
  count = var.enable_app_instance ? 1 : 0

  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type               = var.app_instance_type
  subnet_id                   = aws_subnet.public[0].id
  vpc_security_group_ids      = [aws_security_group.app_instance.id]
  iam_instance_profile        = aws_iam_instance_profile.app_instance.name
  associate_public_ip_address = true
  volume_tags = merge(local.common_tags, {
    Name = "wynnmarket-app-root"
  })

  user_data_replace_on_change = true
  user_data = templatefile("${path.module}/templates/app-user-data.sh.tftpl", {
    aws_region          = var.aws_region
    image_uri           = "${aws_ecr_repository.app.repository_url}:${var.app_image_tag}"
    container_name      = var.app_container_name
    dynamodb_table_name = aws_dynamodb_table.trade_market_listings.name
  })

  tags = merge(local.common_tags, {
    Name = "wynnmarket-app"
  })
}
