# Creates an IAM role for the EC2 instance to assume
resource "aws_iam_role" "app_role" {
  name               = "wynnmarket-app-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust.json

  tags = local.common_tags
}

# Attaches an IAM role policy for the EC2 instance role - inline 
resource "aws_iam_role_policy" "app_permissions" {
  name   = "wynnmarket-app-permissions"
  role   = aws_iam_role.app_role.id
  policy = data.aws_iam_policy_document.app_permissions.json
}

# Attaches the AmazonSSMManagedInstanceCore policy to the EC2 instance role
resource "aws_iam_role_policy_attachment" "ssm_permissions" {
  role       = aws_iam_role.app_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Creates an IAM instance profile for the EC2 instance to use
resource "aws_iam_instance_profile" "app_profile" {
  name = "wynnmarket-app-profile"
  role = aws_iam_role.app_role.name

  tags = local.common_tags
}


#JSON of the document that allows EC2 instances to assume the role
data "aws_iam_policy_document" "ec2_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# JSON of the document that defines the permissions for the EC2 instance
data "aws_iam_policy_document" "app_permissions" {
  statement {
    sid = "ReadAppImageFromEcr"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer"
    ]
    resources = [aws_ecr_repository.app.arn]
  }

  statement {
    sid       = "AuthorizeEcrLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "ReadTradeMarketListings"
    actions = [
      "dynamodb:DescribeTable",
      "dynamodb:Query",
      "dynamodb:Scan"
    ]
    resources = [
      aws_dynamodb_table.trade_market_listings.arn,
      "${aws_dynamodb_table.trade_market_listings.arn}/index/*"
    ]
  }

  statement {
    sid = "WriteTradeMarketListings"
    actions = [
      "dynamodb:BatchWriteItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem"
    ]
    resources = [
      aws_dynamodb_table.trade_market_listings.arn,
      "${aws_dynamodb_table.trade_market_listings.arn}/index/*"
    ]
  }

  statement {
    sid = "WriteContainerLogs"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["${aws_cloudwatch_log_group.app.arn}:*"]
  }
}

