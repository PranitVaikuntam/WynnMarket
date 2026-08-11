data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_db_subnet_group" "main" {
  name       = "wynnmarket-db-subnet-group"
  subnet_ids = data.aws_subnets.default.ids

  tags = {
    Name = "wynnmarket-db-subnet-group"
  }
}

resource "aws_security_group" "rds" {
  name        = "wynnmarket-rds-sg"
  description = "Allow PostgreSQL connections"
  vpc_id      = data.aws_vpc.default.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "wynnmarket-rds-sg"
  }
}

resource "aws_security_group_rule" "rds_from_data_ingestion_lambda" {
  type = "ingress"

  security_group_id        = aws_security_group.rds.id
  source_security_group_id = aws_security_group.data_ingestion_lambda.id

  description = "PostgreSQL access from data ingestion Lambda"
  from_port   = 5432
  to_port     = 5432
  protocol    = "tcp"
}

resource "aws_db_instance" "postgres" {
  identifier = "wynnmarket-postgres"

  engine         = "postgres"
  instance_class = "db.t4g.micro"

  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = "wynnmarket"
  username = var.database.username
  password = var.database.password
  port     = 5432

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  publicly_accessible = false
  multi_az            = false

  backup_retention_period = 7
  deletion_protection     = false
  skip_final_snapshot     = true

  apply_immediately = true

  tags = {
    Name        = "wynnmarket-postgres"
    Environment = "development"
  }
}
