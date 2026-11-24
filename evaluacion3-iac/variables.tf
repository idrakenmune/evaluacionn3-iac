variable "region" {
  description = "Región de AWS"
  type        = string
  default     = "us-east-1"
}

variable "proyecto" {
  description = "Nombre del proyecto"
  type        = string
}

variable "aplicacion" {
  description = "Nombre de la aplicación"
  type        = string
}

variable "responsable" {
  description = "Responsable de la infraestructura"
  type        = string
}

variable "ambiente" {
  description = "Ambiente de despliegue (dev o prod)"
  type        = string
  validation {
    condition     = contains(["dev", "prod"], var.ambiente)
    error_message = "El ambiente debe ser 'dev' o 'prod'."
  }
}

variable "vpc_cidr" {
  description = "CIDR de la VPC"
  type        = string
}

variable "subredes" {
  description = "Mapa de las 4 subredes (2 públicas y 2 privadas)"
  type = map(object({
    cidr = string
    az   = string
    tipo = string # "publica" o "privada"
  }))
}

variable "servidores" {
  description = "Mapa de servidores de la Biblioteca Digital"
  type = map(object({
    tipo_instancia = string
    disco          = number
    subred         = string
  }))
}

variable "key_name" {
  description = "Nombre del Key Pair en AWS para acceso SSH"
  type        = string
}

variable "db_username" {
  description = "Usuario administrador de la RDS MySQL"
  type        = string
}

variable "db_password" {
  description = "Contraseña de la RDS MySQL"
  type        = string
  sensitive   = true
}

variable "s3_sufijo_unico" {
  description = "Sufijo único para evitar conflictos de nombre global en S3"
  type        = string
}