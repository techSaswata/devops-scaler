resource "aws_eks_cluster" "main" {
  name     = var.project_name
  role_arn = aws_iam_role.cluster.arn
  version  = var.cluster_version

  vpc_config {
    # Nodes live in the private subnets; the public ones carry the load
    # balancers. Both are given to EKS so it can place cross-AZ ENIs.
    subnet_ids              = concat(aws_subnet.private[*].id, aws_subnet.public[*].id)
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  # API_AND_CONFIG_MAP keeps the modern EKS access-entry API available while
  # the creating principal still gets cluster-admin, so `aws eks
  # update-kubeconfig` works immediately without an aws-auth ConfigMap dance.
  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator"]

  # Without this the cluster can be created before its IAM permissions exist,
  # and it fails in a way that needs a full destroy to recover from.
  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy,
    aws_cloudwatch_log_group.eks,
  ]

  tags = { Name = var.project_name }
}

# EKS writes control-plane logs to a log group whose name it chooses. Creating
# it here means it carries our tags and, more importantly, that `terraform
# destroy` removes it -- otherwise it is left behind, accruing storage charges
# after everything else is gone.
resource "aws_cloudwatch_log_group" "eks" {
  name              = "/aws/eks/${var.project_name}/cluster"
  retention_in_days = 1
  tags              = { Name = "${var.project_name}-eks-logs" }
}

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.project_name}-ng"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = aws_subnet.private[*].id
  instance_types  = [var.node_instance_type]
  capacity_type   = "ON_DEMAND"
  disk_size       = 20

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  # ALL THREE are required, and the last two were learned the hard way.
  #
  # Terraform infers dependencies from references, and this resource references
  # only the subnets and the role -- not the route tables that give those
  # subnets a way out. So on the first run it launched both nodes into private
  # subnets that still had no route to the NAT gateway. The instances came up,
  # could not reach the EKS API or any registry, never registered, and
  # `kubectl get nodes` returned "No resources found" while the node group sat
  # in CREATING with health.issues empty -- no error anywhere pointing at
  # routing.
  #
  # A private subnet is not usable the moment it exists; it is usable when it
  # has egress. These two depends_on lines say so explicitly.
  depends_on = [
    aws_iam_role_policy_attachment.node,
    aws_nat_gateway.main,
    aws_route_table_association.private,
  ]

  # These tags land on the NODE GROUP, and -- this is the trap -- EKS does NOT
  # propagate them, nor the provider's default_tags, onto the EC2 instances the
  # group launches. The worker nodes come up with no Owner tag at all.
  #
  # That matters for cleanup verification rather than for cost reporting: a
  # teardown check scoped to `tag:Owner` reports "nothing of mine is running"
  # while two t3.medium instances are very much running and billing. This was
  # observed on this cluster, and scripts/09-destroy.sh now verifies by VPC --
  # the boundary Terraform actually owns -- and reports the tag check separately.
  #
  # The alternative fix is a launch template with tag_specifications for
  # "instance" and "volume". It is the better long-term answer; it is noted here
  # rather than applied so that this configuration matches the run the outputs
  # in ../outputs/ were captured from.
  tags = { Name = "${var.project_name}-node" }
}

# --- addons ------------------------------------------------------------------
# The EBS CSI driver is NOT installed by default on EKS 1.23+. Without it a
# PersistentVolumeClaim is accepted by the API server and then sits Pending
# forever with no obvious error, because nothing is listening to provision it.
# Postgres in this chart uses a PVC, so the cluster is useless without this.
resource "aws_eks_addon" "ebs_csi" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "aws-ebs-csi-driver"
  resolve_conflicts_on_create = "OVERWRITE"
  depends_on                  = [aws_eks_node_group.main]
}

resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "coredns"
  resolve_conflicts_on_create = "OVERWRITE"
  # CoreDNS pods cannot schedule until there are nodes, and the addon reports
  # DEGRADED if it is created first.
  depends_on = [aws_eks_node_group.main]
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "kube-proxy"
  resolve_conflicts_on_create = "OVERWRITE"
  depends_on                  = [aws_eks_node_group.main]
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "vpc-cni"
  resolve_conflicts_on_create = "OVERWRITE"
  depends_on                  = [aws_eks_node_group.main]
}

# Pod Identity is the current way to give a pod an IAM role, replacing the older
# IRSA/OIDC dance. Nothing in this chart needs AWS credentials today, but the
# agent is a prerequisite rather than something to retrofit later.
resource "aws_eks_addon" "pod_identity" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "eks-pod-identity-agent"
  resolve_conflicts_on_create = "OVERWRITE"
  depends_on                  = [aws_eks_node_group.main]
}
