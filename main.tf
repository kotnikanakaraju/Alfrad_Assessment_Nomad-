terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.0.0"
    }
  }
  required_version = ">= 1.3.0"
}

provider "aws" {
  region = var.aws_region
}

# Variables
variable "aws_region" { default = "us-east-1" }
variable "server_count" { default = 1 }
variable "client_count" { default = 1 }
variable "ami_id" { description = "Ubuntu AMI ID (e.g., Ubuntu 22.04 LTS HVM AMI for us-east-1)" }
variable "instance_type" { default = "t3.medium" }
variable "key_name" { description = "EC2 key pair name for SSH access" }
variable "allowed_cidr" { default = "YOUR_IP/32" }

# VPC and networking
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  tags = { Name = "NomadVPC" }
}

resource "aws_subnet" "main" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  map_public_ip_on_launch = true
  tags = { Name = "NomadSubnet" }
}

resource "aws_security_group" "nomad" {
  name        = "nomad-sg"
  description = "Allow Nomad, SSH and metrics"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 4646
    to_port     = 4648
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }
  ingress {
    from_port   = 9100
    to_port     = 9100
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_iam_role" "nomad" {
  name = "nomad-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_instance_profile" "nomad" {
  name = "nomad-profile"
  role = aws_iam_role.nomad.name
}

locals {
  nomad_server_userdata = <<-EOF
    #!/bin/bash
    set -e
    apt-get update && apt-get install -y unzip curl jq docker.io
    curl -Lo /usr/local/bin/nomad https://releases.hashicorp.com/nomad/1.7.4/nomad_1.7.4_linux_amd64.zip
    unzip /usr/local/bin/nomad -d /usr/local/bin/
    chmod +x /usr/local/bin/nomad
    mkdir -p /etc/nomad.d /opt/nomad
    echo 'server = true
    bootstrap_expect = 1
    data_dir  = "/opt/nomad"
    bind_addr = "0.0.0.0"
    ui = true
    advertise { http = "0.0.0.0" rpc = "0.0.0.0" serf = "0.0.0.0" }
    ' > /etc/nomad.d/server.hcl
    echo '[Unit]
    Description=Nomad
    [Service]
    ExecStart=/usr/local/bin/nomad agent -config=/etc/nomad.d/
    Restart=on-failure
    [Install]
    WantedBy=multi-user.target
    ' > /etc/systemd/system/nomad.service
    systemctl enable nomad
    systemctl start nomad

    # Observability: Node Exporter
    useradd --no-create-home --shell /bin/false node_exporter
    wget https://github.com/prometheus/node_exporter/releases/download/v1.8.0/node_exporter-1.8.0.linux-amd64.tar.gz
    tar xvf node_exporter-1.8.0.linux-amd64.tar.gz
    cp node_exporter-1.8.0.linux-amd64/node_exporter /usr/local/bin/
    rm -rf node_exporter-1.8.0.linux-amd64*
    cat <<EOE > /etc/systemd/system/node_exporter.service
    [Unit]
    Description=Node Exporter
    After=network.target
    [Service]
    User=node_exporter
    Group=node_exporter
    Type=simple
    ExecStart=/usr/local/bin/node_exporter
    [Install]
    WantedBy=default.target
    EOE
    systemctl daemon-reload
    systemctl enable node_exporter
    systemctl start node_exporter
  EOF

  nomad_client_userdata = <<-EOF
    #!/bin/bash
    set -e
    apt-get update && apt-get install -y unzip curl jq docker.io
    curl -Lo /usr/local/bin/nomad https://releases.hashicorp.com/nomad/1.7.4/nomad_1.7.4_linux_amd64.zip
    unzip /usr/local/bin/nomad -d /usr/local/bin/
    chmod +x /usr/local/bin/nomad
    mkdir -p /etc/nomad.d /opt/nomad
    echo 'server = false
    data_dir  = "/opt/nomad"
    bind_addr = "0.0.0.0"
    advertise { http = "0.0.0.0" rpc = "0.0.0.0" serf = "0.0.0.0" }
    ' > /etc/nomad.d/client.hcl
    echo '[Unit]
    Description=Nomad
    [Service]
    ExecStart=/usr/local/bin/nomad agent -config=/etc/nomad.d/
    Restart=on-failure
    [Install]
    WantedBy=multi-user.target
    ' > /etc/systemd/system/nomad.service
    systemctl enable nomad
    systemctl start nomad

    # Observability: Node Exporter
    useradd --no-create-home --shell /bin/false node_exporter
    wget https://github.com/prometheus/node_exporter/releases/download/v1.8.0/node_exporter-1.8.0.linux-amd64.tar.gz
    tar xvf node_exporter-1.8.0.linux-amd64.tar.gz
    cp node_exporter-1.8.0.linux-amd64/node_exporter /usr/local/bin/
    rm -rf node_exporter-1.8.0.linux-amd64*
    cat <<EOE > /etc/systemd/system/node_exporter.service
    [Unit]
    Description=Node Exporter
    After=network.target
    [Service]
    User=node_exporter
    Group=node_exporter
    Type=simple
    ExecStart=/usr/local/bin/node_exporter
    [Install]
    WantedBy=default.target
    EOE
    systemctl daemon-reload
    systemctl enable node_exporter
    systemctl start node_exporter
  EOF
}

resource "aws_instance" "nomad_server" {
  count                  = var.server_count
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.main.id
  vpc_security_group_ids = [aws_security_group.nomad.id]
  iam_instance_profile   = aws_iam_instance_profile.nomad.name
  key_name               = var.key_name
  user_data              = local.nomad_server_userdata

  tags = {
    Name = "nomad-server-${count.index + 1}"
  }
}

resource "aws_instance" "nomad_client" {
  count                  = var.client_count
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.main.id
  vpc_security_group_ids = [aws_security_group.nomad.id]
  iam_instance_profile   = aws_iam_instance_profile.nomad.name
  key_name               = var.key_name
  user_data              = local.nomad_client_userdata

  tags = {
    Name = "nomad-client-${count.index + 1}"
  }
}

# Outputs
output "server_ips" {
  value = aws_instance.nomad_server[*].public_ip
}

output "client_ips" {
  value = aws_instance.nomad_client[*].public_ip
}

output "ui_access_info" {
  value = "SSH to server node and port-forward 4646 to access Nomad UI: ssh -L 4646:localhost:4646 ubuntu@IP"
}

output "observability_exporter_info" {
  value = "Prometheus Node Exporter listens on :9100 on all nodes"
}

# Create hello-world Nomad job file locally
resource "local_file" "hello_world_nomad" {
  filename = "${path.module}/hello-world.nomad"
  content  = <<-EOC
    job "hello-world" {
      datacenters = ["dc1"]
      group "example" {
        network {
          port "http" {}
        }
        task "server" {
          driver = "docker"
          config {
            image = "hashicorp/http-echo"
            args  = [
              "-text=Hello from Nomad!"
            ]
            ports = ["http"]
          }
          resources {
            cpu    = 100
            memory = 128
          }
        }
      }
    }
  EOC
}
