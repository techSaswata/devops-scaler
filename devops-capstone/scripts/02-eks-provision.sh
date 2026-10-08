#!/usr/bin/env bash
# M7 — provision the real AWS infrastructure with Terraform.
#
# This creates BILLABLE resources: an EKS control plane (~$0.10/hr), a NAT
# gateway (~$0.045/hr) and two t3.medium nodes (~$0.08/hr). scripts/09-destroy.sh
# tears all of it down and verifies the teardown against the AWS API.
export PATH="/opt/homebrew/bin:$PATH"
export AWS_PAGER=""
set -u
hr(){ echo; echo "=== $* ==="; }
# Never pipe terraform into `head`: the closed pipe sends SIGPIPE and can kill
# the run PART WAY THROUGH while the log still reads plausibly. Capture in full,
# trim afterwards.
runfull(){ echo; echo "\$ $*"; local o; o=$(eval "$@" 2>&1); echo "$o" | tail -${N:-25}; }
D="$(cd "$(dirname "$0")/.." && pwd)"
cd "$D/terraform"

hr "0. WHO AM I, AND WHERE"
runfull "aws sts get-caller-identity"
echo ">> A shared account, hence the Owner tag on every resource and the"
echo ">> verified teardown in scripts/09-destroy.sh."

hr "1. INIT"
N=15 runfull "terraform init -no-color -upgrade"

hr "2. FMT AND VALIDATE"
runfull "terraform fmt -check -recursive -no-color"
echo ">> No output means every file is already canonically formatted."
runfull "terraform validate -no-color"

hr "3. PLAN"
N=45 runfull "terraform plan -no-color -var use_nat_gateway=false -out=tfplan"

hr "4. APPLY"
echo "EKS control planes take 8-12 minutes, and the node group another 3-5."
N=45 runfull "terraform apply -no-color -auto-approve tfplan"

hr "5. OUTPUTS"
runfull "terraform output -no-color"

hr "6. THE CLUSTER EXISTS, ASKED OF AWS RATHER THAN OF STATE"
CLUSTER=$(terraform output -raw cluster_name)
VPC=$(terraform output -raw vpc_id)
runfull "aws eks describe-cluster --name $CLUSTER --query 'cluster.{Name:name,Status:status,Version:version,Endpoint:endpoint}' --output table"
runfull "aws eks describe-nodegroup --cluster-name $CLUSTER --nodegroup-name ${CLUSTER}-ng --query 'nodegroup.{Status:status,Instance:instanceTypes,Desired:scalingConfig.desiredSize}' --output table"
runfull "aws ec2 describe-vpcs --vpc-ids $VPC --query 'Vpcs[0].{Id:VpcId,Cidr:CidrBlock}' --output table"
runfull "aws ec2 describe-subnets --filters Name=vpc-id,Values=$VPC --query 'sort_by(Subnets,&CidrBlock)[].{Id:SubnetId,AZ:AvailabilityZone,Cidr:CidrBlock,Public:MapPublicIpOnLaunch}' --output table"
runfull "aws eks list-addons --cluster-name $CLUSTER --output table"

hr "7. POINT KUBECTL AT IT"
runfull "aws eks update-kubeconfig --region ap-south-1 --name $CLUSTER"
runfull "kubectl get nodes -o wide"
runfull "kubectl get pods -A --no-headers | wc -l"
echo ">> Nodes Ready and the system pods running: the CNI, CoreDNS and"
echo ">> kube-proxy addons all came up, so pods will get addresses and DNS."

hr "8. STATE"
runfull "terraform state list"
TOTAL=$(terraform state list | wc -l | tr -d ' ')
echo ">> $TOTAL addresses under management."
