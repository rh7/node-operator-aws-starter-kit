output "vpc_id" {
  description = "ID of the VPC attached to the Transit Gateway"
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "CIDR of the VPC"
  value       = aws_vpc.this.cidr_block
}

output "tgw_attachment_id" {
  description = "ID of the Transit Gateway VPC attachment"
  value       = aws_ec2_transit_gateway_vpc_attachment.this.id
}

output "security_group_id" {
  description = "ID of the security group for the node (attach to any additional instances that should talk to idOS network)"
  value       = aws_security_group.this.id
}

output "instance_public_ip" {
  description = "Public IP of the EC2 instance (for SSH)"
  value       = aws_instance.this.public_ip
}

output "instance_private_ip" {
  description = "Private IP of the EC2 instance; provide this to idOS to be included in the load balancer"
  value       = aws_instance.this.private_ip
}

output "log_group_name" {
  description = "CloudWatch log group for the node's containers (matches ENVIRONMENT in idos-kgw's .env)"
  value       = aws_cloudwatch_log_group.node.name
}
