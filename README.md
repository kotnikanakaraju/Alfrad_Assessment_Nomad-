# Alfrad_Assessment_Nomad-

Project: Nomad Cluster Terraform (Single File)
1. Prerequisites
Install Terraform (v1.3 or higher) on your local machine.

Have an AWS account and a valid SSH key pair.

Find the current Ubuntu AMI ID for your AWS region (Ubuntu AMI List).

Your public IP address (for allowed_cidr).

2. Prepare Your Configuration
Copy the full code provided into a file named main.tf.

In the same folder, create a terraform.tfvars file and fill it like:


ami_id = "ami-xxxxxxxxxxxxxxxxx"
key_name = "your-key-name"
allowed_cidr = "YOUR_PUBLIC_IP/32"
Replace the placeholder values with your AMI, key, and IP.

3. Deploy the Infrastructure
Open a terminal in your project folder and run:


terraform init
terraform apply -var-file="terraform.tfvars"
Review the proposed resource changes and approve by typing yes.

4. Access Nomad UI
Retrieve the output values for server_ips using:


terraform output server_ips
SSH into the Nomad server:


ssh -i /path/to/your-key.pem ubuntu@<server_ip> 
Enable local port forwarding for Nomad UI:


ssh -L 4646:localhost:4646 -i /path/to/your-key.pem ubuntu@<server_ip>
Open http://localhost:4646 in your browser to access the Nomad UI.

5. Deploy the Sample Application
The job file hello-world.nomad will be created automatically in your folder.

On the Nomad server, run:


nomad job run hello-world.nomad
Verify the job from the UI or using:


nomad job status hello-world
6. Observability
Prometheus Node Exporter is started by default on both the server and client VMs (port 9100).

You can verify its status:


curl http://localhost:9100/metrics
For deeper monitoring, connect Prometheus or other compatible dashboards to Node Exporter.

7. Destroy the Infrastructure
To tear down all deployed resources:


terraform destroy -var-file="terraform.tfvars"

