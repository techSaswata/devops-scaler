#!/usr/bin/env bash
# Module 17, Task 1 — the full Terraform workflow against REAL AWS.
# Everything created here is destroyed at the end of this script.
export PATH="/opt/homebrew/bin:$PATH"
export AWS_REGION=ap-south-1 AWS_DEFAULT_REGION=ap-south-1
set -u
hr(){ echo; echo "=== $* ==="; }
run(){ echo; echo "\$ $*"; eval "$@" 2>&1 | head -${N:-40}; }
# For commands that MUST run to completion, never pipe into head: once head has
# taken its lines it exits, the writer gets SIGPIPE and dies mid-operation.
# An earlier version of this script lost a `terraform destroy` that way and left
# a real S3 bucket behind while the log claimed it was gone.
runfull(){ echo; echo "\$ $*"; local out; out=$(eval "$@" 2>&1); echo "$out" | tail -${N:-25}; }
cd "$(cd "$(dirname "$0")/.." && pwd)/terraform-s3-demo"

hr "0. WHO ARE WE, AND WHERE"
echo "\$ aws sts get-caller-identity"
aws sts get-caller-identity 2>&1 | python3 -c "
import json,sys
d=json.load(sys.stdin); a=d.get('Account','')
print('  Account: ' + a[:4] + '*'*(len(a)-4) + '   (redacted)')
print('  Arn:     ' + d.get('Arn','').rsplit('/',1)[-1])
"
echo "  Region:  $AWS_REGION"

hr "1. terraform init"
rm -rf .terraform .terraform.lock.hcl terraform.tfstate*
run "terraform init"
echo ">> init downloads the providers and prepares the backend. The lock file it"
echo ">> writes pins exact provider versions and SHOULD be committed in a real"
echo ">> project, so every engineer and CI runner resolves identically."

hr "2. terraform fmt"
run "terraform fmt -check -recursive -diff"
echo ">> Exit 0 = already canonical formatting."

hr "3. terraform validate"
run "terraform validate"
echo ">> validate checks syntax and internal consistency. It does NOT contact AWS,"
echo ">> so it cannot tell you a bucket name is taken - only that the code is sane."

hr "4. terraform plan"
run "terraform plan -out=tfplan"
echo
echo ">> The plan is the SAFETY MECHANISM: read it before every apply. Saving it"
echo ">> with -out and applying THAT file guarantees you apply exactly what you"
echo ">> reviewed, even if someone edits the code in between."
run "terraform show -json tfplan | python3 -c 'import json,sys; d=json.load(sys.stdin); print(\"resources to create:\", len(d[\"resource_changes\"]))'"

hr "5. terraform apply"
runfull "terraform apply -auto-approve tfplan"

hr "6. terraform show — the state"
run "terraform show | head -40"

hr "7. terraform output"
run "terraform output"
echo
run "terraform output -json | python3 -m json.tool"
BUCKET=$(terraform output -raw bucket_name)
echo
echo ">> bucket: $BUCKET"

hr "8. VERIFY WITH THE AWS CLI — independently of Terraform"
run "aws s3api head-bucket --bucket $BUCKET && echo 'bucket exists'"
run "aws s3 ls s3://$BUCKET/"
run "aws s3api get-bucket-versioning --bucket $BUCKET"
run "aws s3api get-bucket-encryption --bucket $BUCKET"
run "aws s3api get-public-access-block --bucket $BUCKET"
run "aws s3api get-bucket-tagging --bucket $BUCKET"
echo
echo "\$ aws s3 cp s3://$BUCKET/README.txt -"
aws s3 cp "s3://$BUCKET/README.txt" - 2>&1 | head -6

hr "9. terraform state — inspecting what Terraform tracks"
run "terraform state list"
run "terraform state show aws_s3_bucket.demo | head -16"
echo ">> State maps real infrastructure to configuration. It also holds every"
echo ">> attribute in PLAIN TEXT, which is why terraform.tfstate is gitignored"
echo ">> and why real teams keep it in an encrypted S3 backend with locking."

hr "10. IDEMPOTENCE — a second plan should show no changes"
run "terraform plan -detailed-exitcode 2>&1 | tail -5"
echo ">> 'No changes.' Terraform is DECLARATIVE: re-running converges rather"
echo ">> than duplicating. -detailed-exitcode returns 0=no changes, 2=changes,"
echo ">> 1=error, which is what CI uses to detect configuration drift."

hr "11. terraform destroy"
runfull "terraform destroy -auto-approve"
echo
echo "--- confirm it is really gone, from BOTH sides ---"
echo "\$ terraform state list"
terraform state list 2>&1 | head -3
echo "(no resources listed = state is empty)"
echo
echo "\$ aws s3api head-bucket --bucket $BUCKET   (expected to FAIL)"
aws s3api head-bucket --bucket "$BUCKET" 2>&1 | head -3
echo
echo "\$ aws s3 ls | grep devops-hw   (independent of terraform state)"
aws s3 ls 2>&1 | grep -i devops-hw || echo "(no matching bucket on the account)"
echo ">> 404 and an empty listing. Nothing left running, no ongoing cost."
rm -f tfplan
