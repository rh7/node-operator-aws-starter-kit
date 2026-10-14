# idos-kgw's compose.prod.yaml sends container logs to CloudWatch with the awslogs driver,
# using the group "/ec2/$ENVIRONMENT-idos-kwil-node/containers". The driver does not create
# the group and needs the instance role to write to it; without both, the containers fail
# to start. Set ENVIRONMENT in idos-kgw's .env to var.environment.

resource "aws_cloudwatch_log_group" "node" {
  name              = "/ec2/${var.environment}-idos-kwil-node/containers"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${var.name} idOS node containers"
  }
}

resource "aws_iam_role_policy" "node_logs" {
  name = "idos-node-container-logs"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.node.arn}:*"
      }
    ]
  })
}
