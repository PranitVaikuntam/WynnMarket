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
  user_data = templatefile("${path.module}/templates/app-user-data-unattended.sh.tftpl", {
    aws_region          = var.aws_region
    repository_url      = aws_ecr_repository.app.repository_url
    app_image_tag       = var.app_image_tag
    container_name      = var.app_container_name
    dynamodb_table_name = aws_dynamodb_table.trade_market_listings.name
    server_address      = var.wynncraft_server_address
    startup_timeout     = var.startup_timeout_seconds
    scan_timeout        = var.scan_timeout_seconds
    health_marker       = var.health_marker_path
    log_group_name      = aws_cloudwatch_log_group.app.name
    auth_volume_id      = aws_ebs_volume.auth[0].id
    auth_mount_path     = "/mnt/wynnmarket-auth"
    deploy_script       = templatefile("${path.module}/templates/app-deploy.sh.tftpl", {})
  })

  lifecycle {
    ignore_changes = [ami, volume_tags]

    precondition {
      condition     = !var.enable_app_instance || (var.enable_auth_volume && var.auth_state_migrated)
      error_message = "The app instance requires enable_auth_volume=true and auth_state_migrated=true."
    }
  }

  tags = merge(local.common_tags, {
    Name = "wynnmarket-app"
  })
}

resource "aws_ebs_volume" "auth" {
  count = var.enable_auth_volume ? 1 : 0

  availability_zone = data.aws_availability_zones.available.names[0]
  encrypted         = true
  final_snapshot    = true
  kms_key_id        = var.auth_volume_kms_key_id
  size              = var.auth_volume_size_gib
  type              = var.auth_volume_type

  tags = merge(local.common_tags, {
    Name        = "wynnmarket-headlessmc-auth"
    sensitivity = "authentication"
  })
}

resource "aws_volume_attachment" "auth" {
  count = var.enable_app_instance && var.enable_auth_volume ? 1 : 0

  device_name = var.auth_volume_device_name
  instance_id = aws_instance.app[0].id
  volume_id   = aws_ebs_volume.auth[0].id
}
