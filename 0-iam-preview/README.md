# Step 0: Preview the IAM

Part of [Get started with Clumio on AWS](../README.md). Set up your terminal as in [Before you begin](../README.md#before-you-begin) first.

**What it does.** Shows every IAM role, policy and permission step 1 will create, and checks that your deploy role may create them. Nothing is created.

**What you need.** First create step 1's settings: in `1-connect-clumio`, run `cp terraform.tfvars.example terraform.tfvars`, then edit it. Step 0 reads that file, and so does step 1, so what you preview is what you get.

- `account_id` and `region`: the account and Region to connect.
- `iam_prefix` and `iam_path`: your naming rule. If roles must start with `platform-`, set `iam_prefix = "platform-clumio"` and `iam_path = "/"`.
- `workloads`: what Clumio may protect. Start with `["s3"]`; add `"rds"` for RDS and Aurora.
- Only if your organization requires them: `role_tags`, `permissions_boundary_arn`, `pass_role_deny_list`. See SECURITY.md.

**Before you run it.** In a sandbox where you're an administrator, step 0 is optional; step 1's plan shows the same resources. In a company account, don't skip it.

**Run it.**

```bash
cd 0-iam-preview
./preview.sh --as arn:aws:iam::<account>:role/<your deploy role>
```

Without `--as`, it checks your own login.

**What you should see.** A summary, and a folder `clumio-iam-preview-<region>-<time>` for your security team. The last line is the answer:

- **READY**: the deploy role can create everything. Go to step 1.
- **BLOCKED**: lists each missing permission. Replace `<ACCOUNT_ID>` in the folder's `policies/deploy-role-policy.json`, grant it to the deploy role, and run step 0 again.
- **CANNOT CHECK**: you're the root user, or can't run the check. Ask someone who can to run it with `--as`.

**If something goes wrong.** *AWS account ID not allowed* means you're signed in to another account. For other errors, see [When something goes wrong](../docs/operate.md#when-something-goes-wrong).

## Options

```bash
./preview.sh                                    # checks your own login
./preview.sh --as <deploy role ARN>             # checks that role instead
./preview.sh --connect /path/to/1-connect-clumio
```

It reads step 1's own `terraform.tfvars` (copied from its `terraform.tfvars.example`), variables, versions, lock file and module version, so the preview matches what step 1 creates. Change a setting there, and run it again. Sign in to the `account_id` in that file.

You need Terraform 1.5 or later, Python 3 and the AWS CLI. No Clumio token.

## What it writes

Each run writes a folder, `clumio-iam-preview-<region>-<time>/`:

- `summary.md`: everything on one page. Your settings, what the deploy role needs, highlights to read first, roles and who can assume them, policies, the SNS topic policy, all actions, and the check result.
- `policies/`: every trust, managed, inline and resource policy, as JSON.
- `policies/deploy-role-policy.json`: the deploy role's policy. Replace `<ACCOUNT_ID>` before attaching it.

To compare two runs, such as before and after a module upgrade: `diff -r <old>/policies <new>/policies`.

## The check

It asks AWS's IAM policy simulator whether the deploy role may perform every action on every role, policy, topic and rule step 1 creates. It sends what step 1 sends: the Region, role tags, permissions boundary and each attached policy's name. The simulator weighs the role's policies, its boundary and your service control policies (SCPs).

- **READY**: every action is allowed.
- **BLOCKED**: lists each denied action and its ARN. *implicitDeny* means nothing grants it; *explicitDeny* means a policy or SCP denies it.
- **CANNOT CHECK**: you're the root user, you lack `iam:SimulatePrincipalPolicy`, or, with SSO, you can't read your role with `iam:GetRole`.

The simulator can't see resource control policies, or SCP conditions beyond Region, tags, boundary and policy name. READY is strong evidence; the deploy role's first apply is the proof.

## Why it's safe to run

- It only runs `terraform plan`, in a temporary folder it deletes, so there's nothing to apply.
- Its Clumio provider points at an address that doesn't exist, so it never reaches Clumio.
- It only reads from AWS: your account ID, Region and the simulator.
- It masks your account ID as `<ACCOUNT_ID>`. If the real ID appears, or the run stops early, it deletes the output and fails.
- A policy it can't reproduce exactly makes it fail, rather than show a partial policy.
- It refuses to run if `versions.tf` holds a backend. Keep the backend in `backend.tf`.

## Placeholders in the output

Some values only exist once you connect:

| Placeholder | Stands for | Real value comes from |
|---|---|---|
| `<ACCOUNT_ID>` | Your AWS account | You |
| `<CLUMIO_AWS_ACCOUNT_ID>` | Clumio's AWS account, in trust policies | Clumio, at connect |
| `<CLUMIO_DATA_PLANE_ACCOUNT_ID>` | Clumio's account that holds your backups; the only one S3 copies may go to | Clumio, at connect |
| `<EXTERNAL_ID>` | Your ExternalId, in trust policies | Clumio, at connect |
| `<CLUMIO_TOKEN>` | The connection token, in some names | Clumio, at connect |
| `<ARN(s) of resources created in the same run>` | Roles, topics or rules this setup creates | Step 1 |

## How it's built

`preview.sh` builds a temporary configuration from step 1's files, runs the plan and the check. `extract.py` turns the plan into `summary.md` and `policies/`, reading only the plan file. `test/test.sh` runs `extract.py` on two saved plans, one regulated and one with shipped defaults, and compares the output with known-good copies. Run it after any change here.

What's been tested live is in [SECURITY.md](../SECURITY.md#what-is-proven-and-what-isnt).

**Next:** [Step 1](../1-connect-clumio/README.md).
