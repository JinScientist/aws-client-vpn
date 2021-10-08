terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.27"
    }
  }

  required_version = ">= 0.14.9"
}

provider "aws" {
  profile = "default"
  region  = "eu-west-1"
}

variable "public_key_path" {
  description = "Public key path"
  #default = "~/.ssh/id_rsa.pub"
  default = "./id_rsa_mac.pub"
}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}



resource "aws_vpc" "grafana_vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "tf-example"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.grafana_vpc.id

  tags = {
    Name = "main"
  }
}



resource "aws_subnet" "my_subnet" {
  vpc_id            = aws_vpc.grafana_vpc.id
  cidr_block        = "10.0.0.0/21"
  availability_zone = "eu-west-1a"
  map_public_ip_on_launch="true"
  tags = {
    Name = "tf-example"
  }
}

resource "aws_route_table" "rtb_public" {
  vpc_id =aws_vpc.grafana_vpc.id
route {
      cidr_block = "0.0.0.0/0"
      gateway_id = aws_internet_gateway.igw.id
  }
tags ={
    Name = "tf-example"
  }
}

resource "aws_route_table_association" "rta_subnet_public" {
  subnet_id      = "${aws_subnet.my_subnet.id}"
  route_table_id = "${aws_route_table.rtb_public.id}"
}

resource "aws_security_group" "sg_22" {
  name = "sg_22"
  vpc_id = "${aws_vpc.grafana_vpc.id}"
  
  ingress {
  
      description      = "ssh"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = ["10.0.0.0/16"]
  }
     ingress {
      description      = "grafana_ui"
      from_port        = 3000
      to_port          = 3000
      protocol         = "tcp"
      cidr_blocks      = ["10.0.0.0/16"]
    }
  
  
 egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags={
    Name = "tf-example"
  }
}

resource "aws_key_pair" "ec2key" {
  key_name = "testkey"
  public_key = "${file(var.public_key_path)}"
}

resource "aws_network_interface" "foo" {
  subnet_id   = aws_subnet.my_subnet.id
  private_ips = ["10.0.3.100"]
  security_groups = ["${aws_security_group.sg_22.id}"]
  
  tags = {
    Name = "primary_network_interface"
  }
}

resource "aws_instance" "foo" {
  ami           = data.aws_ami.ubuntu.id # us-west-2
  instance_type = "t2.micro"
  key_name      = "${aws_key_pair.ec2key.key_name}"

  
  network_interface {
    network_interface_id = aws_network_interface.foo.id
    device_index         = 0
  }

  credit_specification {
    cpu_credits = "unlimited"
  }

}

resource "aws_ec2_client_vpn_endpoint" "example" {

  client_cidr_block      = "172.31.0.0/22"
  server_certificate_arn = "arn:aws:acm:eu-west-1:476147591178:certificate/0e14b311-c90f-43c3-ac49-8ffba45ebb66"


  authentication_options {
    root_certificate_chain_arn = "arn:aws:acm:eu-west-1:476147591178:certificate/0e14b311-c90f-43c3-ac49-8ffba45ebb66"
    type                       = "certificate-authentication"
  }

  connection_log_options {
    enabled = false
  }
}

resource "aws_ec2_client_vpn_network_association" "example" {
  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.example.id
  subnet_id              = aws_subnet.my_subnet.id
}


resource "aws_ec2_client_vpn_authorization_rule" "example" {
  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.example.id
  target_network_cidr    = aws_subnet.my_subnet.cidr_block
  authorize_all_groups   = true
}

resource "aws_ec2_client_vpn_authorization_rule" "internet" {
  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.example.id
  target_network_cidr    = "0.0.0.0/0"
  authorize_all_groups   = true
}


resource "aws_ec2_client_vpn_route" "example" {
  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.example.id
  destination_cidr_block = "0.0.0.0/0"
  target_vpc_subnet_id   = aws_ec2_client_vpn_network_association.example.subnet_id
}