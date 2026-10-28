# For AI agents, and anyone changing this repository

This repository sets Clumio up on AWS with Terraform, and teaches recovery with a hands-on workshop. Its readers are people. You help them in one of three ways:

1. **Run the workshop** with a person. Go to [workshops/orders-recovery/AGENTS.md](workshops/orders-recovery/AGENTS.md). Its rules apply there, on top of these.
2. **Help a person run steps 0 to 2** on their own account. Each step's README is the procedure. The rules below keep it safe.
3. **Change the repository.** See [Changing this repository](#changing-this-repository).

## Map

| Path | What it is |
|---|---|
| `README.md` | The spine: the story, the order of the steps, and Before you begin (tools, token, API URL) |
| `0-iam-preview/` to `2-protect-rds/` | The steps, one folder each. Each sets values in `terraform.tfvars` and calls a module |
| `modules/` | The logic, once: the connection, S3 protection, RDS and Aurora protection |
| `tools/record-restore/` | Puts a Clumio record-restore CSV back into any Aurora MySQL table, checked first. Its README has the rules for agents |
| `workshops/orders-recovery/` | The workshop: Terraform, the `lab` command, and its module pages in `docs/` |
| `docs/` | The kit's guides: `words.md` (the one glossary) and `operate.md` |
| `SECURITY.md` | What Clumio can do in an account, and the one record of what is proven live |

## Rules for every task

1. **Plan, then ask, then apply the saved plan.** Run `terraform plan -out=tfplan`, show the person the plan, and wait for their go. Then run `terraform apply tfplan`. Never use `-auto-approve`. One go covers one apply.
2. **The person names the account.** `account_id` and `region` in each `terraform.tfvars` come from the person, never from a guess. Step 2 has no AWS sign-in, so it can't check the account: on a shared Clumio tenant, a wrong `account_id` that another team connected would protect their account, and change its databases' PITR window.
3. **Never set `i_understand_byok_is_permanent` in step 1b.** Only the person sets it, after reading `1b-own-key/README.md`. BYOK binds the whole Clumio tenant to one key and one account, for good.
4. **Never print a secret.** Don't print `CLUMIO_API_TOKEN` or other environment variables. Showing `terraform plan` output is fine, but never open a `*.tfstate` or `tfplan` file, or run `terraform show`: they hold secrets in plain text, such as the ExternalIds Clumio uses to assume its roles. The person exports the token in the shell that starts you.
5. **Keep users' state working.** People's local Terraform state lives in the step folders, at the addresses the code names. Never rename a step folder, and never remove a `moved` block.
6. **The person does the console steps:** the Clumio console, AWS sign-in, and creating the token.

## Changing this repository

**Verify with `./check.sh`.** It ends with `ALL CHECKS PASS`. It needs Terraform 1.7 or later and the Terraform registry, and takes a few minutes. It never calls AWS or Clumio, so it proves offline behavior only. When it's all that ran, say "tested offline". For the workshop alone, run `python3 -m unittest discover -s tests` in `workshops/orders-recovery`.

**Tests come first.** Write the test, watch it fail, then change the code. Take expected values from an independent truth, such as a saved real output, never from the code under test.

**Prove it live again before each minor release.** Run the workshop end to end in a test account, and update the dates in `SECURITY.md`, "What is proven, and what isn't". If a part can't run live, say so there before you release. A patch that changes only docs needs no live run.

**Step 0's expected output is what a security team reviewed.** Run `0-iam-preview/test/test.sh --update` only after the person has reviewed the diff.

**Keep versions locked.** Use `terraform init -lockfile=readonly`. Upgrade only on purpose, as in [docs/operate.md](docs/operate.md#on-purpose).

**Git.** The remote is public. Commit only when the person asks, stage named paths, and never push without their go. Never commit `terraform.tfvars`, state, `.lab/`, or an account ID: examples use `123456789012` or `111122223333`.

**Names are unique in their scope:** the account and Region for AWS resources, the tenant for Clumio, and the world for S3 buckets. The workshop's names live in `workshops/orders-recovery/names.json`. A name with a wider scope carries `{account}` and `{region}`, which Terraform and `lab` fill in. Code may add a suffix inside one account, such as a subnet's number, but never composes a name with a wider scope. The kit's modules name their policies `rds-<account>-<region>` and `s3-<account>-<region>`, unless a step sets `name`. Where a list keeps old entries under the same name, as Clumio does, the code verifies what was picked. Code deletes only what carries the workshop tag, never by name alone.

**Write the docs like a book:**

- Each fact lives in one place. Elsewhere, link to it.
- Every claim traces to the code or to a live run. What isn't proven says so, where the reader sees it. `SECURITY.md` keeps the one record of what is proven.
- Full, short sentences. One idea per paragraph. One term per concept, as in `docs/words.md`. No em dashes. In the workshop, every step is numbered, and says what you should see.
