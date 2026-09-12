data "aws_ssm_parameter" "ubuntu_ami" {
  count = var.ubuntu_ami_id == null ? 1 : 0

  name = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = [ "sts:AssumeRole" ]

    principals {
      type        = "Service"
      identifiers = [ "ec2.amazonaws.com" ]
    }
  }
}

locals {
  ubuntu_ami_id = var.ubuntu_ami_id != null ? var.ubuntu_ami_id : data.aws_ssm_parameter.ubuntu_ami[0].value
}

resource "aws_iam_role" "application" {
  name               = "${local.name}-application"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json

  tags = {
    Name = "${local.name}-application"
  }
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.application.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "application" {
  name = "${local.name}-application"
  role = aws_iam_role.application.name
}

resource "aws_key_pair" "application" {
  count = var.ssh_public_key == null ? 0 : 1

  key_name   = "${local.name}-deployment"
  public_key = var.ssh_public_key

  tags = {
    Name = "${local.name}-deployment"
  }
}

locals {
  ec2_key_name = coalesce(var.ssh_key_name, try(aws_key_pair.application[0].key_name, null))
}

resource "aws_instance" "application" {
  ami                         = local.ubuntu_ami_id
  instance_type               = var.ec2_instance_type
  subnet_id                   = aws_subnet.application.id
  vpc_security_group_ids      = [ aws_security_group.application.id ]
  iam_instance_profile        = aws_iam_instance_profile.application.name
  key_name                    = local.ec2_key_name
  associate_public_ip_address = false

  root_block_device {
    encrypted   = true
    volume_type = "gp3"
    volume_size = 20
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  lifecycle {
    precondition {
      condition     = (var.ssh_key_name != null) != (var.ssh_public_key != null)
      error_message = "Set exactly one of ssh_key_name or ssh_public_key so the application server is reachable by SSH."
    }

    precondition {
      condition     = length(var.ssh_allowed_cidrs) > 0
      error_message = "Set ssh_allowed_cidrs to at least one trusted CIDR range for SSH access."
    }
  }

  tags = {
    Name = "${local.name}-application"
    Role = "application"
  }
}

resource "aws_eip" "application" {
  domain   = "vpc"
  instance = aws_instance.application.id

  tags = {
    Name = "${local.name}-application"
  }
}
