terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region     = var.aws_region
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
}

# Create a VPC
resource "aws_vpc" "example" {
  cidr_block = "10.0.0.0/16"
}

data "cloudinit_config" "calico_early" {
  gzip          = false
  base64_encode = true
  part {
    filename     = "cloud-config.yaml"
    content_type = "text/cloud-config"

    content = templatefile("${path.module}/templates/tigera-early-networking.tpl", {
        tor_sw1_asn = 65021,
        tor_sw2_asn = 65031, 
        tor_sw1_octet = "3",
        tor_sw2_octet = "3",
        switch_network_sw1 = "10.10.10",
        switch_network_sw2 = "10.10.20",
        mgmt_network = "10.10.32",
        node_final_octet = 12+count.index
        nodes = range(0, 5)
    })
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}


resource "aws_ec2_host" "k8s_nodes" {
  count             = 5
  ami               = data.aws_ami.ubuntu.id
  instance_type     = var.k8s_instance_type
  availability_zone = "us-west-2a"
  user_data_base64  = cloudinit_config.calico_early.rendered
}
