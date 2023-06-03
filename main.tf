#week 20 prjtest
provider "aws" {
  region = "us-east-1"
}

provider "tls" {
}

resource "tls_private_key" "generated" {
  algorithm = "RSA"
}

resource "local_file" "private_key_pem" {
  content  = tls_private_key.generated.private_key_pem
  filename = "week20prj.pem"
}

resource "aws_key_pair" "generated" {
  key_name   = "week20prj"
  public_key = tls_private_key.generated.public_key_openssh

  lifecycle {
    ignore_changes = [key_name]
  }
}

resource "aws_default_vpc" "default_vpc" {
  enable_dns_hostnames = true

  tags = {
    Name      = "default_vpc"
    Terraform = "true"
  }
}

output "vpc_id" {
  description = "Output the ID of the default_vpc"
  value       = [aws_default_vpc.default_vpc.id]
}

resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_default_vpc.default_vpc.id
  cidr_block              = "172.31.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
}
resource "aws_security_group" "jenkins_sg" {
  name        = "allow 22 & 8080"
  vpc_id      = aws_default_vpc.default_vpc.id
  description = "Web Traffic"
  ingress {
    description = "Allow Port 22"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "Allow Port 8080"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    description = "Allow all ip and ports outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "null_resource" "name" {

  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = tls_private_key.generated.private_key_pem
    host        = aws_instance.jenkins_web.public_ip
  }

  provisioner "file" {
    source      = "jenkinsscript.sh"
    destination = "/tmp/jenkinsscript.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo chmod +x /tmp/jenkinsscript.sh",
      "sh /tmp/jenkinsscript.sh",
    ]
  }

  depends_on = [aws_instance.jenkins_web]
}

output "website_url" {
  value = join("", ["http://", aws_instance.jenkins_web.public_dns, ":", "8080"])
}

resource "aws_instance" "jenkins_web" {
  ami                         = "ami-0bef6cc322bfff646"
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.public_subnet.id
  associate_public_ip_address = true
  key_name                    = "week20prj"
  security_groups             = [aws_security_group.jenkins_sg.id]

  connection {
    user        = "ec2-user"
    private_key = tls_private_key.generated.private_key_pem
    host        = self.public_ip
  }

  provisioner "local-exec" {
    command = "chmod 600 ${local_file.private_key_pem.filename}"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo yum update -y",
      "sudo wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo",
      "sudo rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key",
      "sudo yum upgrade",
      "sudo amazon-linux-extras install java-openjdk11 -y",
      "sudo yum install jenkins -y",
      "sudo systemctl daemon-reload",
      "sudo systemctl enable jenkins",
      "sudo systemctl start jenkins",
      "sudo cat /var/lib/jenkins/secrets/initialAdminPassword",
    ]
  }

  tags = {
    Name = "jenkins_web"
  }
  lifecycle {
    ignore_changes = [security_groups]
  }
}

resource "aws_s3_bucket" "jenkinsbucket" {
  bucket = "jenkins-bucket-for-artifacts-acha060123"

  tags = {
    Name        = "Dev bucket"
    Environment = "Dev"
  }
}

resource "aws_s3_bucket_ownership_controls" "jenkinsbucket" {
  bucket = aws_s3_bucket.jenkinsbucket.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "jenkinsbucket" {
  depends_on = [aws_s3_bucket_ownership_controls.jenkinsbucket]

  bucket = aws_s3_bucket.jenkinsbucket.id
  acl    = "private"
}
