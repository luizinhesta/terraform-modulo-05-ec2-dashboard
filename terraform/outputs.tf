output "instance_id" {
  description = "ID da instância EC2."
  value       = aws_instance.app.id
}

output "public_ip" {
  description = "IP público (muda se a instância for parada/iniciada ou substituída)."
  value       = aws_instance.app.public_ip
}

output "app_url" {
  description = "URL HTTP do dashboard."
  value       = "http://${aws_instance.app.public_ip}"
}

output "vpc_id" {
  description = "VPC utilizada."
  value       = local.vpc_id
}

output "subnet_id" {
  description = "Subnet utilizada."
  value       = local.subnet_id
}

output "security_group_id" {
  description = "Security Group da aplicação."
  value       = aws_security_group.app.id
}

output "ami_id" {
  description = "AMI Ubuntu resolvida pelo data source."
  value       = data.aws_ami.ubuntu.id
}

output "network_diagnosis" {
  description = "Evidências usadas para aceitar a subnet como pública."
  value = {
    network_mode      = var.create_lab_network ? "criada pelo Terraform" : "existente (data sources)"
    vpc_cidr          = local.vpc_cidr
    internet_gateways = local.internet_gateway_ids
    subnet_is_public  = local.subnet_pub
  }
}

output "ssm_session_command" {
  description = "Comando para abrir sessão no Session Manager (requer AWS CLI + plugin do Session Manager)."
  value       = var.enable_ssm ? "aws ssm start-session --target ${aws_instance.app.id} --region ${var.aws_region}" : "SSM desabilitado (enable_ssm = false)"
}
