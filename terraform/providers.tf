# providers.tf
# Credenciais vêm do perfil do AWS CLI (AWS_PROFILE). Nunca escreva chaves aqui.
#
# default_tags aplica as tags abaixo a TODOS os recursos que aceitam tags.
# No state elas aparecem em "tags_all" (tags do recurso + default_tags).
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      Module      = "modulo-05-ec2-dashboard"
      ManagedBy   = "terraform"
    }
  }
}
