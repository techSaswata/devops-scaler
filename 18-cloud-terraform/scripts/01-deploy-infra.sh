#!/usr/bin/env bash
# Module 18 — end-to-end AWS infrastructure with Terraform.
# Everything created is destroyed at the end of this script.
export PATH="/opt/homebrew/bin:$PATH"
export AWS_REGION=ap-south-1 AWS_DEFAULT_REGION=ap-south-1
set -u
hr(){ echo; echo "=== $* ==="; }
run(){ echo; echo "\$ $*"; eval "$@" 2>&1 | head -${N:-35}; }
# Never pipe a command whose completion matters into head - it SIGPIPEs the
# writer. Module 17 lost a terraform destroy that way.
runfull(){ echo; echo "\$ $*"; local out; out=$(eval "$@" 2>&1); echo "$out" | tail -${N:-30}; }
cd "$(cd "$(dirname "$0")/.." && pwd)/infrastructure"

cleanup(){
  echo; echo "=== CLEANUP (always runs, even on error) ==="
  runfull "terraform destroy -auto-approve"
}
trap cleanup EXIT

hr "0. TARGET ACCOUNT AND REGION"
aws sts get-caller-identity 2>&1 | python3 -c "
import json,sys
d=json.load(sys.stdin); a=d.get('Account','')
print('  Account: ' + a[:4] + '*'*(len(a)-4) + '  (redacted)')
print('  Arn:     ' + d.get('Arn','').rsplit('/',1)[-1])"
echo "  Region:  $AWS_REGION"
run "aws ec2 describe-availability-zones --query 'AvailabilityZones[].ZoneName' --output text"

hr "1. THE ARCHITECTURE"
cat <<'ARCH'
                         Internet
                            │
                      ┌─────▼─────┐
                      │    IGW    │
                      └─────┬─────┘
    ┌───────────────────────┼────────────────────────────┐
    │ VPC  10.20.0.0/16     │                            │
    │  ┌────────────────────▼─────────────────────────┐  │
    │  │ PUBLIC   10.20.1.0/24 (az-a)                 │  │
    │  │          10.20.2.0/24 (az-b)                 │  │
    │  │   EC2 (nginx) ── web-sg: 80 from 0.0.0.0/0   │  │
    │  │        │  IAM instance role                  │  │
    │  └────────┼─────────────────────────────────────┘  │
    │           │ no key, temporary credentials          │
    │  ┌────────┼─────────────────────────────────────┐  │
    │  │ PRIVATE 10.20.11.0/24   10.20.12.0/24        │  │
    │  │   app-sg: 8080 FROM web-sg (not a CIDR)      │  │
    │  │   no 0.0.0.0/0 route                         │  │
    │  └──────────────────────────────────────────────┘  │
    └───────────────────────┼────────────────────────────┘
                            ▼
                     S3  assets bucket
              versioned, encrypted, public access blocked
ARCH

hr "2. terraform init / fmt / validate"
rm -rf .terraform .terraform.lock.hcl terraform.tfstate*
run "terraform init 2>&1 | tail -8"
run "terraform fmt -check -recursive"
run "terraform validate"

hr "3. terraform plan"
runfull "terraform plan -out=tfplan"
run "terraform show -json tfplan | python3 -c 'import json,sys; d=json.load(sys.stdin); print(\"resources to create:\", len(d[\"resource_changes\"]))'"
echo
echo "--- resource types in the plan ---"
terraform show -json tfplan | python3 -c "
import json,sys,collections
d=json.load(sys.stdin)
c=collections.Counter(r['type'] for r in d['resource_changes'])
for t,n in sorted(c.items()): print(f'  {n} x {t}')"

hr "4. terraform apply"
runfull "terraform apply -auto-approve tfplan"

hr "5. OUTPUTS"
run "terraform output"
IP=$(terraform output -raw instance_public_ip)
BUCKET=$(terraform output -raw bucket_name)
VPC=$(terraform output -raw vpc_id)

hr "6. DEPENDENCY GRAPH — Terraform worked out the order itself"
echo "\$ terraform graph | grep -c '\\->'"
terraform graph 2>/dev/null | grep -c '\->' || true
echo
echo ">> Nothing in this configuration uses depends_on except where a true"
echo ">> ordering requirement cannot be inferred. Terraform derived the rest"
echo ">> from references: the subnet needs the VPC, the instance needs the"
echo ">> subnet and the security group, the IAM policy needs the bucket ARN."

hr "7. VERIFY THE NETWORK WITH THE AWS CLI"
run "aws ec2 describe-vpcs --vpc-ids $VPC --query 'Vpcs[].{ID:VpcId,CIDR:CidrBlock,DNS:EnableDnsHostnames}' --output table"
run "aws ec2 describe-subnets --filters Name=vpc-id,Values=$VPC --query 'Subnets[].{ID:SubnetId,CIDR:CidrBlock,AZ:AvailabilityZone,AutoPublicIP:MapPublicIpOnLaunch}' --output table"
run "aws ec2 describe-route-tables --filters Name=vpc-id,Values=$VPC --query 'RouteTables[].{ID:RouteTableId,Routes:Routes[].DestinationCidrBlock}' --output json"
echo ">> One route table has a 0.0.0.0/0 route (public); the other has only the"
echo ">> local VPC route (private). That is the ONLY difference between them."

hr "8. VERIFY SECURITY GROUPS"
run "aws ec2 describe-security-groups --filters Name=vpc-id,Values=$VPC --query 'SecurityGroups[].{Name:GroupName,Ingress:IpPermissions[].{Port:FromPort,CIDR:IpRanges[].CidrIp,SG:UserIdGroupPairs[].GroupId}}' --output json"
echo ">> The app SG's source is a security GROUP ID, not a CIDR range."

hr "9. VERIFY THE INSTANCE"
run "aws ec2 describe-instances --filters Name=vpc-id,Values=$VPC Name=instance-state-name,Values=running --query 'Reservations[].Instances[].{ID:InstanceId,Type:InstanceType,AZ:Placement.AvailabilityZone,Private:PrivateIpAddress,Public:PublicIpAddress,IMDSv2:MetadataOptions.HttpTokens}' --output table"
echo ">> IMDSv2 required - blocks the SSRF class that harvested instance"
echo ">> credentials through IMDSv1."

hr "10. THE WEB SERVER IS ACTUALLY SERVING"
echo "waiting for cloud-init to install and start nginx..."
for i in $(seq 1 40); do
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://$IP/" 2>/dev/null)
  [ "$code" = "200" ] && { echo "  HTTP 200 after $((i*10))s"; break; }
  [ "$i" = "40" ] && echo "  no response after 400s (last code: $code)"
  sleep 10
done
echo
echo "\$ curl http://$IP/"
curl -s --max-time 10 "http://$IP/" 2>&1 | head -24

hr "11. VERIFY S3 AND THE IAM ROLE"
run "aws s3 ls s3://$BUCKET/ --recursive"
echo "\$ aws s3 cp s3://$BUCKET/config/app.json -"
aws s3 cp "s3://$BUCKET/config/app.json" - 2>&1 | python3 -m json.tool 2>/dev/null | head -8
run "aws s3api get-public-access-block --bucket $BUCKET --query PublicAccessBlockConfiguration"
run "aws iam get-role --role-name \$(terraform output -raw iam_role_name) --query 'Role.{Name:RoleName,Trust:AssumeRolePolicyDocument.Statement[0].Principal.Service}' --output json"
echo ">> The instance reaches S3 through this role. There is NO access key on"
echo ">> the instance, and nothing to leak."

hr "12. IDEMPOTENCE / DRIFT DETECTION"
run "terraform plan -detailed-exitcode 2>&1 | tail -4"
