# Implantação - Módulo 05 (EC2 Server Dashboard)

Todos os recursos são criados pelo Terraform. Não crie nada pelo console da AWS. Os comandos abaixo são para PowerShell.

Nada neste repositório executa `apply` ou `destroy` por você.

## 1. Pré-requisitos

```powershell
terraform version                       # 1.5 ou superior
aws --version                           # AWS CLI v2
aws sso login --profile <seu-perfil>
$env:AWS_PROFILE = "<seu-perfil>"
aws sts get-caller-identity             # confirme a conta ANTES de aplicar
```

Opcional, para o terminal da EC2: instale o [plugin do Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html).

## 2. Escolher VPC e subnet

Você tem três opções. Escolha **uma**.

| Opção | Quando usar | Variáveis |
|---|---|---|
| A. VPC padrão | A conta tem VPC padrão na região | nenhuma (deixe `vpc_id` e `subnet_id` nulos) |
| B. VPC/subnet específicas | Você já tem uma rede de laboratório | `vpc_id` e, se quiser, `subnet_id` |
| C. Rede criada pelo Terraform | Não há rede adequada | `create_lab_network = true` |

### 2.1 Listar redes existentes (opções A e B)

```powershell
aws ec2 describe-vpcs --query "Vpcs[].[VpcId,CidrBlock,IsDefault]" --output table
aws ec2 describe-subnets --filters Name=vpc-id,Values=<vpc-id> `
  --query "Subnets[].[SubnetId,AvailabilityZone,CidrBlock,MapPublicIpOnLaunch]" --output table
```

![Listagem de VPCs e subnets com a AWS CLI](imagens/imagem%20%2814%29.png)
*Figura: `aws ec2 describe-vpcs` e `describe-subnets` listando a rede existente.*

### 2.2 Confirmar as rotas

Não confie no nome da subnet. Verifique o roteamento:

```powershell
aws ec2 describe-route-tables --filters Name=vpc-id,Values=<vpc-id> --output json
aws ec2 describe-internet-gateways --filters Name=attachment.vpc-id,Values=<vpc-id> `
  --query "InternetGateways[].InternetGatewayId"
```

Regras para interpretar:

1. Se a subnet aparece em `Associations[].SubnetId` de uma route table, essa é a route table dela.
2. Se não aparece em nenhuma, vale a route table **principal** (`Associations[].Main = true`).
3. A route table efetiva precisa ter uma rota `0.0.0.0/0` com `GatewayId = igw-...` (não `blackhole`).

O Terraform repete essa análise por código. Se a subnet não for pública, o `plan` falha com a mensagem "A subnet escolhida não é pública".

![Consulta dos Internet Gateways anexados à VPC](imagens/imagem%20%2815%29.png)
*Figura: `aws ec2 describe-internet-gateways` confirmando o IGW anexado à VPC.*

## 3. Configurar variáveis

```powershell
cd etapa-02-aplicacoes-aws/modulo-05-ec2-dashboard/terraform
Copy-Item terraform.tfvars.example terraform.tfvars
notepad terraform.tfvars
```

Exemplos:

```hcl
# Opção A: nada a configurar. Opção B:
vpc_id    = "vpc-0123456789abcdef0"
subnet_id = "subnet-0123456789abcdef0"

# Opção C:
create_lab_network = true
lab_vpc_cidr       = "10.50.0.0/16"
lab_subnet_cidr    = "10.50.1.0/24"

# Restringir o acesso ao seu IP (recomendado):
allowed_http_cidr = "203.0.113.10/32"
```

O arquivo `terraform.tfvars` não vai para o Git (`.gitignore`).

![Arquivo terraform.tfvars e validação com terraform fmt e validate](imagens/imagem%20%282%29.png)
*Figura: `terraform.tfvars` configurado e a saída de `terraform fmt -check` e `terraform validate`.*

## 4. Executar o Terraform

```powershell
terraform init
terraform fmt -check
terraform validate
terraform plan -out tfplan
```

Leia o `plan` antes de continuar:

- Procure `Plan: N to add, 0 to change, 0 to destroy.` Com os padrões, N = 10 (opção A/B) ou 15 (opção C).
- Todo recurso deve ser `+`. Nenhum `-` em uma primeira execução.
- `public_ip` e `id` aparecem como `(known after apply)`.
- Em `aws_instance.app`, confirme `associate_public_ip_address = true`, `encrypted = true` e `http_tokens = "required"`.

Quando estiver de acordo:

```powershell
terraform apply tfplan
```

Ao final, o Terraform imprime os outputs:

```powershell
terraform output
terraform output -raw app_url
```

Outputs: `instance_id`, `public_ip`, `app_url`, `vpc_id`, `subnet_id`, `security_group_id`, `ami_id`, `network_diagnosis` e `ssm_session_command`.

![Outputs exibidos pelo terraform output](imagens/imagem%20%2816%29.png)
*Figura: `terraform output` com os outputs do módulo.*

![terraform plan sem alterações](imagens/imagem%20%2813%29.png)
*Figura: `terraform plan` após o apply, com `No changes`: o código e a infraestrutura estão iguais.*

## 5. Aguardar o bootstrap

O `apply` termina quando a AWS cria a instância, não quando o User Data acaba. A instalação leva de 1 a 3 minutos. Nesse intervalo o navegador pode mostrar erro de conexão.

Teste periodicamente:

```powershell
curl.exe -s -o NUL -w "%{http_code}`n" "$(terraform output -raw app_url)/api/status"
```

`200` indica que a aplicação está no ar.

## 6. Consultar logs, Nginx e systemd (Session Manager)

Confirme que o agente registrou a instância (pode levar 1 a 3 minutos):

```powershell
aws ssm describe-instance-information --filters Key=InstanceIds,Values=$(terraform output -raw instance_id) `
  --query "InstanceInformationList[].PingStatus"
```

Abra a sessão:

```powershell
aws ssm start-session --target $(terraform output -raw instance_id)
```

Dentro da EC2:

```bash
sudo cloud-init status --long                   # status: done
sudo tail -n 60 /var/log/dashboard-bootstrap.log
sudo tail -n 60 /var/log/cloud-init-output.log
systemctl status dashboard nginx --no-pager
sudo journalctl -u dashboard -n 30 --no-pager
sudo nginx -t
sudo ss -ltnp | grep -E ':(80|8000)\b'
```

Resultado esperado em `ss`: o Nginx em `0.0.0.0:80` e o Python em `127.0.0.1:8000`.

![Agente SSM Online e sessão aberta no Session Manager](imagens/imagem%20%2817%29.png)
*Figura: `PingStatus` Online e abertura da sessão com `aws ssm start-session`, sem SSH.*

![Logs do cloud-init e do bootstrap dentro da EC2](imagens/imagem%20%2818%29.png)
*Figura: `cloud-init status` e os logs do bootstrap dentro da EC2.*

## 7. Confirmar a aplicação

Dentro da EC2:

```bash
curl -s http://127.0.0.1:8000/api/status | python3 -m json.tool | head -20
curl -si http://127.0.0.1/api/status | head -5
```

Da sua máquina:

```powershell
Invoke-RestMethod "$(terraform output -raw app_url)/api/status" | ConvertTo-Json -Depth 4
```

Procure `instance.instance_id` igual ao output `instance_id`.

Acesse pelo navegador:

```powershell
Start-Process (terraform output -raw app_url)
```

O painel mostra instância, sistema e recursos, e atualiza a cada 5 segundos.

![Chamada à API de status dentro da EC2](imagens/imagem%20%2819%29.png)
*Figura: `curl` em `127.0.0.1:8000/api/status` dentro da EC2.*

![JSON da API de status no navegador](imagens/imagem%20%285%29.png)
*Figura: resposta JSON de `/api/status` no navegador.*

![EC2 Server Dashboard no navegador](imagens/imagem%20%286%29.png)
*Figura: EC2 Server Dashboard servido pelo Nginx, com a API Python atrás do proxy.*

### Teste de reinicialização

```powershell
aws ec2 reboot-instances --instance-ids $(terraform output -raw instance_id)
```

Após cerca de um minuto, a mesma URL volta a responder: o `systemd` reiniciou `dashboard` e `nginx`. O IP público é mantido em um reboot (muda apenas em parada e início ou substituição).

## 8. Verificar os recursos criados

```powershell
terraform state list
terraform state show aws_instance.app

aws ec2 describe-security-group-rules --filters Name=group-id,Values=$(terraform output -raw security_group_id)
aws ec2 describe-volumes --filters Name=attachment.instance-id,Values=$(terraform output -raw instance_id) `
  --query "Volumes[].[VolumeType,Size,Encrypted]"
```

Confirme que não há regra de entrada para a porta 22.

![terraform state list](imagens/imagem%20%2820%29.png)
*Figura: `terraform state list` com os recursos gerenciados e os data sources.*

![terraform state show aws_instance.app](imagens/imagem%20%2821%29.png)
*Figura: `terraform state show aws_instance.app` com os atributos computados.*

![Regras do Security Group e volume EBS](imagens/imagem%20%2822%29.png)
*Figura: regras do Security Group (sem porta 22) e volume `gp3` criptografado.*

## 9. Atualizar o código Terraform

1. Edite o `.tf`, o `terraform.tfvars` ou um arquivo de `application/`.
2. `terraform fmt` e `terraform validate`.
3. `terraform plan` e interprete.
4. `terraform apply`.

### Interpretar o plan

| Símbolo | Significado | Exemplo neste módulo |
|---|---|---|
| `+` | criar | primeira execução |
| `~` | alterar no lugar | `instance_type` de `t3.micro` para `t3.small`; tags |
| `-/+` | substituir | mudar qualquer arquivo de `application/` (User Data); trocar `subnet_id` |
| `-` | destruir | remover `enable_ssm` (role e profile) |

Em `-/+`, procure o comentário `# forces replacement` ao lado do argumento responsável.

### Experimento 1: alteração no lugar

```hcl
instance_type = "t3.small"
```

O plan mostra `~ aws_instance.app` com `instance_type`. O IP público muda ao parar e iniciar? Compare `terraform output public_ip` antes e depois.

![Plan com alteração no lugar](imagens/imagem%20%283%29.png)
*Figura: `terraform plan` mostrando `~ update in-place` ao mudar `instance_type`.*

![Apply da alteração no lugar](imagens/imagem%20%284%29.png)
*Figura: `terraform apply` aplicando a alteração: `0 added, 1 changed, 0 destroyed`.*

### Experimento 2: substituição

Edite o título em `application/frontend/index.html`, rode `plan` e leia `user_data # forces replacement`. Aplique e observe que `instance_id` e `public_ip` mudam.

![Plan com substituição da instância](imagens/imagem%20%287%29.png)
*Figura: `terraform plan` com `-/+` e `forces replacement` no `user_data`.*

![Apply destruindo e recriando a instância](imagens/imagem%20%289%29.png)
*Figura: `terraform apply` destruindo e recriando a instância.*

![Dashboard após a substituição, primeiro acesso](imagens/imagem%20%2810%29.png)
*Figura: dashboard com o novo título logo após a substituição.*

![Dashboard após a substituição, segundo acesso](imagens/imagem%20%2811%29.png)
*Figura: o painel se atualiza sozinho a cada 5 segundos.*

### Experimento 3: validação

```hcl
instance_type = "t4g.micro"   # arm64
architecture  = "x86_64"
```

O `plan` falha na `precondition` com a mensagem sobre a arquitetura.

![Plan falhando na precondition](imagens/imagem%20%2812%29.png)
*Figura: `terraform plan` interrompido pela `precondition` por causa da arquitetura incompatível.*

## 10. Problemas comuns

| Sintoma | Causa provável | Ação |
|---|---|---|
| `plan` diz que a subnet não é pública | Route table sem rota para IGW | Escolha outra subnet ou use `create_lab_network = true` |
| `Nenhuma VPC encontrada` | Não há VPC padrão | Informe `vpc_id` ou crie a rede do laboratório |
| `curl` sem resposta nos primeiros minutos | Bootstrap em andamento | Aguarde e consulte `/var/log/dashboard-bootstrap.log` |
| Timeout mesmo depois | `allowed_http_cidr` não inclui seu IP | Ajuste o CIDR |
| SSM `PingStatus` vazio | Sem rota/saída 443 ou sem role | Revise a seção 2.2 e `enable_ssm` |
| Erro de capacidade para o tipo | Tipo indisponível na AZ | Troque `instance_type` ou `subnet_id` |
| `UnauthorizedOperation` | Permissão insuficiente | Revise as permissões do perfil |

Para remover tudo ao final, siga o [DESTRUIR.md](DESTRUIR.md).
