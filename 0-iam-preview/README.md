# Clumio IAM preview

Shows every IAM role, policy and permission `1-connect-clumio` would create, **before anything is
created**, and whether the deploy role may create them. Give the output to your security team.

```bash
./preview.sh                                    # uses ../1-connect-clumio, checks your login
./preview.sh --as <deploy role ARN>             # checks that role instead
./preview.sh --connect /path/to/1-connect-clumio
```

It uses step 1's own `terraform.tfvars`, `variables.tf`, `versions.tf`, lock file and module
version, so the preview matches what step 1 creates. Log in to the `account_id` in that file.
Changed a setting? Run it again.

Output folder `clumio-iam-preview-<region>-<time>/`:

| File | Holds |
|---|---|
| `summary.md` | Settings, what the deploy role needs, highlights, roles, policies, the SNS topic policy, every action, the check result |
| `policies/*.json` | Every trust, managed, inline and resource policy |
| `policies/deploy-role-policy.json` | The deploy role's policy. Replace `<ACCOUNT_ID>` before attaching it |

Compare two runs: `diff -r <old>/policies <new>/policies`

## The check

AWS's IAM policy simulator evaluates the deploy role's policies, boundary and SCPs for every
role, policy, topic and rule, with the context step 1 sends: Region, role tags, permissions
boundary, attached policy ARN.

| Result | Meaning |
|---|---|
| READY | Every action is allowed |
| BLOCKED | Lists each denied action and ARN (`implicitDeny`: not granted; `explicitDeny`: denied by a policy or SCP) |
| CANNOT CHECK | Root login, no `iam:SimulatePrincipalPolicy`, or (SSO) no `iam:GetRole` on your role |

It can't see resource control policies or other condition keys your SCPs test. READY is strong
evidence; the first apply by the deploy role is the proof.

## Why it's safe

- `terraform plan` only, in a throwaway folder: nothing to apply.
- Its Clumio provider points at `https://preview.invalid`: it never reaches Clumio.
- AWS access is read-only: your account ID, Region, and the simulator.
- Your account ID is masked (`<ACCOUNT_ID>`). If one is found unmasked, or the run stops early,
  the output is deleted.
- A policy form it can't render exactly makes it fail, not show a partial policy.
- It refuses a backend in `versions.tf` (keep it in `backend.tf`).

Needs Terraform 1.5+, python3, the AWS CLI. No Clumio token.

## Files

| File | Job |
|---|---|
| `preview.sh` | Builds a throwaway config from step 1, runs `terraform plan`, calls `extract.py`, runs the check |
| `extract.py` | Turns the plan into `summary.md` and `policies/`. Reads only the plan file |
| `test/test.sh` | Runs `extract.py` on two saved plans (`regulated/`, shipped `defaults/`) and compares with `expected/` |

## Placeholders in the output

| Placeholder | What it is | Filled by |
|---|---|---|
| `<ACCOUNT_ID>` | Your AWS account | You |
| `<CLUMIO_AWS_ACCOUNT_ID>` | Clumio's account, in the trust policies | Clumio, at connect |
| `<CLUMIO_DATA_PLANE_ACCOUNT_ID>` | Clumio's account holding your backups; the only one S3 copies may go to | Clumio, at connect |
| `<EXTERNAL_ID>` | Your ExternalId | Clumio, at connect |
| `<CLUMIO_TOKEN>` | The connection token, in some names | Clumio, at connect |
| `<ARN(s) of resources created in the same run>` | Roles, topics or rules this setup creates | Step 1 |

## Checked live

- S3, and S3 + RDS (module 0.41.0): names matched the IAM step 1 created. EC2/EBS: rendered only.
- The IAM simulator allows every check against `deploy-role-policy.json`, at the shipped defaults
  and with prefix, boundary and tags (2026-09). BLOCKED for a role without it.
