# DynamoDB & RDS — Database Services

**Saswata Das — 24BCS10248** · Session 18, Task 2.05

Two managed database services that solve different problems. The first question is not
"which is better" but "does my access pattern fit a key-value lookup or a relational query".

---

# DynamoDB

## NoSQL

DynamoDB is a managed **key-value and document** store. It is serverless — no instances, no
version upgrades, no patching — and it scales to millions of requests per second with
single-digit millisecond latency.

The trade: you must know your **access patterns before you design the table**. There are no
joins, and an unindexed query means scanning the whole table.

| | SQL (RDS) | NoSQL (DynamoDB) |
|---|---|---|
| Schema | fixed, enforced | **flexible per item** |
| Joins | yes | **no** |
| Scaling | mostly vertical | horizontal, automatic |
| Query flexibility | any ad-hoc SQL | only via keys and indexes |
| Transactions | full ACID | ACID on up to 100 items |
| Design driven by | the data model | **the access patterns** |

## Tables, items, attributes

```
TABLE: Orders
┌──────────────────────────────────────────────────────────────┐
│ ITEM  { customerId: "C-1",  orderId: "O-9",  total: 250,     │  ← attributes
│         items: ["book","pen"],  status: "shipped" }          │
├──────────────────────────────────────────────────────────────┤
│ ITEM  { customerId: "C-2",  orderId: "O-1",  total: 99,      │
│         giftWrap: true }            ← different attributes!  │
└──────────────────────────────────────────────────────────────┘
```

- A **table** holds items.
- An **item** is a row — max **400 KB**.
- **Attributes** are the fields. Two items in one table need not have the same ones; only
  the key attributes are mandatory.

## Partition key and sort key

The **primary key** uniquely identifies an item, and comes in two shapes:

**Simple** — partition key only:
```
userId (PK)  →  one item per user
```

**Composite** — partition key + sort key:
```
customerId (PK) + orderId (SK)  →  many orders per customer
```

The **partition key** is hashed to choose a physical partition. The **sort key** orders items
*within* that partition, which is what makes range queries possible:

```python
# every order for one customer, newest first
Key('customerId').eq('C-1') & Key('orderDate').begins_with('2026-10')
```

> **Choosing the partition key is the single most important design decision.** A key with few
> distinct values (`status`, `country`) creates a **hot partition** — all traffic hits one
> physical node and gets throttled while the table looks idle overall. High-cardinality keys
> like `userId` or `orderId` spread load evenly.

Secondary indexes let you query by something other than the primary key:

| Index | Partition key | Note |
|---|---|---|
| **LSI** | same as the table | must be created with the table |
| **GSI** | **any attribute** | add any time, eventually consistent, billed separately |

## Capacity modes

| Mode | Billing | Use |
|---|---|---|
| **On-demand** | per request | spiky or unknown traffic; nothing to tune |
| **Provisioned** | per hour of reserved RCU/WCU | steady, predictable traffic — cheaper, supports auto-scaling |

## Use cases

Session stores · shopping carts · user profiles · IoT telemetry · leaderboards · event
sourcing · **Terraform state locking** (paired with an S3 backend).

**Not** a good fit for ad-hoc analytics, reporting, or anything needing joins.

---

# RDS

## Relational database

RDS is managed relational databases. AWS handles provisioning, patching, backups, failover
and replication; you keep full SQL and your existing schema.

It is the opposite trade from DynamoDB: full query flexibility and ACID guarantees, in
exchange for a server you must size and scale.

## Supported engines

| Engine | Note |
|---|---|
| PostgreSQL | the usual default for new work |
| MySQL / MariaDB | widest ecosystem |
| **Aurora** (MySQL/Postgres compatible) | AWS-built; faster, storage auto-grows to 128 TB, 15 read replicas |
| Oracle, SQL Server | commercial, licence-sensitive |

> **Aurora Serverless v2** scales capacity in fine-grained steps and is the closest RDS gets
> to DynamoDB's operational model.

## DB instances

Sized like EC2 — `db.t4g.micro`, `db.m6g.large`, `db.r6g.xlarge`. Storage is EBS
(gp3 or io1) and can grow automatically.

The instance class and storage are **the** cost drivers, and both can be changed later —
with a reboot.

## Security

| Control | Practice |
|---|---|
| **Network** | put it in a **private subnet**, never publicly accessible |
| **Security group** | inbound 5432/3306 **from the app's security group only**, never a CIDR |
| **Encryption at rest** | KMS — **must be enabled at creation**, cannot be added later |
| **Encryption in transit** | require SSL/TLS (`rds.force_ssl`) |
| **Credentials** | **Secrets Manager** with automatic rotation, or **IAM database authentication** (no password at all) |
| **Audit** | enable the engine's audit log, export to CloudWatch |

> `publicly_accessible = true` on an RDS instance is the database equivalent of an S3 bucket
> without Block Public Access. It should essentially never be set.

## Backups

| Mechanism | Retention | Restore |
|---|---|---|
| **Automated backups** | 0–35 days | **point-in-time**, to any second in the window |
| **Manual snapshots** | until you delete them | to a new instance |

Automated backups are deleted with the instance; manual snapshots survive. Setting retention
to `0` disables backups entirely — occasionally correct for a scratch database, catastrophic
anywhere else.

> **Restores always create a NEW instance.** You cannot restore in place, so recovery means
> restore, verify, then repoint the application.

## Multi-AZ

A **synchronous standby replica in a second availability zone**.

```
   app ──▶ writer endpoint ──▶ PRIMARY (AZ-a)
                                  │ synchronous replication
                                  ▼
                               STANDBY (AZ-b)   ← not readable
```

- Failover is automatic, typically 60–120 seconds, by **DNS change** — so the application
  must reconnect rather than cache the resolved IP.
- The standby serves **no read traffic**. Multi-AZ is for **availability**, not performance.
- It roughly doubles the cost.

## Read replicas

**Asynchronous** copies that *do* serve reads.

| | Multi-AZ standby | Read replica |
|---|---|---|
| Replication | synchronous | **asynchronous** |
| Serves reads | no | **yes** |
| Purpose | availability | **scaling reads** |
| Failover | automatic | manual promotion |
| Cross-region | no | **yes** |

> Because replication is asynchronous, read replicas have **replication lag**. An application
> that writes then immediately reads from a replica can get stale data — the classic
> read-after-write bug in a read-replica architecture.

Use both together: Multi-AZ for survival, read replicas for scale.

## Use cases

Transactional applications · anything with an existing relational schema · reporting and
analytics requiring joins · systems needing strict ACID guarantees · lift-and-shift of an
on-premises database.

---

# Choosing between them

| If you need | Use |
|---|---|
| Joins, ad-hoc queries, reporting | **RDS** |
| Known access patterns, extreme scale, low latency | **DynamoDB** |
| Strict multi-row ACID transactions | **RDS** |
| Zero operational overhead | **DynamoDB** |
| Spiky or unpredictable traffic | **DynamoDB on-demand** |
| An existing SQL application | **RDS** |

Real systems commonly use both: RDS as the system of record, DynamoDB for sessions and
high-volume event data.

## Hands-on commands

```bash
# DynamoDB
aws dynamodb create-table --table-name Orders \
  --attribute-definitions AttributeName=customerId,AttributeType=S AttributeName=orderId,AttributeType=S \
  --key-schema AttributeName=customerId,KeyType=HASH AttributeName=orderId,KeyType=RANGE \
  --billing-mode PAY_PER_REQUEST
aws dynamodb put-item  --table-name Orders --item '{"customerId":{"S":"C-1"},"orderId":{"S":"O-9"}}'
aws dynamodb query     --table-name Orders \
  --key-condition-expression 'customerId = :c' \
  --expression-attribute-values '{":c":{"S":"C-1"}}'
aws dynamodb describe-table --table-name Orders

# RDS
aws rds describe-db-instances \
  --query 'DBInstances[].{ID:DBInstanceIdentifier,Engine:Engine,Class:DBInstanceClass,MultiAZ:MultiAZ,Public:PubliclyAccessible}' \
  --output table
aws rds describe-db-snapshots --db-instance-identifier mydb
aws rds create-db-snapshot --db-instance-identifier mydb --db-snapshot-identifier mydb-manual
```
