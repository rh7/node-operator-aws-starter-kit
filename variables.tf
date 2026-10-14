variable "region" {
  type        = string
  description = "AWS region (must be eu-central-1 to match the idOS Transit Gateway)"
}

variable "name" {
  type        = string
  default     = "Example"
  description = "Prefix for resource names"
}

# --- Values you receive from idOS after TGW approval ---

variable "transit_gateway_id" {
  type        = string
  description = "Transit Gateway ID (provided by idOS after your account is approved)"
}

variable "tgw_ram_share_arn" {
  type        = string
  description = "RAM resource share ARN (provided by idOS after your account is approved)"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for your VPC (assigned by idOS, e.g. 10.1.0.0/16, 10.4.0.0/16)"
}

variable "ssh_keypair_pub_path" {
  type        = string
  default     = "id_example.pub"
  description = "Path to the public key file for SSH access to the instance"
}

variable "environment" {
  type        = string
  default     = "partner"
  description = "ENVIRONMENT value in idos-kgw's .env; names the CloudWatch log group /ec2/<environment>-idos-kwil-node/containers"
}

variable "log_retention_days" {
  type        = number
  default     = 30
  description = "Retention of the node's CloudWatch container logs, in days"
}
