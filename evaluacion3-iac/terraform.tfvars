region          = "us-east-1"
proyecto        = "eduandes"
aplicacion      = "biblioteca"
responsable     = "millaray-silva"
ambiente        = "dev" # Cambiar a "prod" para el plan de producción
vpc_cidr        = "10.0.0.0/16"
key_name        = "vockey" # Cambia esto por el nombre de tu Key Pair en AWS
db_username     = "admin"
s3_sufijo_unico = "2026-milla"

subredes = {
  pub1 = {
    cidr = "10.0.1.0/24"
    az   = "us-east-1a"
    tipo = "publica"
  }
  pub2 = {
    cidr = "10.0.2.0/24"
    az   = "us-east-1b"
    tipo = "publica"
  }
  priv1 = {
    cidr = "10.0.3.0/24"
    az   = "us-east-1a"
    tipo = "privada"
  }
  priv2 = {
    cidr = "10.0.4.0/24"
    az   = "us-east-1b"
    tipo = "privada"
  }
}

servidores = {
  biblioteca-a = {
    tipo_instancia = "t3.medium"
    disco          = 30
    subred         = "pub1"
  }
  biblioteca-b = {
    tipo_instancia = "t3.medium"
    disco          = 30
    subred         = "pub1"
  }
  biblioteca-c = {
    tipo_instancia = "t3.large"
    disco          = 60
    subred         = "pub2"
  }
}