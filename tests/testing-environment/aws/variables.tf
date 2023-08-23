variable "aws_region" {
    type = string
    default = "us-west-2" 
}

variable "aws_access_key" {
    type = string
    default = "ACCESS KEY NOT SET" 
}

variable "aws_secret_key" {
    type = string
    default = "SECRET KEY NOT SET" 
}

variable "k8s_instance_type" {
    type = string
    default = "t3.micro"
  
}