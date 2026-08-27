resource "aws_cloudwatch_log_group" "app" {
  name              = "/wynnmarket/container"
  retention_in_days = var.cloudwatch_log_retention_days
  tags              = local.common_tags
}

resource "aws_sns_topic" "alarms" {
  name = "wynnmarket-alarms"
  tags = local.common_tags
}

resource "aws_sns_topic_subscription" "email" {
  count = var.alert_email == null ? 0 : 1

  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_log_metric_filter" "scan_heartbeat" {
  name           = "wynnmarket-valid-scan-heartbeat"
  log_group_name = aws_cloudwatch_log_group.app.name
  pattern        = "event=scan_heartbeat"

  metric_transformation {
    name      = "ValidScanHeartbeat"
    namespace = "WynnMarket"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "missing_scan_heartbeat" {
  count = var.enable_app_instance ? 1 : 0

  alarm_name          = "wynnmarket-missing-scan-heartbeat"
  alarm_description   = "No valid Auction House scan heartbeat was logged within ten minutes."
  namespace           = "WynnMarket"
  metric_name         = "ValidScanHeartbeat"
  statistic           = "Sum"
  period              = var.scan_timeout_seconds
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  comparison_operator = "LessThanThreshold"
  threshold           = 1
  treat_missing_data  = "breaching"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]
  tags                = local.common_tags
}

resource "aws_cloudwatch_log_metric_filter" "dynamodb_write_failure" {
  name           = "wynnmarket-dynamodb-write-failure"
  log_group_name = aws_cloudwatch_log_group.app.name
  pattern        = "event=dynamodb_write_failure"

  metric_transformation {
    name      = "DynamoDbWriteFailure"
    namespace = "WynnMarket"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "dynamodb_write_failure" {
  alarm_name          = "wynnmarket-dynamodb-write-failure"
  alarm_description   = "At least one Trade Market listing failed to write to DynamoDB."
  namespace           = "WynnMarket"
  metric_name         = "DynamoDbWriteFailure"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 1
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]
  tags                = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "ec2_system_status" {
  count = var.enable_app_instance ? 1 : 0

  alarm_name          = "wynnmarket-ec2-system-status"
  alarm_description   = "The EC2 host failed system status checks; automatic recovery is requested."
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed_System"
  dimensions          = { InstanceId = aws_instance.app[0].id }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 1
  treat_missing_data  = "missing"
  alarm_actions = [
    aws_sns_topic.alarms.arn,
    "arn:aws:automate:${var.aws_region}:ec2:recover"
  ]
  ok_actions = [aws_sns_topic.alarms.arn]
  tags       = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "ec2_status" {
  count = var.enable_app_instance ? 1 : 0

  alarm_name          = "wynnmarket-ec2-status"
  alarm_description   = "The EC2 host failed an instance or system status check."
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed"
  dimensions          = { InstanceId = aws_instance.app[0].id }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 1
  treat_missing_data  = "missing"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]
  tags                = local.common_tags
}
