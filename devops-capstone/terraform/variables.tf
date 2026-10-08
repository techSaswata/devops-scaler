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

variable "use_nat_gateway" {
  description = <<-EOT
    true  - worker nodes run in PRIVATE subnets and egress through a NAT
            gateway. This is the production shape and the default: nodes have
            no inbound route from the internet at all.

    false - worker nodes run in PUBLIC subnets with auto-assigned public IPs and
            egress through the internet gateway. No NAT gateway, and therefore
            no Elastic IP.

    This exists because of a real constraint rather than a preference. A NAT
    gateway requires an Elastic IP, and the shared AWS account this was built on
    is already at its EIP quota (8 allocated against a limit of 5, all belonging
    to other projects). `terraform apply` failed with:

      Error: creating EC2 EIP: AddressLimitExceeded:
             The maximum number of addresses has been reached.

    Releasing somebody else's EIP was not an option, so the cluster runs with
    public nodes. The nodes are still protected by their security group -- what
    is lost is the second layer, where an inbound route does not exist in the
    first place. On an account with EIP headroom, leave this true.
  EOT
  type        = bool
  default     = true
}
