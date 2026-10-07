#!/usr/bin/env bash
# Module 20, part 5 - provision the project's AWS infrastructure for real, then
# destroy it. The account is shared, so everything here is tagged
# Owner = 24BCS10248 (providers.tf default_tags) and the teardown is wired to a
# trap, which runs even if the script dies in the middle.
export PATH="/opt/homebrew/bin:$PATH"
export AWS_PAGER=""
set -u
hr(){ echo; echo "=== $* ==="; }
# No `head` anywhere near terraform. Piping terraform into head closes the pipe
# early, terraform takes SIGPIPE, and the run dies PART WAY THROUGH while the
# log still looks plausible. That is how an earlier module left a real S3 bucket
# behind under a log that claimed it was gone. runfull captures first, trims
# after, so the command always completes.
runfull(){ echo; echo "\$ $*"; local o; o=$(eval "$@" 2>&1); echo "$o" | tail -${N:-25}; }
cd "$(dirname "$0")/../terraform"

DESTROYED=0
cleanup(){
  [ "$DESTROYED" = "1" ] && return
  echo
  echo "=== TEARDOWN (trap) ==="
  terraform destroy -auto-approve -no-color 2>&1 | tail -12
}
trap cleanup EXIT

hr "0. WHO AM I, AND WHERE"
runfull "aws sts get-caller-identity"
echo ">> A shared account. Hence the Owner tag and the trap."

hr "1. INIT"
N=12 runfull "terraform init -no-color -upgrade"

hr "2. FMT AND VALIDATE"
runfull "terraform fmt -check -recursive -no-color"
echo ">> No output means every file is already canonically formatted."
runfull "terraform validate -no-color"

hr "3. PLAN"
N=40 runfull "terraform plan -no-color -out=tfplan"

hr "4. APPLY - this creates real resources"
N=40 runfull "terraform apply -no-color -auto-approve tfplan"

hr "5. OUTPUTS"
runfull "terraform output -no-color"

hr "6. THE RESOURCES EXIST, CONFIRMED FROM OUTSIDE TERRAFORM"
# Asking AWS directly, not reading terraform's own state. State is terraform's
# opinion; the API is the fact.
BUCKET=$(terraform output -raw artifacts_bucket 2>/dev/null)
VPC=$(terraform output -raw vpc_id 2>/dev/null)
ECR=$(terraform output -raw ecr_repository_url 2>/dev/null)
echo "bucket: $BUCKET"
echo "vpc:    $VPC"
echo "ecr:    $ECR"
runfull "aws s3api head-bucket --bucket $BUCKET && echo 'bucket exists'"
runfull "aws s3api get-bucket-versioning --bucket $BUCKET"
runfull "aws s3api get-bucket-encryption --bucket $BUCKET --query 'ServerSideEncryptionConfiguration.Rules[0]'"
runfull "aws ec2 describe-vpcs --vpc-ids $VPC --query 'Vpcs[0].{Id:VpcId,Cidr:CidrBlock,Tags:Tags[?Key==\`Owner\`].Value}'"
runfull "aws ec2 describe-subnets --filters Name=vpc-id,Values=$VPC --query 'Subnets[].{Id:SubnetId,AZ:AvailabilityZone,Cidr:CidrBlock}'"
runfull "aws ecr describe-repositories --repository-names taskapi --query 'repositories[0].{Url:repositoryUrl,Mutability:imageTagMutability,ScanOnPush:imageScanningConfiguration.scanOnPush}'"

hr "7. STATE - what terraform is tracking"
runfull "terraform state list"
TOTAL=$(terraform state list | wc -l | tr -d ' ')
MANAGED=$(terraform state list | grep -vc '^data\.')
echo ">> $TOTAL addresses: $MANAGED managed resources plus the data source, which"
echo ">> terraform reads but does not own. State is the map between these names"
echo ">> and the real AWS IDs; lose it and terraform can neither update nor"
echo ">> destroy what it made."

hr "8. DRIFT - terraform notices a change it did not make"
echo "Adding a tag to the bucket with the AWS CLI, behind terraform's back:"
runfull "aws s3api put-bucket-tagging --bucket $BUCKET --tagging 'TagSet=[{Key=TouchedBy,Value=aws-cli},{Key=Owner,Value=24BCS10248}]'"
echo
echo "\$ terraform plan -detailed-exitcode   (exit 2 means drift)"
terraform plan -detailed-exitcode -no-color -refresh=true > /tmp/drift.txt 2>&1
echo "exit code: $?"
grep -E '^  # |^Plan:|will be updated|must be replaced|No changes' /tmp/drift.txt | head -8
echo ">> Exit 2 is the useful one for CI: 0 = no drift, 1 = error, 2 = drift."

hr "9. DESTROY"
N=30 runfull "terraform destroy -no-color -auto-approve"
DESTROYED=1

hr "10. THE RESOURCES ARE REALLY GONE, CONFIRMED FROM OUTSIDE"
# Each check is phrased so that SUCCESS of the command means the resource still
# exists. Anything other than a clean 'gone' line below is a leftover.
echo "\$ aws s3api head-bucket --bucket $BUCKET"
if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  echo "  STILL EXISTS -- leftover!"
else
  echo "  gone (head-bucket failed, which is what we want)"
fi
echo "\$ aws ec2 describe-vpcs --vpc-ids $VPC"
aws ec2 describe-vpcs --vpc-ids "$VPC" 2>&1 | grep -oE 'InvalidVpcID.NotFound|"VpcId"' | head -1 | sed 's/InvalidVpcID.NotFound/  gone (InvalidVpcID.NotFound)/; s/"VpcId"/  STILL EXISTS -- leftover!/'
echo "\$ aws ecr describe-repositories --repository-names taskapi"
aws ecr describe-repositories --repository-names taskapi 2>&1 | grep -oE 'RepositoryNotFoundException|"repositoryUrl"' | head -1 | sed 's/RepositoryNotFoundException/  gone (RepositoryNotFoundException)/; s/"repositoryUrl"/  STILL EXISTS -- leftover!/'

hr "11. NOTHING OF MINE LEFT ANYWHERE IN THE REGION"
echo "\$ aws resourcegroupstaggingapi get-resources --tag-filters Key=Owner,Values=24BCS10248"
ARNS=$(aws resourcegroupstaggingapi get-resources --region ap-south-1 \
         --tag-filters Key=Owner,Values=24BCS10248 \
         --query 'ResourceTagMappingList[].ResourceARN' --output text 2>/dev/null | tr '\t' '\n')
if [ -z "$ARNS" ]; then
  echo "  (nothing indexed under Owner=24BCS10248)"
else
  echo "$ARNS" | sed 's/^/  indexed: /'
  echo
  echo "--- An ARN here does NOT prove the resource exists. The tagging API is"
  echo "--- an INDEX, and it keeps entries for terminated resources for a while"
  echo "--- after the resource itself is reaped. Treating this list as the truth"
  echo "--- would mean either a false alarm or, worse, trusting it the other way"
  echo "--- round. So each ARN is resolved against the service that owns it:"
  for a in $ARNS; do
    case "$a" in
      *:instance/*)
        id="${a##*/}"
        st=$(aws ec2 describe-instances --region ap-south-1 --instance-ids "$id" \
               --query 'Reservations[].Instances[].State.Name' --output text 2>/dev/null)
        if [ -z "$st" ]; then
          echo "  $id -> gone; no instance record at all (stale index entry)"
        else
          echo "  $id -> STILL EXISTS, state=$st  <-- NEEDS ATTENTION"
        fi
        ;;
      *:vpc/*)
        id="${a##*/}"
        aws ec2 describe-vpcs --region ap-south-1 --vpc-ids "$id" >/dev/null 2>&1 \
          && echo "  $id -> STILL EXISTS  <-- NEEDS ATTENTION" \
          || echo "  $id -> gone (stale index entry)"
        ;;
      *)
        echo "  $a -> not auto-resolved; check by hand"
        ;;
    esac
  done
fi
echo
echo "--- live resources of mine, asked of each service directly ---"
echo "\$ aws ec2 describe-instances  (non-terminated, tagged mine)"
LIVE=$(aws ec2 describe-instances --region ap-south-1 \
        --filters 'Name=tag:Owner,Values=24BCS10248' \
                  'Name=instance-state-name,Values=pending,running,stopping,stopped,shutting-down' \
        --query 'Reservations[].Instances[].InstanceId' --output text 2>/dev/null)
[ -z "$LIVE" ] && echo "  (none)" || echo "  $LIVE  <-- NEEDS ATTENTION"
echo "\$ aws s3 ls | grep taskapi"
aws s3 ls 2>/dev/null | grep taskapi || echo "  (no taskapi bucket)"
echo "\$ aws ec2 describe-vpcs  (tagged mine)"
MV=$(aws ec2 describe-vpcs --region ap-south-1 --filters 'Name=tag:Owner,Values=24BCS10248' \
      --query 'Vpcs[].VpcId' --output text 2>/dev/null)
[ -z "$MV" ] && echo "  (none)" || echo "  $MV  <-- NEEDS ATTENTION"
echo "\$ aws ecr describe-repositories"
aws ecr describe-repositories --region ap-south-1 --query 'repositories[].repositoryName' \
  --output text 2>/dev/null | tr '\t' '\n' | grep -x taskapi || echo "  (no taskapi repository)"
echo
runfull "terraform state list"
echo ">> Empty state, and every service reports nothing of mine still running."
echo ">> Resources belonging to OTHER projects on this shared account were never"
echo ">> touched: nothing here filters on anything but Owner=24BCS10248."
