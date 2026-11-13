# -----------------------------------------------------------------------------
# security.tf - Security Group da aplicação
#
# O Security Group é um firewall com estado (stateful) ligado à interface de rede
# da EC2. Ele pertence a UMA VPC (vpc_id), por isso a VPC precisa existir antes.
#
# As regras são recursos separados (aws_vpc_security_group_*_rule), a forma atual
# recomendada pelo provider. Evite misturar com os blocos inline ingress/egress.
# -----------------------------------------------------------------------------

resource "aws_security_group" "app" {
  # name_prefix + create_before_destroy: se o grupo precisar ser substituído, o
  # novo é criado ANTES de o antigo ser removido (nomes diferentes, sem conflito).
  name_prefix = "${local.name}-sg-"
  description = "Dashboard EC2: HTTP de entrada, sem SSH"
  vpc_id      = local.vpc_id # referência: a VPC precisa existir primeiro

  tags = {
    Name = "${local.name}-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ENTRADA: somente HTTP (80). Não há regra para a porta 22: SSH fechado.
resource "aws_vpc_security_group_ingress_rule" "http" {
  security_group_id = aws_security_group.app.id
  description       = "HTTP para o Nginx"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = var.allowed_http_cidr
}

# SAÍDA: apenas o necessário.
#   80/tcp  -> repositórios apt do Ubuntu (usam HTTP)
#   443/tcp -> endpoints do Systems Manager (ssm, ssmmessages, ec2messages) e HTTPS em geral
#   53      -> DNS do resolvedor da VPC
resource "aws_vpc_security_group_egress_rule" "http" {
  security_group_id = aws_security_group.app.id
  description       = "Saida HTTP para pacotes apt"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "https" {
  security_group_id = aws_security_group.app.id
  description       = "Saida HTTPS para apt e agente SSM"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "dns_udp" {
  security_group_id = aws_security_group.app.id
  description       = "DNS (UDP) dentro da VPC"
  ip_protocol       = "udp"
  from_port         = 53
  to_port           = 53
  cidr_ipv4         = local.vpc_cidr
}

resource "aws_vpc_security_group_egress_rule" "dns_tcp" {
  security_group_id = aws_security_group.app.id
  description       = "DNS (TCP) dentro da VPC"
  ip_protocol       = "tcp"
  from_port         = 53
  to_port           = 53
  cidr_ipv4         = local.vpc_cidr
}
