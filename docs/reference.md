# Reference

Part of [Get started with Clumio on AWS](../README.md).

## Terms

See [Words you'll see](words.md).

## Not covered

EC2 and EBS protection (`"ebs"` creates only its IAM), DynamoDB, Iceberg, SQL Server on EC2, and SecureVault Archive for S3.

## Clumio documentation

- [Getting started with the Clumio provider](https://registry.terraform.io/providers/clumio-code/clumio/latest/docs/guides/getting_started): Clumio's one-file quick start, for a sandbox.
- [IAM permissions required to deploy](https://documentation.commvault.com/clumio/iam_permissions_required_to_deploy_clumio_service.html): Clumio's deploy permissions, to compare with step 0.
- [Permissions file details](https://documentation.commvault.com/clumio/permissions_file_details.html): why each role and permission exists.
- [Inventory](https://documentation.commvault.com/clumio/inventory.html): what Clumio found, and its protection status.
- [Best practices](https://documentation.commvault.com/clumio/best_practices_for_clumios_platform.html): tags, access and monitoring.

## Changing this repository

Run `./check.sh` before every commit. It checks formatting and validation, confirms the placeholders stop a plan, and compares step 0's output with known-good copies.
