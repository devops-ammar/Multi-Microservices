resource "aws_vpc" "eks_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = { Name = "eks-vpc" }
}
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.eks_vpc.id
  cidr_block              = "10.0.${count.index + 1}.0/24"
  availability_zone       = "us-east-1${count.index == 0 ? "a" : "b"}"
  map_public_ip_on_launch = true
  tags = {
    Name                                = "eks-public-${count.index + 1}"
    "kubernetes.io/role/elb"            = "1"
    "kubernetes.io/cluster/eks-cluster" = "shared"
  }
}

# Private Subnets – for worker nodes (2 AZs for HA)
resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.eks_vpc.id
  cidr_block        = "10.0.${count.index + 10}.0/24"
  availability_zone = "us-east-1${count.index == 0 ? "a" : "b"}"
  tags = {
    Name                                = "eks-private-${count.index + 1}"
    "kubernetes.io/role/internal-elb"   = "1"
    "kubernetes.io/cluster/eks-cluster" = "shared"
  }
}

# Internet Gateway (public subnets)
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.eks_vpc.id
  tags   = { Name = "eks-igw" }
}

# Elastic IP for NAT Gateway
resource "aws_eip" "nat" {
  count  = 2
  domain = "vpc"
  tags   = { Name = "todo-nat-eip-${count.index + 1}" }
}

# NAT Gateway (allows private instances to reach the internet)
resource "aws_nat_gateway" "nat" {
  count         = 2
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id # place in first public subnet
  depends_on    = [aws_internet_gateway.igw]
  tags          = { Name = "eks-nat-${count.index + 1}" }
}

# Route table for public subnets (directly to IGW)
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.eks_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "eks-public-rt" }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Route table for private subnets (via NAT)
resource "aws_route_table" "private" {
  count  = 2
  vpc_id = aws_vpc.eks_vpc.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat[count.index].id
  }
  tags = { Name = "eks-private-rt-${count.index + 1}" }
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# EKS Cluster role
resource "aws_iam_role" "eks_cluster" {
  name = "eks-cluster-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
  tags = { Name = "eks-cluster-role" }
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# Worker Node role
resource "aws_iam_role" "node" {
  name = "eks-node-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
  tags = { Name = "eks-node-role" }
}

# Attach three mandatory node policies using for_each
resource "aws_iam_role_policy_attachment" "node_policies" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy" # for persistent storage like MongoDB or Redis
  ])
  role       = aws_iam_role.node.name
  policy_arn = each.value
}

data "aws_caller_identity" "current" {}

resource "aws_eks_access_entry" "admin" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "admin_policy" {
  cluster_name  = aws_eks_cluster.main.name
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  principal_arn = aws_eks_access_entry.admin.principal_arn
  access_scope { type = "cluster" }
}

resource "aws_eks_cluster" "main" {
  name     = "eks-cluster"
  version  = "1.35"
  role_arn = aws_iam_role.eks_cluster.arn

  access_config {
    authentication_mode = "API" # must grant explicit access via access entries
  }

  vpc_config {
    subnet_ids              = concat(aws_subnet.public[*].id, aws_subnet.private[*].id)
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  depends_on = [aws_iam_role_policy_attachment.eks_cluster_policy]
}

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "main-workers"
  node_role_arn   = aws_iam_role.node.arn

  # place workers in private subnets only
  subnet_ids = aws_subnet.private[*].id

  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 1
  }

  update_config { max_unavailable = 1 }

  labels = { role = "application" }

  instance_types = ["t3.micro"] # Free tier eligible
  # disk_size      = 20

  depends_on = [aws_iam_role_policy_attachment.node_policies]
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["9e99a48a9960b14926bb7f3b02e22da2b0ab7280"] # fixed thumbprint for AWS OIDC
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer
  tags            = { Name = "eks-oidc" }
}

# Unsupported addons (managed by EKS, not Terraform) - can be enabled via AWS Console or CLI after cluster creation
# resource "aws_eks_addon" "vpc_cni" {
#   cluster_name                = aws_eks_cluster.main.name
#   addon_name                  = "vpc-cni"
#   addon_version               = "v1.18.3-eksbuild.2"
#   resolve_conflicts_on_create = "OVERWRITE"
#   resolve_conflicts_on_update = "OVERWRITE"
#   depends_on                  = [aws_eks_node_group.main]
# }

# resource "aws_eks_addon" "coredns" {
#   cluster_name                = aws_eks_cluster.main.name
#   addon_name                  = "coredns"
#   addon_version               = "v1.11.3-eksbuild.1"
#   resolve_conflicts_on_create = "OVERWRITE"
#   resolve_conflicts_on_update = "OVERWRITE"
#   depends_on                  = [aws_eks_node_group.main]
# }

# resource "aws_eks_addon" "kube_proxy" {
#   cluster_name                = aws_eks_cluster.main.name
#   addon_name                  = "kube-proxy"
#   addon_version               = "v1.31.0-eksbuild.2"
#   resolve_conflicts_on_create = "OVERWRITE"
#   resolve_conflicts_on_update = "OVERWRITE"
#   depends_on                  = [aws_eks_node_group.main]
# }

# resource "aws_eks_addon" "ebs_csi" {
#   cluster_name                = aws_eks_cluster.main.name
#   addon_name                  = "aws-ebs-csi-driver"
#   addon_version               = "v1.36.0-eksbuild.1"
#   resolve_conflicts_on_create = "OVERWRITE"
#   resolve_conflicts_on_update = "OVERWRITE"
#   depends_on                  = [aws_eks_node_group.main]
# }
