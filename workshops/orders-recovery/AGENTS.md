# For AI agents running this workshop

You help a person run this workshop in their test AWS account. You run the `./lab` and Terraform commands. The person does every step in the Clumio console, and approves every deletion. The module pages in `docs/` are the full guide. This page tells you how to run them safely.

## Rules

1. **Use the test account in `terraform.tfvars` only.** Every `./lab` command checks that the signed-in account matches it, and stops if it doesn't. Never edit `account_id` or `region` to get past that stop. Ask the person instead.
2. **Ask before every deletion.** `./lab break deploy`, `./lab drop`, `./lab break everything`, and `./lab down` delete things. Before each one, tell the person what it deletes (its module page lists it), and wait for their go. One go covers one command. `break everything` and `down` can't be undone, so they ask for the account ID. Ask the person to type it in chat as their go, and pass exactly that with `--confirm-account`. Never copy it from `terraform.tfvars` or another file.
3. **Never run `terraform destroy` yourself.** `./lab down` deletes what Terraform doesn't know about first, then runs it.
4. **Keep secrets out of sight.** The person exports `CLUMIO_API_TOKEN`, `CLUMIO_API_BASE_URL` and `AWS_PROFILE` in the shell that starts you, before you start (`docs/0-setup.md`, "Start a session"). Many agent shells start fresh for every command, so a variable set later can be lost. Never ask for the token in chat, print it, or write it to a file. Never read `terraform.tfstate`, `tfplan` or `terraform show`: they hold the database password and Clumio's ExternalId. If Clumio refuses the token mid-run, ask the person to exit you, start a session again, and restart you: a variable exported in another terminal never reaches you.
5. **Run one command at a time, and show its full output.** Don't cut the output with `tail` or `head`, and don't chain a deletion after another command. The person must see each step. `./lab break everything`, `./lab prepare` and `./lab down` can run longer than 10 minutes: run them in the background, wait for each to end, and never start a second copy while one runs.
6. **Never edit `lab`, the Terraform files, or `names.json` during a run.** If something looks wrong, stop and tell the person.
7. **Run `terraform apply` only in Module 1, before any incident.** After an incident and a restore, the account no longer matches what Terraform built, and an apply could replace the restored database. If `./lab status` names another policy's rule, the fix in `docs/reference.md` needs an apply: do it only before `./lab break deploy`. The person sets `rds_rule_before_id`, or you do after their go. Every apply is `terraform plan -out=tfplan`, the person's go, then `terraform apply tfplan`, even where a page or `./lab` says `terraform apply`.

## How to read a result

- A line starting with `STOP:` (on stderr, exit code 1) means the command stopped. Read what it already did, in the lines above. The message names what to fix. Tell the person, then look it up in `docs/reference.md`, "Troubleshooting". Never retry a deletion in a loop.
- A Clumio task ID can arrive before the task is done. Before you check the data, ask the person to confirm in the Clumio console that the task completed.
- `./lab check` ends with `HEALTHY` (exit code 0) or `BROKEN` (exit code 1). After an incident, `BROKEN` is the expected result, not an error.
- Clumio takes time. Its first recovery points can take hours, Backtrack's first sync and the archive's preparation up to 48 hours each. A rebuilt bucket can take an hour to appear in Clumio. While you wait, run `./lab status` at most every 15 minutes, and tell the person what you're waiting for.

## The run, in order

| Module | Who | What | You should see |
|---|---|---|---|
| 0 | You | `./lab preflight` | `READY` |
| 1 | You, with the person's go | `terraform init`, `terraform plan -out=tfplan`, then `terraform apply tfplan` | `Seeded 1,000 orders`, then `Apply complete!` |
| 1 | You | `./lab check` | `HEALTHY` |
| 1 | You | `./lab portal`, left running in the background. The person opens http://localhost:8080 | `portal: open http://localhost:8080` |
| 1 | You | `./lab status`, until it says ready | `ready for the incidents  yes` |
| 1 | Person | Opens the archive recovery point in the Clumio console, and prepares it if Clumio asks | Record restore opens, or Clumio emails when it's ready |
| 1 | Person | Checks the bucket's **Backtrack** tab. Don't start Module 2 before it shows a Last sync: `./lab status` can't see it, and Module 3 needs it | **Last sync** with a date and time |
| 2 | You, with the person's go | `./lab break deploy`. Tell the person the change time it prints | `Bad deployment at <time> UTC` |
| 2 | You | `./lab check` | `BROKEN`, with 100 orders missing and 50 documents changed |
| 3 | Person | Backtrack in the Clumio console | The person gives you the task ID |
| 3 | You | `./lab check` | `BROKEN`, with 0 documents changed |
| 4A | Person | Record restore in the Clumio console. Gives you the CSV's path | The path of a `.csv` file |
| 4A | You | `./lab repair --from-csv <path>`, then `./lab check` | `Copied 100 of 100`, then `HEALTHY` |
| 4B | Person | Restores `orders-db-restore` in the Clumio console | The person gives you the task ID |
| 4B | You | `./lab prepare orders-db-restore`, then `./lab repair --from orders-db-restore` | `answers SQL`, then `No orders are missing`. If 4A was skipped: `Copied 100 of 100`, then run `./lab check`: `HEALTHY` |
| 4B | You, with the person's go | `./lab drop orders-db-restore` | `orders-db-restore deleted` |
| 5 | You, with the person's go | `./lab break everything --confirm-account <account ID>`, then `./lab check` | `Everything is gone`, then `BROKEN` |
| 5 | Person | Restores the database as `orders-db` in the Clumio console | The person gives you the task ID |
| 5 | You | `./lab prepare orders-db`, then `./lab rebuild` | `answers SQL`, then `recreated, empty and tagged` |
| 5 | Person | Restores the documents into the rebuilt bucket in the Clumio console | The person gives you the task ID |
| 5 | You | `./lab check` | `HEALTHY` |
| 6 | You | `./lab report` | The scorecard, and `.lab/report.html` |
| 7 | You, with the person's go | Stop the portal, then `./lab down --confirm-account <account ID>` | `DONE: the workshop is gone` |

Each module page says what each check should show, line by line. When a result differs from the page, stop and tell the person before you go on.
