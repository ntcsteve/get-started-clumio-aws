# Words you'll see

Part of [Get started with Clumio on AWS](../README.md). New to AWS or Clumio? Read this first. Each word is explained in plain terms.

## AWS

| Word | Meaning |
|---|---|
| AWS account | Your own space in AWS. Everything you create, and its bill, belongs to one account. |
| Test account | An AWS account with no real data, used to try things safely. |
| Region | Where AWS runs your resources, such as ap-southeast-1 (Singapore). |
| AWS Management Console | AWS's website, where you see and change your resources. |
| AWS CLI | AWS's command-line tool. The workshop's commands use it. |
| ARN | A resource's full name in AWS, such as `arn:aws:iam::123456789012:role/name`. |
| IAM role | A set of permissions that a person or a service can use. |
| Amazon S3 | AWS's file storage. Files live in buckets. |
| S3 Versioning | S3 keeps every earlier version of a file when it changes, so you can go back to one. |
| Prefix | The start of a file's name in S3, such as `documents/`. It works like a folder. |
| Amazon Aurora | AWS's managed database, compatible with MySQL. A cluster holds the data; an instance runs the queries. |
| Point-in-time recovery (PITR) | AWS's own backup of a database, kept for a few days inside your account. The Clumio console calls it AWS automated backups. |
| AWS KMS key | An encryption key that AWS keeps for you. |
| Terraform | A tool that creates cloud resources from code, so the same code builds the same thing every time. |
| Plan, apply | Terraform's two moves: `plan` shows what will change, and `apply` makes the change after you enter `yes`. |
| NULL | A database value that means "no value". It differs from empty text. |

## Clumio

| Word | Meaning |
|---|---|
| Clumio | A service that keeps copies of your AWS data apart from your account, and brings them back when you need them. |
| Tenant | Your organization's own space in Clumio. |
| Connection | Clumio's link to one AWS account and Region. |
| Clumio policy | What Clumio protects, how often, and how long it keeps each copy. Not an IAM policy. |
| Tag | A label on an AWS resource, such as `clumio-protection = orders`. A policy can protect everything with a tag. |
| Protection rule | Which databases a Clumio policy applies to, by tag or by name. |
| Protection group | A list of S3 buckets that one Clumio policy protects. |
| Recovery point | One copy of your data at one moment, which you can recover from. Clumio's console calls it a backup. |
| SecureVault | Clumio's storage for copies: air-gapped (kept apart from your account) and immutable (can't be changed). |
| SecureVault Standard | Daily copies, kept days or weeks. Restores a whole database or bucket. |
| Tier | Where Clumio keeps a recovery point, and for how long: SecureVault Standard or SecureVault Archive. |
| SecureVault Archive | Monthly copies, kept longer at lower cost. Answers SQL questions, and returns selected rows. |
| Backtrack | Rolls an S3 bucket back in place, to a point in time up to its last daily sync, from the bucket's own object versions. |
| Restore | Brings data back from a recovery point. For a database, Clumio makes a new cluster or instance with the name you choose: beside the original, or under the original's name once it's gone. |
| Way back | One way to recover from one kind of incident, such as Backtrack or a full restore. [Choose the way back](operate.md#choose-the-way-back) lists them. |
| Record restore | SQL on an Archive recovery point. It returns only the rows you ask for, as a CSV file. |
| BYOK | Bring your own key: Clumio encrypts its copies with your AWS KMS key. Optional, and permanent. |

## This repository

| Word | Meaning |
|---|---|
| Step | One folder of the kit, such as `1-connect-clumio`. You run them in order. |
| Deploy role | The AWS identity that runs step 1 and creates Clumio's IAM roles. |
| `terraform.tfvars` | Your settings for a step. You copy it from `terraform.tfvars.example`. |
| `./lab` | The workshop's command. Every command checks first, and says what to do next. |
| Deployment ID | A short random ID that `./lab seed` writes into the database. `./lab status` shows it, and `./lab check` uses it to tell this run's copy from an older one. |
| HEALTHY or BROKEN | What `./lab check` says: whether every order is there, unchanged, with its intact document. |
| Control order | Order 1. The bad deployment doesn't touch it, so a correct recovery leaves it unchanged. |
| Change time | The time the workshop's bad deployment ran. You recover to a point before it. |
| Schema | A database's tables, columns, types and indexes. `./lab check` compares it after every restore. |
| Scorecard | Each incident, its damage, and the time back to HEALTHY. `./lab report` shows it. |
