# EKS needs two separate roles: one the CONTROL PLANE assumes to manage AWS on
# the cluster's behalf, and one the WORKER NODES assume. They are not
# interchangeable -- the trust policies name different services.

data "aws_iam_policy_document" "cluster_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name               = "${var.project_name}-eks-cluster"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume.json
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# --- node role ---------------------------------------------------------------
data "aws_iam_policy_document" "node_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = "${var.project_name}-eks-node"
  assume_role_policy = data.aws_iam_policy_document.node_assume.json
}

# All four are required, and each failure mode is different:
#   WorkerNodePolicy  - the node cannot register with the cluster
#   CNI_Policy        - the node joins but pods get no IP address
#   ECR ReadOnly      - pods cannot pull images from ECR
#   EBS CSI           - PersistentVolumeClaims stay Pending forever
resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy",
  ])
  role       = aws_iam_role.node.name
  policy_arn = each.value
}

# --- EBS CSI driver identity ---------------------------------------------------
#
# The controller needs AWS credentials of its own. Attaching
# AmazonEBSCSIDriverPolicy to the NODE role is not enough: the controller pod
# reaches for the instance metadata service, and EKS restricts the IMDS hop
# limit so a pod cannot reach it. The symptom is a CrashLoopBackOff where five
# of the six containers die with:
#
#   Failed health check (verify network connection and IAM credentials):
#   dry-run EC2 API call failed: ... no EC2 IMDS role found,
#   ec2imds: GetMetadata, context deadline exceeded
#
# and the only visible consequence is that every PersistentVolumeClaim stays
# Pending with no error on the PVC itself.
#
# EKS Pod Identity gives the service account its own role directly, with no OIDC
# provider to set up and no reliance on instance metadata.
data "aws_iam_policy_document" "pod_identity_assume" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ebs_csi" {
  name               = "${var.project_name}-ebs-csi"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume.json
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_eks_pod_identity_association" "ebs_csi" {
  cluster_name    = aws_eks_cluster.main.name
  namespace       = "kube-system"
  service_account = "ebs-csi-controller-sa"
  role_arn        = aws_iam_role.ebs_csi.arn
  depends_on      = [aws_eks_addon.pod_identity]
}
