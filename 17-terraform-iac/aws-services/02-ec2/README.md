# EC2 — Elastic Compute Cloud

**Saswata Das — 24BCS10248** · Session 18, Task 2.02

## What EC2 is

EC2 is resizable virtual machines in AWS. You choose an operating system image, a size, a
network, and firewall rules; AWS gives you a running server in about a minute, billed by the
second while it runs.

It is the oldest and lowest-level compute service: you own the OS, the patching and the
scaling. Containers (ECS/EKS) and serverless (Lambda) trade that control for less
operational burden.

## AMI — Amazon Machine Image

The template an instance boots from: operating system, pre-installed software, and
configuration.

| Source | Use |
|---|---|
| AWS-provided | Amazon Linux 2023, Ubuntu, Windows Server |
| Marketplace | vendor appliances |
| **Custom** | your own golden image, built with Packer |

AMIs are **regional** — an AMI in `ap-south-1` must be copied before it can launch in
`us-east-1`. An AMI ID like `ami-0f5ee92e2d63afc18` is meaningless in another region, which
is why Terraform looks it up with a data source rather than hard-coding it:

```hcl
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}
```

## Instance types

Named `family.generation.size` — `t3.micro`, `m6i.large`, `c7g.xlarge`.

| Family | Optimised for | Typical use |
|---|---|---|
| **t** | burstable | dev boxes, low-traffic web servers |
| **m** | balanced | general purpose application servers |
| **c** | compute | batch processing, encoding, game servers |
| **r** / **x** | memory | in-memory caches, large databases |
| **i** / **d** | storage | NoSQL, data warehouses |
| **p** / **g** | GPU | machine learning, rendering |

A trailing **`g`** (`c7g`, `m7g`) means **Graviton** — AWS's own ARM processors, typically
~20% cheaper for the same performance. The catch is that your container images must be built
for `arm64` — exactly the multi-arch problem hit in
[module 15](../../15-cicd-github-actions/#7-three-real-failures-and-the-fixes).

> **The `t` family burst model:** t-instances earn CPU credits while idle and spend them
> under load. Exhaust the credits and you are throttled to the baseline — a classic cause of
> "the server was fine for a week and then got slow".

## Key pairs

An SSH key pair used for login. AWS keeps the **public** key; you keep the private key.

```bash
aws ec2 create-key-pair --key-name my-key \
  --query 'KeyMaterial' --output text > my-key.pem
chmod 400 my-key.pem
ssh -i my-key.pem ec2-user@<public-ip>
```

> **AWS cannot recover a lost private key.** If you lose it, you must detach the root volume
> and attach it to another instance to get your data back.
>
> Better: skip SSH entirely and use **AWS Systems Manager Session Manager**. It needs no key
> pair, no open port 22, and no public IP — and every session is logged to CloudTrail.

## Security Groups

A **stateful** virtual firewall attached to an instance's network interface.

| Property | Behaviour |
|---|---|
| Default inbound | **deny all** |
| Default outbound | **allow all** |
| Rules | **allow only** — you cannot write a deny rule |
| State | **stateful** — a reply to an allowed inbound request is automatically allowed out |
| Source | a CIDR block, **or another security group** |

Referencing another security group as the source is the idiomatic pattern:

```
web-sg    inbound 443 from 0.0.0.0/0
app-sg    inbound 8080 from web-sg      ← not an IP range
db-sg     inbound 5432 from app-sg
```

The database is then reachable only from the app tier, and the rule keeps working as
instances come and go. This is the same reasoning as Kubernetes label selectors in
[module 10](../../10-k8s-networking-services/).

> **Security group vs NACL:** security groups are stateful, instance-level and allow-only.
> Network ACLs are **stateless**, subnet-level, and support deny rules — so with a NACL you
> must open the ephemeral port range for return traffic too.

## EBS — Elastic Block Store

Network-attached block storage: a virtual disk.

| Type | Use |
|---|---|
| **gp3** | the sensible default — IOPS and throughput configured independently of size |
| gp2 | older generation; IOPS scaled with size |
| io1/io2 | provisioned IOPS for demanding databases |
| st1/sc1 | throughput-optimised HDD, for logs and big sequential reads |

Key properties: EBS volumes live in **one availability zone**, persist independently of the
instance, can be snapshotted to S3, and are encrypted with KMS when you ask.

> **The classic data-loss mistake:** the root volume defaults to `DeleteOnTermination =
> true`. Terminate the instance and the disk goes with it.
>
> **Instance store** (`i3`, `d3` families) is physically attached NVMe — very fast, and
> **wiped when the instance stops**. Never put anything you need on it.

## Public vs private IP

| | Private IP | Public IP | Elastic IP |
|---|---|---|---|
| Scope | inside the VPC | internet-routable | internet-routable |
| Persistence | fixed for the instance's life | **changes on stop/start** | **static**, you own it |
| Cost | free | free while attached | charged when *not* attached |

> **The public IP changes when you stop and start an instance** (though not on reboot). An
> instance behind DNS therefore needs an Elastic IP, or better, a load balancer.
>
> Note the instance never *sees* its public IP: its OS is configured with the private
> address, and the Internet Gateway does the one-to-one NAT. `ip addr` inside the box shows
> only the private IP — the same confusion as pod IPs versus Service IPs in Kubernetes.

## Instance lifecycle

```
            launch
              │
              ▼
  pending ──▶ running ──┬──▶ stopping ──▶ stopped ──▶ (start again)
                        │                     │
                        │                     ▼
                        └──▶ shutting-down ──▶ terminated   (gone forever)
```

| Action | RAM | Root volume | Public IP | Billing |
|---|---|---|---|---|
| **Reboot** | preserved | preserved | **kept** | continues |
| **Stop** | lost | preserved | **released** | compute stops; EBS still billed |
| **Hibernate** | **written to EBS** | preserved | released | compute stops |
| **Terminate** | lost | **deleted** by default | released | everything stops |

## Pricing models

| Model | Discount | Use |
|---|---|---|
| On-demand | — | spiky or unknown workloads |
| **Spot** | up to 90% | fault-tolerant batch, CI runners — **can be reclaimed with 2 minutes' notice** |
| Savings Plans / Reserved | up to 72% | steady baseline load, 1 or 3 year commitment |
| Dedicated Host | premium | licensing or compliance requiring physical isolation |

## Common use cases

- Web and application servers behind an Application Load Balancer
- Self-managed databases where RDS doesn't fit
- Kubernetes worker nodes (EKS node groups are EC2 under the hood)
- Batch and CI workers on Spot
- Lift-and-shift of on-premises VMs

## Hands-on commands

```bash
aws ec2 describe-instances \
  --query 'Reservations[].Instances[].{ID:InstanceId,Type:InstanceType,State:State.Name}' \
  --output table

aws ec2 run-instances --image-id ami-xxx --instance-type t3.micro \
  --key-name my-key --security-group-ids sg-xxx --subnet-id subnet-xxx

aws ec2 stop-instances      --instance-ids i-xxx
aws ec2 terminate-instances --instance-ids i-xxx
aws ec2 describe-instance-types --instance-types t3.micro \
  --query 'InstanceTypes[].{vCPU:VCpuInfo.DefaultVCpus,MemGiB:MemoryInfo.SizeInMiB}'
```

A working Terraform EC2 instance — with a security group, an IAM instance profile and a
VPC — is in [module 18](../../18-cloud-terraform/).
