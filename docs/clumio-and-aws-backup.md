# Clumio and AWS Backup

Part of [Get started with Clumio on AWS](../README.md), after [Why Clumio](../README.md#why-clumio).

Both can keep copies out of reach of your account. AWS Backup's logically air-gapped vault holds them in an account AWS owns, locked in compliance mode. Clumio's SecureVault holds them outside your organization's security domain. Where they differ, from each one's documentation:

| | AWS Backup | Clumio |
|---|---|---|
| Roll an S3 bucket back in place | A restore doesn't replace objects that exist, or delete objects added since | Backtrack rolls a bucket or prefix back in place, from its own versions |
| What an S3 restore can bring back | A whole bucket, or up to 5 objects or folders per restore job | An object, a prefix, or whole buckets |
| Aurora in the air-gapped tier | Snapshot backups only; continuous backups aren't supported there | SecureVault Standard and Archive |
| A few Aurora records back | Not documented: a restore brings back the whole cluster | SQL on an archive recovery point returns only the matching rows, as a CSV file |
| Point in time | Continuous backup for S3 and Aurora, up to 35 days | AWS point-in-time recovery, which Clumio sets, plus SecureVault copies on its schedule |
| Many accounts | AWS Organizations backup policies | CloudFormation StackSets, across an organization, its OUs, or a set of accounts |

AWS Backup alone can be enough when whole-bucket or whole-cluster restores meet your recovery time, 35 days of point in time plus snapshots covers your retention, and you don't need records back without a full restore, or a bucket rolled back in place. For a database, let either AWS Backup's continuous backup or Clumio manage point-in-time recovery, not both: Clumio's documentation says to use one or the other.
