# Alfrad_Assessment_Nomad-

Usage & Deployment Instructions
Copy above contents to main.tf in a new folder.

Create a file terraform.tfvars:

text
ami_id = "ami-xxxxxx"
key_name = "your-key"
allowed_cidr = "YOUR_IP/32"
Replace with your Ubuntu AMI, SSH key, and public IP/CIDR.

Initialize and apply:

text
terraform init
terraform apply -var-file="terraform.tfvars"
SSH into server node (output.server_ips), port-forward 4646, and access Nomad UI at http://localhost:4646.

The file hello-world.nomad will be created automatically; use nomad job run hello-world.nomad on the server.
