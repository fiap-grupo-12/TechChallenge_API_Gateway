resource "aws_cognito_user_pool" "lanchonete_user_pool" {
  name = "lanchonete_user_pool"

  # Definir política de senha
  password_policy {
    minimum_length    = 8
    require_uppercase = true
    require_numbers   = true
    require_symbols   = true
  }

  # Desabilitar a verificação de e-mail e telefone
  auto_verified_attributes = [] # Nenhuma verificação automática de email ou telefone

  # Configuração de criação de usuário sem verificação de e-mail
  admin_create_user_config {
    allow_admin_create_user_only = false
  }

  # Email não será obrigatório
  schema {
    attribute_data_type = "String"
    name                = "email"
    required            = false # Email opcional
    mutable             = true
  }

  # O login será feito usando o username, que será preenchido com o CPF
  alias_attributes = []
}

# Função Lambda de autorização usando CPF ou anonimamente
resource "aws_lambda_function" "lambda_authorizer" {
  function_name = "cognito_authorizer3"
  runtime       = "dotnet6"
  role          = aws_iam_role.lambda_role.arn
  handler       = "AuthorizerLambda::AuthorizerLambda.Function::FunctionHandler"
  timeout       = 30 # Tempo em segundos

  # Código da Lambda
  filename = "lambda_authorizer3.zip" # Arquivo zipado do código da Lambda

  # Variáveis de ambiente para a Lambda
  environment {
    variables = {
      USER_POOL_ID = aws_cognito_user_pool.lanchonete_user_pool.id # Passa o User Pool ID para a Lambda
    }
  }

}

# Obter a identidade da conta AWS atual, incluindo o account_id
data "aws_caller_identity" "current" {}

resource "aws_lambda_permission" "api_gateway_invoke_authorizer" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda_authorizer.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${var.region}:${data.aws_caller_identity.current.account_id}:${aws_api_gateway_rest_api.lanchonete_api.id}/authorizers/${aws_api_gateway_authorizer.lambda_authorizer.id}"

  # Adicionar dependência explícita para garantir que o authorizer seja criado antes
  depends_on = [aws_api_gateway_authorizer.lambda_authorizer]
}

resource "aws_iam_role" "lambda_role" {
  name = "lambda_cognito_role"

  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "",
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "lambda.amazonaws.com"
        },
        "Action" : "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_policy" "lambda_policy" {
  name        = "lambda_cognito_policy"
  description = "Policy for Lambda to interact with other AWS services"
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "lambda:InvokeFunction",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "cognito-idp:ListUsers"
        ],
        "Resource" : "*"
      },
      {
        Effect = "Allow",
        Action = [
          "cognito-idp:ListUsers"
        ],
        Resource = aws_cognito_user_pool.lanchonete_user_pool.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_role_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

# Anexar a política à role
resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}