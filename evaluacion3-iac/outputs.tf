output "nlb_dns" {
  description = "DNS público del Network Load Balancer"
  value       = aws_lb.nlb.dns_name
}

output "rds_endpoint" {
  description = "Endpoint privado de la base de datos RDS MySQL"
  value       = aws_db_instance.mysql.endpoint
}

output "s3_bucket_name" {
  description = "Nombre del bucket S3 generado"
  value       = aws_s3_bucket.material.bucket
}