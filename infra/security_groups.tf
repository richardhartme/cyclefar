resource "aws_security_group" "application" {
  name        = "${local.name}-application"
  description = "Public access to the CycleFar application server"
  vpc_id      = aws_vpc.main.id

  dynamic "ingress" {
    for_each = toset(var.ssh_allowed_cidrs)

    content {
      description = "SSH for administration and Kamal deployment"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = [ ingress.value ]
    }
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [ "0.0.0.0/0" ]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [ "0.0.0.0/0" ]
  }

  egress {
    description = "Application outbound traffic, including image pulls and external APIs"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [ "0.0.0.0/0" ]
  }

  tags = {
    Name = "${local.name}-application"
  }
}

resource "aws_security_group" "database" {
  name        = "${local.name}-database"
  description = "PostgreSQL access only from the CycleFar application server"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "PostgreSQL from the application server"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [ aws_security_group.application.id ]
  }

  egress = []

  tags = {
    Name = "${local.name}-database"
  }
}
