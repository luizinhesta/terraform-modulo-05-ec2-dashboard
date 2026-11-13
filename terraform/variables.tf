# variables.tf - entradas do módulo 05.

variable "aws_region" {
  description = "Região AWS onde a EC2 será criada."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Nome do projeto, usado em nomes e na tag Project."
  type        = string
  default     = "tfpratica"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,19}$", var.project_name))
    error_message = "project_name deve ter 3 a 20 caracteres: minúsculas, números e hífen, começando por letra."
  }
}

variable "environment" {
  description = "Ambiente (tag Environment)."
  type        = string
  default     = "lab"

  validation {
    condition     = contains(["lab", "dev", "hml", "prd"], var.environment)
    error_message = "environment deve ser lab, dev, hml ou prd."
  }
}

# ---- Rede -------------------------------------------------------------------

variable "create_lab_network" {
  description = "true = cria VPC, subnet pública, Internet Gateway e Route Table do laboratório. false = usa uma VPC existente (data sources)."
  type        = bool
  default     = false
}

variable "vpc_id" {
  description = "ID de uma VPC existente. Se null (e create_lab_network = false), usa a VPC padrão da região."
  type        = string
  default     = null

  validation {
    condition     = var.vpc_id == null || can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id deve ter o formato vpc-xxxxxxxx."
  }
}

variable "subnet_id" {
  description = "ID de uma subnet existente da VPC. Se null, o Terraform escolhe a primeira subnet comprovadamente pública."
  type        = string
  default     = null

  validation {
    condition     = var.subnet_id == null || can(regex("^subnet-[0-9a-f]+$", var.subnet_id))
    error_message = "subnet_id deve ter o formato subnet-xxxxxxxx."
  }
}

variable "lab_vpc_cidr" {
  description = "CIDR da VPC criada quando create_lab_network = true."
  type        = string
  default     = "10.50.0.0/16"

  validation {
    condition     = can(cidrhost(var.lab_vpc_cidr, 0))
    error_message = "lab_vpc_cidr deve ser um CIDR válido."
  }
}

variable "lab_subnet_cidr" {
  description = "CIDR da subnet pública criada quando create_lab_network = true. Deve estar dentro de lab_vpc_cidr."
  type        = string
  default     = "10.50.1.0/24"

  validation {
    condition     = can(cidrhost(var.lab_subnet_cidr, 0))
    error_message = "lab_subnet_cidr deve ser um CIDR válido."
  }
}

# ---- Segurança --------------------------------------------------------------

variable "allowed_http_cidr" {
  description = "CIDR autorizado a acessar a porta 80. Para restringir ao seu IP use, por exemplo, 203.0.113.10/32."
  type        = string
  default     = "0.0.0.0/0"

  validation {
    condition     = can(cidrhost(var.allowed_http_cidr, 0))
    error_message = "allowed_http_cidr deve ser um CIDR válido."
  }
}

variable "enable_ssm" {
  description = "Cria IAM Role + Instance Profile com AmazonSSMManagedInstanceCore para acesso via Session Manager (sem SSH)."
  type        = bool
  default     = true
}

# ---- Instância --------------------------------------------------------------

variable "instance_type" {
  description = "Tipo da instância EC2."
  type        = string
  default     = "t3.micro"
}

variable "architecture" {
  description = "Arquitetura da AMI e da instância: x86_64 ou arm64 (ex.: t4g.micro é arm64)."
  type        = string
  default     = "x86_64"

  validation {
    condition     = contains(["x86_64", "arm64"], var.architecture)
    error_message = "architecture deve ser x86_64 ou arm64."
  }
}

variable "root_volume_size" {
  description = "Tamanho do volume root EBS (GiB). A AMI do Ubuntu exige no mínimo 8."
  type        = number
  default     = 8

  validation {
    condition     = var.root_volume_size >= 8 && var.root_volume_size <= 30
    error_message = "root_volume_size deve ficar entre 8 e 30 GiB."
  }
}
