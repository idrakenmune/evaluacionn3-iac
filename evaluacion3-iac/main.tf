terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

locals {
  tags_comunes = {
    Proyecto    = var.proyecto
    Ambiente    = var.ambiente
    Responsable = var.responsable
  }

  subredes_publicas = [
    for k, v in aws_subnet.subredes : v.id if var.subredes[k].tipo == "publica"
  ]

  subredes_privadas = [
    for k, v in aws_subnet.subredes : v.id if var.subredes[k].tipo == "privada"
  ]
}

# Busca automáticamente la última AMI de Amazon Linux 2023 (sin hardcodear)
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

# --- RED: VPC, SUBREDES, IGW Y RUTAS ---
resource "aws_vpc" "principal" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.tags_comunes, {
    Name = "${var.proyecto}-vpc-${var.ambiente}"
  })
}

resource "aws_subnet" "subredes" {
  for_each = var.subredes

  vpc_id                  = aws_vpc.principal.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = each.value.tipo == "publica"

  tags = merge(local.tags_comunes, {
    Name = "${var.proyecto}-${each.key}-${var.ambiente}"
  })
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.principal.id

  tags = merge(local.tags_comunes, {
    Name = "${var.proyecto}-igw-${var.ambiente}"
  })
}

resource "aws_route_table" "publica" {
  vpc_id = aws_vpc.principal.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = merge(local.tags_comunes, {
    Name = "${var.proyecto}-rt-publica-${var.ambiente}"
  })
}

resource "aws_route_table_association" "publicas" {
  for_each = {
    for k, v in var.subredes : k => v if v.tipo == "publica"
  }

  subnet_id      = aws_subnet.subredes[each.key].id
  route_table_id = aws_route_table.publica.id
}

# --- SECURITY GROUPS ---
resource "aws_security_group" "servidores" {
  name        = "${var.proyecto}-sg-servidores-${var.ambiente}"
  description = "Permite HTTP y SSH a los servidores de la biblioteca"
  vpc_id      = aws_vpc.principal.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags_comunes, {
    Name = "${var.proyecto}-sg-servidores-${var.ambiente}"
  })
}

resource "aws_security_group" "rds" {
  name        = "${var.proyecto}-sg-rds-${var.ambiente}"
  description = "Solo permite MySQL desde el Security Group de los servidores"
  vpc_id      = aws_vpc.principal.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.servidores.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags_comunes, {
    Name = "${var.proyecto}-sg-rds-${var.ambiente}"
  })
}

# --- SERVIDORES EC2 (for_each + condicional de disco) ---
resource "aws_instance" "servidores" {
  for_each = var.servidores

  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = each.value.tipo_instancia
  subnet_id              = aws_subnet.subredes[each.value.subred].id
  vpc_security_group_ids = [aws_security_group.servidores.id]
  key_name               = var.key_name

  root_block_device {
    volume_size = var.ambiente == "prod" ? each.value.disco * 2 : each.value.disco
    volume_type = "gp3"
  }

  user_data = <<-EOF
              #!/bin/bash
              dnf update -y
              dnf install -y httpd mariadb105
              systemctl start httpd
              systemctl enable httpd
              echo "<h1>Biblioteca Digital - Servidor ${each.key} (${var.ambiente})</h1>" > /var/www/html/index.html
              EOF

  tags = merge(local.tags_comunes, {
    Name = "${each.key}-${var.ambiente}"
  })
}

# --- NLB, TARGET GROUP, LISTENER Y TARGETS (for_each) ---
resource "aws_lb" "nlb" {
  name               = "${var.proyecto}-nlb-${var.ambiente}"
  internal           = false
  load_balancer_type = "network"
  subnets            = local.subredes_publicas

  tags = merge(local.tags_comunes, {
    Name = "${var.proyecto}-nlb-${var.ambiente}"
  })
}

resource "aws_lb_target_group" "tg" {
  name     = "${var.proyecto}-tg-${var.ambiente}"
  port     = 80
  protocol = "TCP"
  vpc_id   = aws_vpc.principal.id

  tags = merge(local.tags_comunes, {
    Name = "${var.proyecto}-tg-${var.ambiente}"
  })
}

resource "aws_lb_listener" "tcp" {
  load_balancer_arn = aws_lb.nlb.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

resource "aws_lb_target_group_attachment" "targets" {
  for_each = aws_instance.servidores

  target_group_arn = aws_lb_target_group.tg.arn
  target_id        = each.value.id
  port             = 80
}

# --- RDS MYSQL EN SUBREDES PRIVADAS (condicional Multi-AZ) ---
resource "aws_db_subnet_group" "rds" {
  name       = "${var.proyecto}-rds-subnet-group-${var.ambiente}"
  subnet_ids = local.subredes_privadas

  tags = merge(local.tags_comunes, {
    Name = "${var.proyecto}-rds-subnet-group-${var.ambiente}"
  })
}

resource "aws_db_instance" "mysql" {
  identifier             = "${var.proyecto}-mysql-${var.ambiente}"
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  username               = var.db_username
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.rds.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false
  multi_az               = var.ambiente == "prod"
  skip_final_snapshot    = true

  tags = merge(local.tags_comunes, {
    Name = "${var.proyecto}-mysql-${var.ambiente}"
  })
}

# --- BUCKET S3 (format + condicional de versionado) ---
resource "aws_s3_bucket" "material" {
  bucket        = format("%s-%s-%s-%s", var.proyecto, var.aplicacion, var.ambiente, var.s3_sufijo_unico)
  force_destroy = true

  tags = merge(local.tags_comunes, {
    Name = format("%s-%s-%s", var.proyecto, var.aplicacion, var.ambiente)
  })
}

resource "aws_s3_bucket_versioning" "material" {
  bucket = aws_s3_bucket.material.id

  versioning_configuration {
    status = var.ambiente == "prod" ? "Enabled" : "Suspended"
  }
}