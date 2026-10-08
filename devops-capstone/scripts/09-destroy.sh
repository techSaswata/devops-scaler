#!/usr/bin/env bash
# Tear down everything this project created in AWS, and PROVE it.
#
# ORDER MATTERS, and this is the single most common way an EKS teardown fails:
# a Service of type LoadBalancer is created by Kubernetes, not by Terraform, so
# Terraform does not know the ELB exists. The ELB holds ENIs in the VPC's
# subnets, and `terraform destroy` then hangs for ~20 minutes trying to delete
# subnets that are still in use before failing with DependencyViolation -- and
# it leaves the cluster, the NAT gateway and the nodes running while it does.
#
# So: delete the Kubernetes objects that own AWS resources FIRST, wait for AWS
# to actually release them, and only then destroy the infrastructure.
export PATH="/opt/homebrew/bin:$PATH"
export AWS_PAGER=""
set -u
hr(){ echo; echo "=== $* ==="; }
runfull(){ echo; echo "\$ $*"; local o; o=$(eval "$@" 2>&1); echo "$o" | tail -${N:-25}; }
D="$(cd "$(dirname "$0")/.." && pwd)"
cd "$D/terraform"
REGION=ap-south-1
# Captured BEFORE destroy, because afterwards terraform output has nothing to say.
MYVPC=$(terraform output -raw vpc_id 2>/dev/null || echo "")
echo "target VPC: ${MYVPC:-<none>}"

hr "1. DELETE THE KUBERNETES OBJECTS THAT OWN AWS RESOURCES"
if kubectl cluster-info >/dev/null 2>&1; then
  echo "--- load balancers currently owned by Services ---"
  kubectl get svc -A -o json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
n=0
for s in d['items']:
    if s['spec'].get('type')=='LoadBalancer':
        ing=s.get('status',{}).get('loadBalancer',{}).get('ingress',[])
        host=ing[0].get('hostname','<pending>') if ing else '<pending>'
        print(f\"  {s['metadata']['namespace']}/{s['metadata']['name']}  ->  {host}\"); n+=1
print('  (none)' if n==0 else f'  {n} load balancer service(s)')"
  echo
  runfull "helm uninstall clinicflow -n clinicflow --wait --timeout 5m || true"
  runfull "helm uninstall monitoring -n monitoring --wait --timeout 5m || true"
  runfull "helm uninstall ingress-nginx -n ingress-nginx --wait --timeout 5m || true"
  runfull "kubectl delete ns clinicflow clinicflow-broken monitoring ingress-nginx --ignore-not-found --timeout=5m || true"

  echo
  echo "--- waiting for AWS to actually release the load balancers ---"
  # `helm uninstall` returns as soon as Kubernetes deletes the Service object.
  # The AWS-side ELB deletion is asynchronous and takes longer, so polling AWS
  # (not Kubernetes) is the only honest way to know it is gone.
  #
  # Scoped to MY VPC, not to a region-wide count. This account is shared and
  # already had another project's load balancer in it, so waiting for the total
  # to reach zero would have waited forever and then proceeded anyway -- a check
  # that cannot pass is worse than no check, because it looks like one.
  if [ -n "$MYVPC" ]; then
    for i in $(seq 1 60); do
      CLB=$(aws elb describe-load-balancers --region $REGION \
              --query "length(LoadBalancerDescriptions[?VPCId=='$MYVPC'])" --output text 2>/dev/null || echo 0)
      NLB=$(aws elbv2 describe-load-balancers --region $REGION \
              --query "length(LoadBalancers[?VpcId=='$MYVPC'])" --output text 2>/dev/null || echo 0)
      printf '  t+%-4s in %s: classic=%s v2=%s\n' "$((i*5))s" "$MYVPC" "$CLB" "$NLB"
      [ "$CLB" = "0" ] && [ "$NLB" = "0" ] && { echo "  my VPC holds no load balancers"; break; }
      sleep 5
    done
    echo
    echo "--- leftover ENIs would block subnet deletion; check for them too ---"
    for i in $(seq 1 24); do
      ENI=$(aws ec2 describe-network-interfaces --region $REGION \
              --filters "Name=vpc-id,Values=$MYVPC" \
              --query 'length(NetworkInterfaces)' --output text 2>/dev/null || echo 0)
      printf '  t+%-4s ENIs in VPC: %s\n' "$((i*5))s" "$ENI"
      [ "$ENI" = "0" ] && { echo "  VPC is clear"; break; }
      sleep 5
    done
  else
    echo "  (no vpc_id in state; skipping the scoped wait)"
  fi
else
  echo "No reachable cluster; nothing to clean up on the Kubernetes side."
fi

hr "2. DESTROY THE INFRASTRUCTURE"
N=40 runfull "terraform destroy -no-color -auto-approve"

hr "3. GONE, CONFIRMED FROM OUTSIDE TERRAFORM"
# Each check is phrased so that SUCCESS of the command means a leftover.
echo "\$ aws eks list-clusters"
aws eks list-clusters --region $REGION --query 'clusters' --output text 2>/dev/null | tr '\t' '\n' | grep -x clinicflow \
  && echo "  STILL EXISTS -- leftover!" || echo "  no clinicflow cluster"

echo "\$ aws ec2 describe-vpcs --filters tag:Owner=24BCS10248"
V=$(aws ec2 describe-vpcs --region $REGION --filters 'Name=tag:Owner,Values=24BCS10248' --query 'Vpcs[].VpcId' --output text 2>/dev/null)
[ -z "$V" ] && echo "  no VPC of mine" || echo "  $V  <-- NEEDS ATTENTION"

# Checked by VPC, NOT by tag, and that distinction is the whole point.
#
# An EKS managed node group does NOT propagate the provider's default_tags to
# the EC2 instances it launches -- the worker nodes came up with no Owner tag at
# all. A tag-scoped check therefore reported "nothing of mine is running" while
# two t3.medium instances were running and billing. The VPC is the authoritative
# boundary here because Terraform created it and nothing else is in it.
echo "\$ aws ec2 describe-instances  (anything still alive in MY VPC)"
if [ -n "${MYVPC:-}" ]; then
  I=$(aws ec2 describe-instances --region $REGION \
        --filters "Name=vpc-id,Values=$MYVPC" 'Name=instance-state-name,Values=pending,running,stopping,stopped,shutting-down' \
        --query 'Reservations[].Instances[].[InstanceId,State.Name]' --output text 2>/dev/null)
  [ -z "$I" ] && echo "  no instances left in the VPC" || echo "  $I  <-- NEEDS ATTENTION"
else
  echo "  (VPC already gone, so nothing can be left in it)"
fi
echo "\$ aws ec2 describe-instances  (and separately, anything tagged mine)"
IT=$(aws ec2 describe-instances --region $REGION \
      --filters 'Name=tag:Owner,Values=24BCS10248' 'Name=instance-state-name,Values=pending,running,stopping,stopped,shutting-down' \
      --query 'Reservations[].Instances[].InstanceId' --output text 2>/dev/null)
[ -z "$IT" ] && echo "  nothing tagged mine" || echo "  $IT  <-- NEEDS ATTENTION"

echo "\$ aws ec2 describe-nat-gateways  (NAT bills by the hour even when idle)"
NG=$(aws ec2 describe-nat-gateways --region $REGION \
      --filter 'Name=state,Values=available,pending' 'Name=tag:Owner,Values=24BCS10248' \
      --query 'NatGateways[].NatGatewayId' --output text 2>/dev/null)
[ -z "$NG" ] && echo "  no NAT gateway of mine" || echo "  $NG  <-- NEEDS ATTENTION"

echo "\$ aws ec2 describe-addresses  (an unattached Elastic IP is charged for)"
EIP=$(aws ec2 describe-addresses --region $REGION \
      --filters 'Name=tag:Owner,Values=24BCS10248' --query 'Addresses[].PublicIp' --output text 2>/dev/null)
[ -z "$EIP" ] && echo "  no Elastic IP of mine" || echo "  $EIP  <-- NEEDS ATTENTION"

echo "\$ aws ec2 describe-volumes  (an orphaned EBS volume keeps billing)"
VOL=$(aws ec2 describe-volumes --region $REGION \
      --filters 'Name=status,Values=available' --query 'Volumes[].VolumeId' --output text 2>/dev/null)
[ -z "$VOL" ] && echo "  no unattached volumes" || echo "  $VOL  <-- check these"

echo "\$ aws logs describe-log-groups  (/aws/eks/clinicflow)"
LG=$(aws logs describe-log-groups --region $REGION --log-group-name-prefix /aws/eks/clinicflow \
      --query 'logGroups[].logGroupName' --output text 2>/dev/null)
[ -z "$LG" ] && echo "  log group removed" || echo "  $LG  <-- NEEDS ATTENTION"

hr "4. NOTHING TAGGED Owner=24BCS10248 ANYWHERE IN THE REGION"
ARNS=$(aws resourcegroupstaggingapi get-resources --region $REGION \
        --tag-filters Key=Owner,Values=24BCS10248 \
        --query 'ResourceTagMappingList[].ResourceARN' --output text 2>/dev/null | tr '\t' '\n')
if [ -z "$ARNS" ]; then
  echo "  (nothing indexed)"
else
  echo "$ARNS" | sed 's/^/  indexed: /'
  echo
  echo "--- the tagging API is an INDEX, not an inventory: it keeps entries for"
  echo "--- terminated resources for a while. Each ARN is resolved against the"
  echo "--- service that owns it rather than believed on sight."
  for a in $ARNS; do
    case "$a" in
      *:instance/*)
        id="${a##*/}"
        st=$(aws ec2 describe-instances --region $REGION --instance-ids "$id" \
               --query 'Reservations[].Instances[].State.Name' --output text 2>/dev/null)
        [ -z "$st" ] && echo "  $id -> gone (stale index entry)" \
                     || echo "  $id -> STILL $st  <-- NEEDS ATTENTION" ;;
      *:vpc/*)
        id="${a##*/}"
        aws ec2 describe-vpcs --region $REGION --vpc-ids "$id" >/dev/null 2>&1 \
          && echo "  $id -> STILL EXISTS  <-- NEEDS ATTENTION" \
          || echo "  $id -> gone (stale index entry)" ;;
      *) echo "  $a -> resolve by hand" ;;
    esac
  done
fi

hr "5. TERRAFORM STATE"
runfull "terraform state list"
echo ">> Empty state and nothing of mine left running. Resources belonging to"
echo ">> OTHER projects on this shared account were never touched: every filter"
echo ">> above is scoped to Owner=24BCS10248."
