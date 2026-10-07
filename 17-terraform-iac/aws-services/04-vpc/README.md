# VPC — Virtual Private Cloud

**Saswata Das — 24BCS10248** · Session 18, Task 2.04

## What a VPC is

A VPC is your own logically isolated network inside AWS — your private slice of the cloud,
with your own IP range, subnets, routing and firewalls. Nothing in it is reachable from the
internet unless you explicitly arrange it.

A working Terraform VPC with subnets, routing, a gateway and an EC2 instance is built in
[module 18](../../../18-cloud-terraform/).

## CIDR

A VPC is defined by a CIDR block: `10.0.0.0/16`.

```
10.0.0.0/16   →  10.0.0.0  –  10.0.255.255   65,536 addresses
10.0.1.0/24   →  10.0.1.0  –  10.0.1.255        256 addresses
```

The `/n` is how many **leading bits are the network**; the rest identify hosts. Smaller
number = bigger network.

Rules worth knowing:

- Allowed size is `/16` (65,536) down to `/28` (16).
- **The CIDR cannot be changed after creation** — you can only add secondary blocks. Choose
  with room to grow.
- Use RFC 1918 private space: `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`.
- **AWS reserves 5 addresses in every subnet** — network, VPC router, DNS, future use, and
  broadcast. A `/24` gives you 251 usable, not 256.

> Avoid overlapping ranges with anything you might peer with later — your office network, a
> partner VPC, or another region. Overlapping CIDRs cannot be peered, and re-addressing a
> live VPC is painful.

## Subnets

A subnet is a slice of the VPC CIDR **pinned to one availability zone**.

| | Public subnet | Private subnet |
|---|---|---|
| Route to `0.0.0.0/0` | **Internet Gateway** | **NAT Gateway** (or nothing) |
| Inbound from internet | possible | no |
| Outbound to internet | yes | yes, via NAT |
| Typical contents | load balancers, bastions | app servers, databases |

> **The only thing that makes a subnet "public" is its route table.** There is no checkbox.
> A subnet whose route table sends `0.0.0.0/0` to an Internet Gateway is public; otherwise it
> is private.

Always spread subnets across **at least two AZs** — a subnet lives in exactly one, so a
single-AZ design has a single point of failure.

## Route tables

A set of rules deciding where traffic goes, evaluated **most specific prefix first**.

```
Destination     Target
10.0.0.0/16     local          ← always present, cannot be removed
0.0.0.0/0       igw-xxxxx      ← makes this subnet public
```

The `local` route is why every subnet in a VPC can reach every other by default — VPCs are
flat internally, and segmentation comes from security groups and NACLs.

## Internet Gateway

A horizontally scaled, highly available component that connects the VPC to the internet. One
per VPC.

It does one-to-one NAT between a private IP and a public IP. **This is why an instance never
sees its own public address** — the OS is configured with the private IP only.

Three things are all required for internet access:

1. an Internet Gateway attached to the VPC
2. a route `0.0.0.0/0 → igw` in the subnet's route table
3. a public IP on the instance

## NAT Gateway

Lets instances in **private** subnets reach out to the internet (package updates, API calls)
while remaining unreachable from it.

```
private instance ──▶ NAT Gateway (in a PUBLIC subnet) ──▶ IGW ──▶ internet
```

> **NAT Gateways are one of the most common surprise AWS bills.** They cost roughly $0.045
> per hour (~$32/month each) *plus* a per-GB data processing charge — and the textbook
> highly-available design puts one in each AZ.
>
> Cheaper alternatives: a **VPC Gateway Endpoint** for S3 and DynamoDB is **free** and keeps
> that traffic off the NAT entirely. For dev environments, a single shared NAT (accepting the
> AZ risk) or a NAT *instance* is far cheaper.

## Security Groups vs Network ACLs

| | Security Group | Network ACL |
|---|---|---|
| Level | instance (ENI) | **subnet** |
| State | **stateful** | **stateless** |
| Rules | allow only | allow **and deny** |
| Evaluation | all rules together | **numbered, first match wins** |
| Default | deny in, allow out | allow all both ways |

> **Stateless is the trap.** With a NACL, allowing inbound 443 is not enough — you must also
> allow **outbound on the ephemeral port range (1024–65535)** for the reply, or connections
> hang. Security groups handle the return traffic automatically.

Use security groups as the primary control; reach for NACLs for coarse subnet-wide denies,
such as blocking a hostile IP range.

## Public vs private subnet — the standard three-tier design

```
                           Internet
                              │
                        ┌─────▼─────┐
                        │    IGW    │
                        └─────┬─────┘
   ┌──────────────────────────┼──────────────────────────┐
   │ VPC 10.0.0.0/16          │                          │
   │  ┌───────────────────────▼────────────────────────┐ │
   │  │ PUBLIC   10.0.1.0/24 (AZ-a)  10.0.2.0/24 (AZ-b)│ │
   │  │   ALB,  NAT Gateway,  bastion                  │ │
   │  └───────────────────────┬────────────────────────┘ │
   │                          │ NAT                      │
   │  ┌───────────────────────▼────────────────────────┐ │
   │  │ PRIVATE  10.0.11.0/24 (AZ-a) 10.0.12.0/24(AZ-b)│ │
   │  │   application servers / EKS nodes              │ │
   │  └───────────────────────┬────────────────────────┘ │
   │                          │                          │
   │  ┌───────────────────────▼────────────────────────┐ │
   │  │ DATA     10.0.21.0/24 (AZ-a) 10.0.22.0/24(AZ-b)│ │
   │  │   RDS, ElastiCache - NO internet route at all  │ │
   │  └────────────────────────────────────────────────┘ │
   └─────────────────────────────────────────────────────┘
```

The data tier has **no route to the internet in either direction** — not even via NAT. It is
reachable only from the app tier's security group.

## Other VPC components

| Component | Purpose |
|---|---|
| **VPC Endpoints** | reach AWS services privately. *Gateway* endpoints (S3, DynamoDB) are free; *Interface* endpoints (ENI-based) are hourly |
| **VPC Peering** | connect two VPCs; **not transitive**, CIDRs must not overlap |
| **Transit Gateway** | hub-and-spoke for many VPCs — replaces a mesh of peerings |
| **VPC Flow Logs** | capture accepted/rejected traffic metadata; the first thing to enable when debugging connectivity |
| **Site-to-Site VPN / Direct Connect** | link to on-premises |

## Debugging connectivity — the order that works

1. **Security group** — is the port allowed inbound from that source?
2. **NACL** — stateless, so check *both* directions
3. **Route table** — is there a route to the destination?
4. **IGW/NAT** — present, attached, and in the route table?
5. **Public IP** — does the instance actually have one?
6. **Flow Logs** — `ACCEPT` or `REJECT`, and at which hop?

> `VPC Reachability Analyzer` answers this automatically: give it a source and destination
> and it tells you which component is blocking.

## Hands-on commands

```bash
aws ec2 describe-vpcs --query 'Vpcs[].{ID:VpcId,CIDR:CidrBlock,Default:IsDefault}' --output table
aws ec2 describe-subnets --filters Name=vpc-id,Values=vpc-xxx \
  --query 'Subnets[].{ID:SubnetId,CIDR:CidrBlock,AZ:AvailabilityZone,PublicIP:MapPublicIpOnLaunch}' --output table
aws ec2 describe-route-tables   --filters Name=vpc-id,Values=vpc-xxx
aws ec2 describe-internet-gateways
aws ec2 describe-nat-gateways
aws ec2 describe-security-groups --filters Name=vpc-id,Values=vpc-xxx
aws ec2 describe-availability-zones --region ap-south-1 --query 'AvailabilityZones[].ZoneName'
```
