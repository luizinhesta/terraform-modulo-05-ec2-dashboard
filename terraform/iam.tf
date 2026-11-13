# -----------------------------------------------------------------------------
# iam.tf - Acesso por Systems Manager (Session Manager), sem SSH
#
# Cadeia: Role (com política de confiança) -> política gerenciada -> Instance Profile
# A EC2 não recebe uma Role diretamente: recebe um Instance Profile que a contém.
# -----------------------------------------------------------------------------

data "aws_partition" "current" {}

# Política de CONFIANÇA: quem pode assumir a role. Aqui, o serviço EC2.
data "aws_iam_policy_document" "ec2_trust" {
  statement {
    sid     = "EC2AssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2" {
  count = var.enable_ssm ? 1 : 0

  name               = "${local.name}-ec2-role-${var.aws_region}"
  description        = "Role da EC2 do dashboard (Session Manager)"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust.json
}

# Política gerenciada pela AWS que permite ao SSM Agent se registrar e abrir sessões.
resource "aws_iam_role_policy_attachment" "ssm_core" {
  count = var.enable_ssm ? 1 : 0

  role       = aws_iam_role.ec2[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2" {
  count = var.enable_ssm ? 1 : 0

  name = "${local.name}-ec2-profile-${var.aws_region}"
  role = aws_iam_role.ec2[0].name
}
