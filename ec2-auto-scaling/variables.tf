# Tags
variable "project" {
  default = "terraform"
}
# variable "createdby" {}
# General 
variable "aws_region" {
  default = "us-west-2"
}

variable "aws_az_count" {
  default = 2
}


variable "app_from_port" {
  default = 80
}

variable "app_to_port" {
  default = 80
}

variable "app_protocol" {
  default = "tcp"
}


variable "app_health_check_path" {
  default = "/"
}
