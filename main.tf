#test
provider "aws" {
  region = "us-east-1"
}

resource "aws_default_vpc" "default_vpc" {
  enable_dns_hostnames = true

  tags = {
    Name = "default_vpc"
  }
}

output "vpc_id" {
  description = "Output the ID of the default_vpc"
  value       = [aws_default_vpc.default_vpc.id]
}

output "cidr_block" {
  description = "Output the cidr_block of default_vpc"
  value       = "172.31.0.0/24"
}

resource "aws_subnet" "public_subnet" {
  vpc_id            = aws_default_vpc.default_vpc.id
  cidr_block        = "172.31.1.0/24"
  availability_zone = "us-east-1a"
}
resource "aws_security_group" "jenkins_sg" {
  name        = "allow 80, 22 & 8080"
  vpc_id      = aws_default_vpc.default_vpc.id
  description = "Web Traffic"
  ingress {
    description = "Allow Port 22"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["172.31.1.0/24"]
  }
  ingress {
    description = "Allow Port 80"
    from_port   = 80
    to_port     = 80
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

resource "aws_instance" "jenkins_web" {
  ami                         = "ami-0bef6cc322bfff646"
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.public_subnet.id
  associate_public_ip_address = true
  key_name                    = "athena-cloud-key"
  user_data                   = <<-EOF
  #!/bin/bash
  sudo apt update -y
  sudo apt install openjdk-11-jdk -y
  curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io.key | sudo tee /usr/share/keyrings/jenkins-keyring.asc > /dev/null
  echo deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/ | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null
  sudo apt-get update
  sudo apt-get install jenkins -y
  sudo systemctl enable jenkins
  sudo systemctl start jenkins
  EOF
}

resource "aws_s3_bucket" "jenkinsbucket" {
  bucket = "jenkins-bucket-for-artifacts-acha053123"

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
 