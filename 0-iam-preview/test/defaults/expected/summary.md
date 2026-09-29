# Clumio IAM preview: ap-southeast-2

What Clumio's Terraform module `aws-template` v0.41.0 creates in account `<ACCOUNT_ID>`, rendered by `terraform plan` (nothing was created).

Settings: prefix `(Clumio default names)`, IAM path `/clumio/`, workloads `s3`.

Role tags `{'Vendor': 'Clumio'}`; permissions boundary `none`; pass-role deny list: 0 role(s).

`<CLUMIO_TOKEN>`, `<EXTERNAL_ID>`, `<CLUMIO_AWS_ACCOUNT_ID>`, `<CLUMIO_DATA_PLANE_ACCOUNT_ID>` are issued by Clumio when you connect.

## What the deploy role needs

The identity that runs Terraform needs all of these: create, read, update and destroy (from CloudTrail on live runs), plus tagging and boundary actions. The policy is `policies/deploy-role-policy.json`.

> **Before attaching it,** replace `<ACCOUNT_ID>` with your account ID: `sed 's/<ACCOUNT_ID>/123456789012/g' policies/deploy-role-policy.json`

| What | Actions | Resource | Condition |
| --- | --- | --- | --- |
| Manage roles and their inline policies | `iam:TagRole, iam:UntagRole, iam:ListRoleTags, iam:GetRole, iam:DeleteRole, iam:ListRolePolicies, iam:ListAttachedRolePolicies, iam:ListInstanceProfilesForRole, iam:PutRolePolicy, iam:GetRolePolicy, iam:DeleteRolePolicy, iam:UpdateAssumeRolePolicy, iam:UpdateRole, iam:DeleteRolePermissionsBoundary` | `arn:aws:iam::<ACCOUNT_ID>:role/clumio/Clumio*` | none |
| Create roles | `iam:CreateRole, iam:PutRolePermissionsBoundary` | `arn:aws:iam::<ACCOUNT_ID>:role/clumio/Clumio*` | none |
| Attach Clumio-named policies to those roles | `iam:AttachRolePolicy, iam:DetachRolePolicy` | `arn:aws:iam::<ACCOUNT_ID>:role/clumio/Clumio*` | `{"ArnLike": {"iam:PolicyARN": ["arn:aws:iam::<ACCOUNT_ID>:policy/ClumioS3EbPolicy-*", "arn:aws:iam::<ACCOUNT_ID>:policy/clumio/Clumio*"]}}` |
| Managed policies | `iam:CreatePolicy, iam:GetPolicy, iam:GetPolicyVersion, iam:ListPolicyVersions, iam:CreatePolicyVersion, iam:DeletePolicyVersion, iam:DeletePolicy` | `arn:aws:iam::<ACCOUNT_ID>:policy/ClumioS3EbPolicy-*, arn:aws:iam::<ACCOUNT_ID>:policy/clumio/Clumio*` | none |
| SNS topic | `sns:CreateTopic, sns:GetTopicAttributes, sns:SetTopicAttributes, sns:ListTagsForResource, sns:DeleteTopic` | `arn:aws:sns:ap-southeast-2:<ACCOUNT_ID>:ClumioInventoryTopic_*` | none |
| EventBridge rules and targets | `events:PutRule, events:DescribeRule, events:ListTagsForResource, events:PutTargets, events:ListTargetsByRule, events:RemoveTargets, events:DeleteRule` | `arn:aws:events:ap-southeast-2:<ACCOUNT_ID>:rule/Clumio*` | none |

## Review before approving

Highlights found in the policies below. Read every file in `policies/` before approving.

- IAM path: `ClumioS3EbPolicy-<ACCOUNT_ID>-ap-southeast-2-<CLUMIO_TOKEN>` is created at `/`, not at iam_path `/clumio/` (Clumio's module doesn't apply iam_path to it). A path rule needs an exception
- KMS: can use ANY key whose key policy lets IAM grant access (needed for encrypted data)
- S3 read: objects in any bucket it can reach, including other accounts' buckets whose bucket policy allows it
- S3 write + delete: objects in every bucket in this account (restores)
- S3: can change a bucket's event notifications and inventory configuration
- S3 copy out: only to clumio-s3-backup* buckets in Clumio's data plane account
- At runtime: creates EventBridge rules clumio-s3-event-rule-* in this account
- At runtime: creates S3 Storage Lens configurations clumio-storage-lens-*
- Sends events and messages to Clumio's event bus and queues
- IAM PassRole: to a role this setup creates
- Support: can open, read and update AWS Support cases in this account, and read Trusted Advisor results
- SNS topic policy: SNS:Publish by any principal, only if AWS:SourceAccount = <ACCOUNT_ID>
- SNS topic policy: SNS:Subscribe by arn:aws:iam::<CLUMIO_AWS_ACCOUNT_ID>:root
- SNS topic policy: SNS:ListSubscriptionsByTopic by arn:aws:iam::<CLUMIO_AWS_ACCOUNT_ID>:root
- SNS topic policy: SNS:Publish by events.amazonaws.com, only if AWS:SourceAccount = <ACCOUNT_ID>

## Roles

| Role | Path | Who can assume it | Managed policies | Inline policies |
| --- | --- | --- | --- | --- |
| `ClumioIAMRole-ase-2-<CLUMIO_TOKEN>` | `/clumio/` | arn:aws:iam::<CLUMIO_AWS_ACCOUNT_ID>:role/ClumioCustomerProtectRole + sts:ExternalId | `ClumioBaseManagedPolicy-ap-southeast-2-<CLUMIO_TOKEN>`, `ClumioS3BackupPolicy-ap-southeast-2-<CLUMIO_TOKEN>`, `ClumioS3RestorePolicy-ap-southeast-2-<CLUMIO_TOKEN>` | `ClumioDriftDetectPolicy-ap-southeast-2-<CLUMIO_TOKEN>`, `ClumioInventoryPolicy-ap-southeast-2-<CLUMIO_TOKEN>`, `ClumioKMSPolicy-ap-southeast-2-<CLUMIO_TOKEN>` |
| `ClumioS3EbRole-ase-2-<CLUMIO_TOKEN>` | `/clumio/` | events.amazonaws.com + AWS:SourceAccount | `ClumioS3EbPolicy-<ACCOUNT_ID>-ap-southeast-2-<CLUMIO_TOKEN>` | none |
| `ClumioSuppt-ap-southeast-2-<CLUMIO_TOKEN>` | `/clumio/` | arn:aws:iam::<CLUMIO_AWS_ACCOUNT_ID>:role/ClumioCustomerSupportRole + sts:ExternalId | none | `ClumioSupportPolicy-ap-southeast-2-<CLUMIO_TOKEN>` |

## Policies

| Policy | Kind | Path | Actions | Broad resource (`*`, all S3, any KMS key) | File |
| --- | --- | --- | --- | --- | --- |
| `ClumioBaseManagedPolicy-ap-southeast-2-<CLUMIO_TOKEN>` | managed | `/clumio/` | 5 | yes | `policies/managed--ClumioBaseManagedPolicy-ap-southeast-2-CLUMIO_TOKEN.json` |
| `ClumioS3BackupPolicy-ap-southeast-2-<CLUMIO_TOKEN>` | managed | `/clumio/` | 23 | yes | `policies/managed--ClumioS3BackupPolicy-ap-southeast-2-CLUMIO_TOKEN.json` |
| `ClumioS3EbPolicy-<ACCOUNT_ID>-ap-southeast-2-<CLUMIO_TOKEN>` | managed | `/` | 2 | no | `policies/managed--ClumioS3EbPolicy-ACCOUNT_ID-ap-southeast-2-CLUMIO_TOKEN.json` |
| `ClumioS3RestorePolicy-ap-southeast-2-<CLUMIO_TOKEN>` | managed | `/clumio/` | 10 | yes | `policies/managed--ClumioS3RestorePolicy-ap-southeast-2-CLUMIO_TOKEN.json` |
| `ClumioDriftDetectPolicy-ap-southeast-2-<CLUMIO_TOKEN>` | inline | - | 17 | no | `policies/inline--ClumioDriftDetectPolicy-ap-southeast-2-CLUMIO_TOKEN.json` |
| `ClumioInventoryPolicy-ap-southeast-2-<CLUMIO_TOKEN>` | inline | - | 25 | yes | `policies/inline--ClumioInventoryPolicy-ap-southeast-2-CLUMIO_TOKEN.json` |
| `ClumioKMSPolicy-ap-southeast-2-<CLUMIO_TOKEN>` | inline | - | 5 | yes | `policies/inline--ClumioKMSPolicy-ap-southeast-2-CLUMIO_TOKEN.json` |
| `ClumioSupportPolicy-ap-southeast-2-<CLUMIO_TOKEN>` | inline | - | 14 | yes | `policies/inline--ClumioSupportPolicy-ap-southeast-2-CLUMIO_TOKEN.json` |

## Resource policies

| Resource | File |
| --- | --- |
| SNS topic `ClumioInventoryTopic_<CLUMIO_TOKEN>` | `policies/resource--ClumioInventoryTopic_CLUMIO_TOKEN.json` |

## Other resources

| Type | Name |
| --- | --- |
| `aws_cloudwatch_event_rule` | `ClumioS3AWSBackupCWRule_<CLUMIO_TOKEN>` |
| `aws_cloudwatch_event_rule` | `ClumioS3CloudtrailEventRule_<CLUMIO_TOKEN>` |
| `aws_cloudwatch_event_rule` | `ClumioTagCloudwatchRule_<CLUMIO_TOKEN>` |
| `aws_sns_topic` | `ClumioInventoryTopic_<CLUMIO_TOKEN>` |

## All actions, by service

- **account**: GetRegionOptStatus, ListRegions
- **backup**: DescribeRecoveryPoint, ListBackupVaults, ListProtectedResources, ListRecoveryPointsByBackupVault
- **cloudwatch**: GetMetricStatistics
- **events**: DeleteRule, DescribeEventBus, DescribeRule, ListTagsForResource, ListTargetsByRule, PutEvents, PutRule, PutTargets, RemoveTargets
- **iam**: GetContextKeysForPrincipalPolicy, GetRole, GetRolePolicy, GetServiceLinkedRoleDeletionStatus, ListAccountAliases, ListAttachedRolePolicies, ListInstanceProfilesForRole, ListRolePolicies, ListRoleTags, PassRole, SimulatePrincipalPolicy
- **kms**: Decrypt, DescribeKey, Encrypt, GenerateDataKey*, ReEncrypt*
- **organizations**: DescribeOrganization
- **s3**: AbortMultipartUpload, DeleteObject, DeleteStorageLensConfiguration, GetBucketLocation, GetBucketLogging, GetBucketNotification, GetBucketObjectLockConfiguration, GetBucketPolicy, GetBucketPublicAccessBlock, GetBucketTagging, GetBucketVersioning, GetEncryptionConfiguration, GetInventoryConfiguration, GetLifecycleConfiguration, GetMetricsConfiguration, GetMultiRegionAccessPoint, GetObject, GetObjectTagging, GetObjectVersion, GetObjectVersionTagging, GetReplicationConfiguration, GetStorageLensConfiguration, GetStorageLensConfigurationTagging, ListAllMyBuckets, ListBucket, ListBucketMultipartUploads, ListBucketVersions, ListMultiRegionAccessPoints, ListStorageLensConfigurations, PutBucketNotification, PutInventoryConfiguration, PutObject, PutObjectAcl, PutObjectTagging, PutStorageLensConfiguration, PutStorageLensConfigurationTagging
- **sns**: GetDataProtectionPolicy, GetTopicAttributes, ListSubscriptionsByTopic, ListTagsForResource
- **sqs**: SendMessage
- **sts**: DecodeAuthorizationMessage
- **support**: AddAttachmentsToSet, AddCommunicationToCase, CreateCase, DescribeAttachment, DescribeCases, DescribeCommunications, DescribeCreateCaseOptions, DescribeServices, DescribeSeverityLevels, DescribeSupportedLanguages, DescribeTrustedAdvisorCheckRefreshStatuses, DescribeTrustedAdvisorCheckResult, DescribeTrustedAdvisorCheckSummaries, DescribeTrustedAdvisorChecks
