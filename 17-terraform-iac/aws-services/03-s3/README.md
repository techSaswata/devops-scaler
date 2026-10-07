# S3 — Simple Storage Service

**Saswata Das — 24BCS10248** · Session 18, Task 2.03

Everything here was exercised for real — see
[`../../scripts/01-terraform-s3.sh`](../../scripts/01-terraform-s3.sh) and its captured run.

## What S3 is

S3 is **object storage**: you put whole files in and get whole files out, addressed by key
over HTTP. It is not a filesystem — there is no partial write, no append, no rename.

It is effectively infinite, durable to **eleven nines** (99.999999999%), and you pay for what
you store plus what you transfer.

## Buckets

A bucket is the top-level container.

- The name is **globally unique across every AWS account on earth**. This is why the
  Terraform project appends a random suffix:
  ```hcl
  resource "random_id" "suffix" { byte_length = 4 }
  bucket = "${var.project_name}-${var.environment}-${random_id.suffix.hex}"
  ```
- A bucket lives in **one region**, and data does not leave it unless you replicate it.
- Names must be DNS-compatible: lowercase, 3–63 characters, no underscores.

## Objects

An object is the data plus its metadata, identified by a **key**.

```
s3://devops-hw-demo-87fae26e/logs/2026/10/08/app.log
   └──────── bucket ───────┘ └──────── key ────────┘
```

> **There are no real folders.** The key is one flat string; the console renders `/` as a
> directory tree for convenience. `logs/2026/` is a *prefix*, not a directory — which is why
> you cannot rename a "folder" without copying every object.

Max object size is 5 TB; anything over 5 GB must use multipart upload (the CLI does this
automatically).

## Storage classes

| Class | Use | Retrieval |
|---|---|---|
| **Standard** | frequently accessed | immediate |
| **Intelligent-Tiering** | unpredictable access | immediate, auto-tiers for you |
| Standard-IA | infrequent, needs immediacy | immediate, higher per-GB read cost |
| One Zone-IA | re-creatable data | immediate, single AZ |
| Glacier Instant | archive, occasional instant access | milliseconds |
| Glacier Flexible | archive | minutes to hours |
| **Deep Archive** | compliance, 7-year retention | **up to 12 hours** |

> Cheaper classes charge a **minimum storage duration** (30–180 days) and a per-GB retrieval
> fee. Moving churny data to Glacier can cost *more* than Standard.

## Versioning

Keeps every version of an object, so an overwrite or delete is recoverable.

```hcl
resource "aws_s3_bucket_versioning" "demo" {
  bucket = aws_s3_bucket.demo.id
  versioning_configuration { status = "Enabled" }
}
```

```
$ aws s3api get-bucket-versioning --bucket devops-hw-demo-87fae26e
{ "Status": "Enabled" }
```

Two things to know:

- **Deleting creates a delete marker.** The object disappears from listings but every
  version still exists — and you are still paying for all of them.
- **Versioning cannot be switched off**, only *suspended*. Existing versions remain.

This is the main defence against ransomware and `aws s3 rm --recursive` typos — pair it with
MFA Delete.

## Lifecycle policies

Rules that transition or expire objects automatically.

```hcl
rule {
  id     = "expire-old-versions"
  status = "Enabled"
  noncurrent_version_transition {
    noncurrent_days = 30
    storage_class   = "STANDARD_IA"
  }
  noncurrent_version_expiration { noncurrent_days = 90 }
}
```

Without a rule like this, versioning quietly grows your bill forever. Also worth adding:
`abort_incomplete_multipart_upload`, since failed uploads leave invisible, billable parts.

## Encryption

| Type | Key managed by | Use |
|---|---|---|
| **SSE-S3** (AES256) | AWS | the default; free |
| **SSE-KMS** | you, in KMS | audit trail per decrypt, key rotation, cross-account control |
| SSE-C | you, supplied per request | rare |
| Client-side | you, before upload | zero trust in the provider |

```
$ aws s3api get-bucket-encryption --bucket devops-hw-demo-87fae26e
"SSEAlgorithm": "AES256"
```

All new buckets encrypt at rest by default, but declaring it explicitly makes the intent
auditable. **Encryption in transit** is separate — enforce HTTPS with a bucket policy
denying `aws:SecureTransport: false`.

## Bucket policies and public access

A resource-based policy attached to the bucket:

```json
{
  "Effect": "Deny",
  "Principal": "*",
  "Action": "s3:*",
  "Resource": ["arn:aws:s3:::my-bucket", "arn:aws:s3:::my-bucket/*"],
  "Condition": { "Bool": { "aws:SecureTransport": "false" } }
}
```

### Block Public Access — the setting that matters most

```hcl
resource "aws_s3_bucket_public_access_block" "demo" {
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
```

```
$ aws s3api get-public-access-block --bucket devops-hw-demo-87fae26e
"BlockPublicAcls": true, "BlockPublicPolicy": true,
"IgnorePublicAcls": true, "RestrictPublicBuckets": true
```

> **Nearly every "S3 data breach" headline is a bucket without this.** It overrides any ACL
> or policy that would otherwise make objects public, so a mistake elsewhere cannot expose
> the data. AWS now enables it by default on new buckets — leave it on.
>
> To serve content publicly, put **CloudFront** in front with Origin Access Control, and keep
> the bucket private.

## Consistency and durability

S3 has been **strongly read-after-write consistent** since 2020 — a `PUT` is immediately
visible to a subsequent `GET`. Older material describing eventual consistency is out of date.

Standard stores data across at least three availability zones. Durability (11 nines) is not
the same as availability (99.99%) — and neither protects you from deleting the object
yourself, which is what versioning is for.

## Common use cases

- Static website hosting (behind CloudFront)
- Application assets: uploads, images, documents
- **Terraform remote state** — with versioning on and DynamoDB for locking
- Data lakes queried in place by Athena
- Backups and long-term archive
- Log destination for CloudTrail, ALB, VPC Flow Logs

## Hands-on commands

```bash
aws s3 ls                                  # list buckets
aws s3 ls s3://bucket/prefix/              # list objects
aws s3 cp file.txt s3://bucket/
aws s3 sync ./local s3://bucket/remote/
aws s3 cp s3://bucket/key -                # stream to stdout

aws s3api head-bucket            --bucket B   # does it exist / do I have access?
aws s3api get-bucket-versioning  --bucket B
aws s3api get-bucket-encryption  --bucket B
aws s3api get-public-access-block --bucket B
aws s3api list-object-versions   --bucket B   # including delete markers
aws s3 presign s3://bucket/key --expires-in 3600   # temporary signed URL
```

> **Presigned URLs** are the right way to let a browser upload or download directly without
> making the bucket public and without proxying bytes through your application.
