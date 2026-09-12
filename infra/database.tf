resource "random_password" "database" {
  count = var.database_password == null ? 1 : 0

  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "random_id" "database_final_snapshot" {
  byte_length = 4
}

locals {
  database_password = var.database_password != null ? var.database_password : random_password.database[0].result
}

resource "aws_db_subnet_group" "database" {
  name       = "${local.name}-database"
  subnet_ids = aws_subnet.database[*].id

  tags = {
    Name = "${local.name}-database"
  }
}

resource "aws_db_instance" "database" {
  identifier             = "${local.name}-database"
  allocated_storage      = 20
  max_allocated_storage  = 50
  storage_type           = "gp3"
  storage_encrypted      = true
  engine                 = "postgres"
  engine_version         = var.database_engine_version
  instance_class         = var.rds_instance_class
  db_name                = var.database_name
  username               = var.database_username
  password               = local.database_password
  port                   = 5432
  db_subnet_group_name   = aws_db_subnet_group.database.name
  vpc_security_group_ids = [ aws_security_group.database.id ]
  publicly_accessible    = false
  multi_az               = false

  backup_retention_period   = 7
  copy_tags_to_snapshot     = true
  skip_final_snapshot       = var.rds_skip_final_snapshot
  final_snapshot_identifier = var.rds_skip_final_snapshot ? null : "${local.name}-final-${random_id.database_final_snapshot.hex}"

  auto_minor_version_upgrade = true
  apply_immediately          = false

  tags = {
    Name = "${local.name}-database"
    Role = "database"
  }
}
