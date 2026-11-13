# Destruir - Módulo 05 (EC2 Server Dashboard)

O `terraform destroy` remove **somente o que está no state deste módulo**. VPC, subnets, route tables e Internet Gateways **preexistentes** foram apenas lidos por data sources e não são tocados.

> `destroy` é irreversível. Confirme conta e região antes.

## 1. Conferir o contexto

```powershell
cd etapa-02-aplicacoes-aws/modulo-05-ec2-dashboard/terraform
$env:AWS_PROFILE = "<seu-perfil>"
aws sts get-caller-identity
terraform state list
```

`terraform state list` mostra exatamente o que será removido. Linhas que começam com `data.` são leituras e não são apagadas.

Se o módulo foi aplicado com `create_lab_network = true`, a lista incluirá `aws_vpc.lab[0]`, `aws_subnet.lab[0]` e afins: eles pertencem ao laboratório e serão removidos. Com uma VPC existente, essas linhas não existem.

## 2. Simular a destruição

```powershell
terraform plan -destroy
```

Confira `Plan: 0 to add, 0 to change, N to destroy.` e leia a lista. Não deve aparecer nenhuma VPC, subnet ou IGW que não seja `aws_vpc.lab`, `aws_subnet.lab`, `aws_internet_gateway.lab`, `aws_route_table.lab` ou `aws_route_table_association.lab`.

![terraform plan -destroy](imagens/imagem%20%2827%29.png)
*Figura: `terraform plan -destroy` listando apenas o que pertence ao módulo.*

## 3. Destruir

```powershell
terraform destroy
```

Digite `yes` somente após conferir. Ordem seguida pelo Terraform (inversa da criação):

1. Instância EC2 (e volume root, por `delete_on_termination`).
2. Regras do Security Group, Instance Profile, attachment e role.
3. Security Group.
4. Associação de rota, route table, subnet, IGW e VPC (apenas se criados pelo módulo).

![terraform destroy em execução](imagens/imagem%20%2828%29.png)
*Figura: `terraform destroy` removendo os recursos na ordem inversa da criação.*

## 4. Confirmar a remoção

```powershell
terraform state list        # deve estar vazio
aws ec2 describe-instances --filters "Name=tag:Project,Values=tfpratica" "Name=tag:Module,Values=modulo-05-ec2-dashboard" `
  --query "Reservations[].Instances[].[InstanceId,State.Name]"
```

A instância deve estar `terminated` (some da lista em poucos minutos). Se você mudou `project_name`, ajuste o filtro.

Para a rede criada pelo módulo:

```powershell
aws ec2 describe-vpcs --filters "Name=tag:Module,Values=modulo-05-ec2-dashboard" --query "Vpcs[].VpcId"
```

A saída deve ser vazia.

![Confirmação da remoção pela AWS CLI](imagens/imagem%20%2829%29.png)
*Figura: `state list` vazio e instâncias em `terminated`.*

![Confirmação de que não restou VPC do módulo](imagens/imagem%20%281%29.png)
*Figura: consulta de VPCs do módulo retornando lista vazia.*

## 5. Se o destroy falhar

| Erro | Causa | Solução |
|---|---|---|
| `DependencyViolation` na VPC/subnet | Algo criado fora do Terraform usa a rede (por exemplo, uma interface de rede) | Localize e remova o recurso externo, depois rode `terraform destroy` de novo |
| `UnauthorizedOperation` | Falta de permissão | Revise o perfil |
| Timeout | Instância demorando a encerrar | Rode `terraform destroy` novamente |

Não apague recursos do módulo pelo console: o state ficaria divergente. Se isso acontecer, `terraform plan -refresh-only` mostra a diferença.

## 6. Limpeza local (opcional)

O state local fica em `terraform/terraform.tfstate` e não vai para o Git. Depois do destroy ele está vazio. Pode manter `terraform.tfvars` para uma nova execução.
