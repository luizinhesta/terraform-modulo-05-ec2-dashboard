# -----------------------------------------------------------------------------
# ec2.tf - AMI, User Data e instância EC2
# -----------------------------------------------------------------------------

locals {
  name = "${var.project_name}-m05-${var.environment}"

  # Mapa arquitetura EC2 -> sufixo usado no nome da AMI do Ubuntu.
  ami_arch_suffix = {
    x86_64 = "amd64"
    arm64  = "arm64"
  }

  # destino na EC2 => origem na pasta application/ (caminhos relativos).
  app_files = {
    "/opt/dashboard/server.py"              = "backend/server.py"
    "/var/www/dashboard/index.html"         = "frontend/index.html"
    "/var/www/dashboard/style.css"          = "frontend/style.css"
    "/var/www/dashboard/app.js"             = "frontend/app.js"
    "/etc/systemd/system/dashboard.service" = "system/dashboard.service"
    "/etc/nginx/conf.d/dashboard.conf"      = "system/dashboard.nginx.conf"
  }

  # templatefile lê o .tftpl e substitui ${files}. base64gzip comprime e codifica
  # cada arquivo: o código da aplicação viaja DENTRO do User Data (limite: 16 KB).
  # replace(..., "\r\n", "\n") garante finais de linha Linux mesmo se o Git no
  # Windows converter os arquivos para CRLF (bash e systemd não toleram \r).
  user_data = replace(templatefile("${path.module}/templates/user_data.sh.tftpl", {
    files = {
      for dest, src in local.app_files :
      dest => base64gzip(replace(file("${path.module}/../application/${src}"), "\r\n", "\n"))
    }
  }), "\r\n", "\n")
}

# Informações sobre o tipo de instância escolhido (ex.: arquiteturas suportadas).
data "aws_ec2_instance_type" "selected" {
  instance_type = var.instance_type
}

# AMI Ubuntu 24.04 LTS oficial (Canonical), pesquisada por filtros. O ID da AMI
# nunca é escrito no código: muda a cada nova versão publicada.
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-${local.ami_arch_suffix[var.architecture]}-server-*"]
  }

  filter {
    name   = "architecture"
    values = [var.architecture]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

resource "aws_instance" "app" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = local.subnet_id
  vpc_security_group_ids      = [aws_security_group.app.id]
  associate_public_ip_address = true # IP público automático (não é Elastic IP)
  iam_instance_profile        = var.enable_ssm ? aws_iam_instance_profile.ec2[0].name : null

  user_data                   = local.user_data
  user_data_replace_on_change = true # mudou o User Data => a instância é SUBSTITUÍDA

  # IMDSv2 obrigatório: protege as credenciais da instância contra SSRF.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    encrypted             = true
    delete_on_termination = true

    tags = {
      Name = "${local.name}-root"
    }
  }

  tags = {
    Name = local.name
  }

  lifecycle {
    # A AMI mais recente muda com o tempo. Sem isso, qualquer nova publicação da
    # Canonical faria o próximo plan propor substituir a instância.
    ignore_changes = [ami]

    precondition {
      condition     = contains(data.aws_ec2_instance_type.selected.supported_architectures, var.architecture)
      error_message = "O tipo ${var.instance_type} não suporta a arquitetura ${var.architecture}. Ajuste instance_type ou architecture."
    }

    precondition {
      condition     = local.subnet_id != null
      error_message = "Nenhuma subnet pública elegível foi encontrada. Informe subnet_id ou use create_lab_network = true."
    }

    precondition {
      condition     = local.subnet_pub
      error_message = "A subnet escolhida não é pública: sua route table efetiva não tem rota 0.0.0.0/0 para um Internet Gateway."
    }

    precondition {
      condition     = length(local.user_data) <= 16384
      error_message = "O User Data excede 16 KB. Reduza os arquivos da aplicação."
    }
  }
}
