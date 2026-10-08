variable "aws_region" {
  description = "Region to deploy into."
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Prefix for every resource name."
  type        = string
  default     = "clinicflow"
}

variable "owner_tag" {
  description = "Owner tag applied to every resource, used for cost attribution and cleanup verification."
  type        = string
  default     = "24BCS10248"
}

variable "vpc_cidr" {
  description = "CIDR for the cluster VPC."
  type        = string
  default     = "10.40.0.0/16"
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS control plane."
  type        = string
  default     = "1.31"
}

variable "node_instance_type" {
  description = "Instance type for the managed node group."
  type        = string
  # t3.medium, not t3.small: the kubelet reserves part of each node, and the
  # per-node POD LIMIT on EKS is driven by ENI capacity -- t3.small allows only
  # 11 pods, which CoreDNS, kube-proxy, the VPC CNI, the ingress controller and
  # Prometheus consume almost entirely before the application is scheduled.
  default = "t3.medium"
}

variable "node_desired_size" {
  description = "Number of worker nodes."
  type        = number
  default     = 2
}

variable "node_min_size" {
  type    = number
  default = 2
}

variable "node_max_size" {
  type    = number
  default = 4
}

variable "single_nat_gateway" {
  description = <<-EOT
    Use one NAT gateway for all private subnets instead of one per AZ.
    true  - cheaper (~$0.045/hr instead of ~$0.09/hr), single point of failure.
    false - production shape: an AZ outage cannot take egress with it.
    Set true for a short-lived demo cluster, which is what this is.
  EOT
  type        = bool
  default     = true
}
