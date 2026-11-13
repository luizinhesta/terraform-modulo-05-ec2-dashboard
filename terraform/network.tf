# -----------------------------------------------------------------------------
# network.tf - Rede da aplicação
#
# Dois caminhos, escolhidos por var.create_lab_network:
#
#   false (padrão) -> LÊ uma VPC existente com data sources (nada é criado).
#   true           -> CRIA VPC, subnet, Internet Gateway, Route Table e associação.
#
# Em ambos, o resultado final são dois locals: local.vpc_id e local.subnet_id.
# O restante do módulo usa só esses locals e não sabe de onde eles vieram.
# -----------------------------------------------------------------------------

locals {
  use_existing_network = !var.create_lab_network
}

# ============================================================================
# CAMINHO A - rede existente (data sources: somente leitura)
# ============================================================================

# Se vpc_id não foi informado, procura a VPC padrão da região.
data "aws_vpcs" "default" {
  count = local.use_existing_network && var.vpc_id == null ? 1 : 0

  filter {
    name   = "is-default"
    values = ["true"]
  }
}

locals {
  existing_vpc_id = local.use_existing_network ? (
    var.vpc_id != null ? var.vpc_id : try(one(data.aws_vpcs.default[0].ids), null)
  ) : null
}

# Detalhes da VPC escolhida (CIDR, DNS etc.).
data "aws_vpc" "selected" {
  count = local.use_existing_network ? 1 : 0
  id    = local.existing_vpc_id

  lifecycle {
    postcondition {
      condition     = self.id != null && self.id != ""
      error_message = "Nenhuma VPC encontrada. Informe vpc_id ou use create_lab_network = true."
    }
  }
}

# Subnets da VPC e detalhes de cada uma (AZ, CIDR).
data "aws_subnets" "vpc" {
  count = local.use_existing_network ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [local.existing_vpc_id]
  }
}

data "aws_subnet" "each" {
  for_each = local.use_existing_network ? toset(data.aws_subnets.vpc[0].ids) : toset([])
  id       = each.value
}

# Todas as route tables da VPC, com suas rotas e associações.
data "aws_route_tables" "vpc" {
  count = local.use_existing_network ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [local.existing_vpc_id]
  }
}

data "aws_route_table" "each" {
  for_each       = local.use_existing_network ? toset(data.aws_route_tables.vpc[0].ids) : toset([])
  route_table_id = each.value
}

# Zonas de disponibilidade onde o tipo de instância escolhido existe.
# Serve para não escolher uma subnet em uma AZ que não oferece o tipo.
data "aws_ec2_instance_type_offerings" "az" {
  location_type = "availability-zone"

  filter {
    name   = "instance-type"
    values = [var.instance_type]
  }
}

# Internet Gateways citados nas rotas. O filtro attachment.vpc-id exige que cada
# um esteja ANEXADO à VPC; se estiver desanexado, o data source falha (rota inútil).
locals {
  igw_ids_in_routes = toset(flatten([
    for rt in data.aws_route_table.each : [
      for r in rt.routes : r.gateway_id if try(startswith(r.gateway_id, "igw-"), false)
    ]
  ]))
}

data "aws_internet_gateway" "attached" {
  for_each            = local.igw_ids_in_routes
  internet_gateway_id = each.value

  filter {
    name   = "attachment.vpc-id"
    values = [local.existing_vpc_id]
  }
}

locals {
  # Resumo de cada route table: tem rota 0.0.0.0/0 para um Internet Gateway?
  # Quais subnets estão associadas EXPLICITAMENTE a ela? É a tabela principal (main)?
  route_table_summary = {
    for rt_id, rt in data.aws_route_table.each : rt_id => {
      default_route_to_igw = anytrue([
        for r in rt.routes : r.cidr_block == "0.0.0.0/0" && try(startswith(r.gateway_id, "igw-"), false)
      ])
      subnet_ids = compact([for a in rt.associations : try(a.subnet_id, "")])
      is_main    = anytrue([for a in rt.associations : a.main])
    }
  }

  main_route_table_is_public = anytrue([
    for rt in local.route_table_summary : rt.is_main && rt.default_route_to_igw
  ])

  # Regra da AWS: subnet sem associação explícita usa a route table principal.
  # Subnet pública = a route table EFETIVA tem rota padrão para um Internet Gateway.
  # O NOME da subnet não é considerado.
  subnet_is_public = {
    for sid, _ in data.aws_subnet.each : sid => (
      anytrue([
        for rt in local.route_table_summary : contains(rt.subnet_ids, sid) && rt.default_route_to_igw
        ]) || (
        !anytrue([for rt in local.route_table_summary : contains(rt.subnet_ids, sid)]) && local.main_route_table_is_public
      )
    )
  }

  # Subnets públicas em AZs que oferecem o tipo de instância (ordenadas para ser determinístico).
  eligible_subnet_ids = sort([
    for sid, s in data.aws_subnet.each : sid
    if local.subnet_is_public[sid] && contains(data.aws_ec2_instance_type_offerings.az.locations, s.availability_zone)
  ])

  existing_subnet_id = local.use_existing_network ? (
    var.subnet_id != null ? var.subnet_id : try(local.eligible_subnet_ids[0], null)
  ) : null
}

# ============================================================================
# CAMINHO B - rede do laboratório (resources: criados e destruídos pelo Terraform)
# Sem NAT Gateway e sem Elastic IP.
# ============================================================================

resource "aws_vpc" "lab" {
  count = var.create_lab_network ? 1 : 0

  cidr_block           = var.lab_vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${local.name}-vpc"
  }
}

resource "aws_internet_gateway" "lab" {
  count = var.create_lab_network ? 1 : 0

  vpc_id = aws_vpc.lab[0].id # dependência implícita: a VPC é criada primeiro

  tags = {
    Name = "${local.name}-igw"
  }
}

resource "aws_subnet" "lab" {
  count = var.create_lab_network ? 1 : 0

  vpc_id                  = aws_vpc.lab[0].id
  cidr_block              = var.lab_subnet_cidr
  availability_zone       = sort(data.aws_ec2_instance_type_offerings.az.locations)[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name}-subnet-publica"
  }
}

resource "aws_route_table" "lab" {
  count = var.create_lab_network ? 1 : 0

  vpc_id = aws_vpc.lab[0].id

  # Rota padrão: todo tráfego que não é local sai pelo Internet Gateway.
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.lab[0].id
  }

  tags = {
    Name = "${local.name}-rt-publica"
  }
}

resource "aws_route_table_association" "lab" {
  count = var.create_lab_network ? 1 : 0

  subnet_id      = aws_subnet.lab[0].id
  route_table_id = aws_route_table.lab[0].id
}

# ============================================================================
# Resultado único consumido pelo restante do módulo
# ============================================================================

locals {
  vpc_id     = var.create_lab_network ? aws_vpc.lab[0].id : local.existing_vpc_id
  vpc_cidr   = var.create_lab_network ? aws_vpc.lab[0].cidr_block : data.aws_vpc.selected[0].cidr_block
  subnet_id  = var.create_lab_network ? aws_subnet.lab[0].id : local.existing_subnet_id
  subnet_pub = var.create_lab_network ? true : lookup(local.subnet_is_public, local.existing_subnet_id == null ? "none" : local.existing_subnet_id, false)

  # Pontos que o Terraform exibe como diagnóstico no output "network_diagnosis".
  internet_gateway_ids = var.create_lab_network ? [aws_internet_gateway.lab[0].id] : sort(keys(data.aws_internet_gateway.attached))
}
