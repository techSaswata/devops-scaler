# IAM — Identity and Access Management

**Saswata Das — 24BCS10248** · Session 18, Task 2.01

## What IAM is

IAM controls **who** can do **what** to **which** AWS resources. Every single AWS API call
is authenticated and authorised by IAM — there is no way around it. It is global, not
regional, and it is free.

Every request answers three questions:

```
  PRINCIPAL        ACTION              RESOURCE
  who is asking    what they want      what they want it on
  (user/role)      (s3:GetObject)      (arn:aws:s3:::my-bucket/*)
```

## Users

A **user** is a permanent identity for a human or a legacy application. It has long-lived
credentials: a console password, and/or an access key pair.

```bash
aws iam create-user --user-name saswata
aws iam create-access-key --user-name saswata
```

> **Access keys are the main way AWS accounts get compromised** — committed to git, pasted
> into a chat, left in a `.env`. Prefer roles (below), and if you must use a key, rotate it
> on a schedule and never commit it. GitHub's secret scanning will block a push containing
> one, as demonstrated in [module 16](../../../16-devsecops/#4-secret-scanning--which-caught-me-twice).

## Groups

A **group** is a collection of users that share permissions. Attach policies to the group,
not to each user.

```bash
aws iam create-group --group-name developers
aws iam add-user-to-group --user-name saswata --group-name developers
```

Groups cannot be nested, and a group is **not** an identity — you cannot give a group
credentials or make it a principal in a trust policy.

## Roles

A **role** is an identity with permissions but **no permanent credentials**. Something
*assumes* it and receives temporary credentials that expire (typically 1 hour).

This is the single most important IAM concept.

| Who assumes it | Example |
|---|---|
| An EC2 instance | an app reads S3 without any key on disk |
| A Lambda function | its execution role |
| A Kubernetes pod | IRSA / EKS Pod Identity |
| A user in another account | cross-account access |
| A federated user | SSO, or GitHub Actions via OIDC |

A role has **two** policies:

- a **trust policy** — *who may assume it*
- a **permissions policy** — *what it can do once assumed*

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Service": "ec2.amazonaws.com" },
    "Action": "sts:AssumeRole"
  }]
}
```

> **Why roles beat keys:** credentials are temporary, rotated automatically, never stored on
> disk, and never committed. An EC2 instance with a role has no access key to leak.

## Policies

A policy is a JSON document granting or denying permissions.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ReadOneBucket",
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:ListBucket"],
      "Resource": [
        "arn:aws:s3:::devops-hw-demo",
        "arn:aws:s3:::devops-hw-demo/*"
      ],
      "Condition": {
        "IpAddress": { "aws:SourceIp": "203.0.113.0/24" }
      }
    }
  ]
}
```

Note the two ARNs: `:::bucket` for bucket-level actions like `ListBucket`, and `:::bucket/*`
for object-level actions like `GetObject`. Forgetting the second is the most common reason a
policy "doesn't work".

| Policy type | Attached to |
|---|---|
| **Identity-based** | a user, group or role |
| **Resource-based** | the resource itself (S3 bucket policy, SQS queue policy) |
| **Permissions boundary** | caps the maximum permissions an identity can have |
| **SCP** (Organizations) | caps permissions for a whole account |

## How permissions are evaluated

```
  Explicit DENY anywhere?  ──yes──▶  DENIED
          │ no
  Explicit ALLOW?          ──no───▶  DENIED  (implicit deny — the default)
          │ yes
        ALLOWED
```

**An explicit `Deny` always wins.** Nothing can override it — not an admin policy, not a
resource policy. And with no matching `Allow`, the answer is deny; AWS is deny-by-default.

## Least privilege

Grant only the permissions actually needed, on only the resources actually needed.

| Instead of | Use |
|---|---|
| `"Action": "*"` | the specific actions the app calls |
| `"Resource": "*"` | the specific ARNs |
| `AdministratorAccess` | a scoped custom policy |
| a long-lived user key | a role |

Practical approach: start with nothing, run the application, read the `AccessDenied` errors,
and add exactly those actions. **IAM Access Analyzer** can generate a policy from CloudTrail
history of what an identity actually used.

## Best practices

1. **Lock away the root user.** Use it only for the handful of tasks that require it. Enable
   MFA on it and delete its access keys.
2. **Enable MFA** for every human user.
3. **Prefer roles over users.** Humans via SSO/Identity Center; workloads via instance or
   pod roles.
4. **No wildcards in production policies.**
5. **Rotate** any key that must exist.
6. **Use permissions boundaries** so a team that can create roles cannot escalate beyond
   their own level.
7. **Audit with CloudTrail**, Access Analyzer and the credential report.

```bash
aws iam generate-credential-report
aws iam get-credential-report --query Content --output text | base64 -d
```

## Common use cases

| Need | Approach |
|---|---|
| App on EC2 reads S3 | instance profile with a scoped role |
| Pod in EKS reads S3 | IRSA — a service account annotated with a role ARN |
| CI deploys to AWS | **OIDC federation** from GitHub Actions — no stored keys at all |
| Vendor needs access | cross-account role with `ExternalId` |
| Developers get console access | Identity Center (SSO), with permission sets |

> **The GitHub Actions case is worth highlighting.** Instead of storing `AWS_ACCESS_KEY_ID`
> as a repository secret, configure an OIDC trust so Actions exchanges its signed token for
> temporary AWS credentials. There is then no AWS key anywhere in the repository to leak.
