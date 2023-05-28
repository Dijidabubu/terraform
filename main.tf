#ConfiguretheAWSProvider
provider "aws" {
  region = "us-east-1"
}

#Retrieve the list of AZs in the current AWS region
data "aws_availability_zones" "available" {}
data "aws_region" "current" {}

module "eks-jx" {
  source  = "jenkins-x/eks-jx/aws"
  version = "1.21.2"
  vault_user = "Alexis"  # insert the 2 required variables here
}

locals {
  team = "api_mgmt_dev"
  application = "corp_api"
  server_name = "ec2-${var.environment}-api-${var.variables_sub_az}"
}

#Define the VPC
resource "aws_vpc" "vpc" {
  cidr_block = var.vpc_cidr

  tags = {
    Name        = "jenkins_vpc"
    Environment = "demo_environment"
    Terraform   = "true"
    Region      = data.aws_region.current.name

  }
}

#Deploy the public subnets
resource "aws_subnet" "public_subnets" {
  for_each                = var.public_subnets
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, each.value + 100)
  availability_zone       = tolist(data.aws_availability_zones.available.names)[each.value]
  map_public_ip_on_launch = true
  tags = {
    Name      = each.key
    Terraform = "true"
  }
}

#Create routetables for public and private subnets
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.internet_gateway.id
    #nat_gateway_id=aws_nat_gateway.nat_gateway.id
  }
  tags = {
    Name      = "jenkins_public_rtb"
    Terraform = "true"
  }
}

#Create routetable associations
resource "aws_route_table_association" "public" {
  depends_on     = [aws_subnet.public_subnets]
  route_table_id = aws_route_table.public_route_table.id
  for_each       = aws_subnet.public_subnets
  subnet_id      = each.value.id
}

#Create InternetGateway
resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "jenkins_igw"
  }
}

# Terraform Data Block - Lookup Ubuntu 16.04
data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-xenial-16.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  owners = ["099720109477"]
}

#Terraform Resource Block-To Build EC2 instance in Public Subnet
resource "aws_instance" "web_server" {                            # BLOCK
  ami           = data.aws_ami.ubuntu.id                          # Argument with data expression
  instance_type = "t2.micro"                                      # Argument
  subnet_id     = aws_subnet.public_subnets["public_subnet_1"].id # Argument with value as expression
  tags = {
    Name = local.server_name
    Owner = local.team
    App = local.application
  }
}

resource "aws_s3_bucket" "my-new-S3-bucket" {
  bucket = "jenkins-tf-bucket-${random_id.randomness.hex}"

  tags = {
    Name    = "Jenkins S3 Bucket"
    Purpose = "Week 20 project"
  }
}

resource "aws_s3_bucket_acl" "my_new_bucket_acl" {
  bucket = aws_s3_bucket.my-new-S3-bucket.id
  acl    = "private"
}

resource "aws_security_group" "jenkins-security-group" {
  name        = "jenkins_server_inbound"
  description = "Allow inbound traffic on 8080"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    description = "Allow 8080 from the Internet"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "web_server_inbound"
    Purpose = "Intro to Resource Blocks Lab"
  }
}

resource "random_id" "randomness" {
  byte_length = 16
}

resource "aws_subnet" "variables-subnet" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = var.variables_sub_cidr
  availability_zone       = var.variables_sub_az
  map_public_ip_on_launch = var.variables_sub_auto_ip

  tags = {
    Name      = "sub-variables-${var.variables_sub_az}"
    Terraform = "true"
  }
}

