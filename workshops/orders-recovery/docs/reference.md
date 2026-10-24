# Reference

## Choose the way back

Start from what happened. Backtrack works in place. Every other way back gives you a new database, objects in a bucket you choose, or rows in a file: check the result, then put it to use.

| What happened | Choose | Why | In this workshop |
|---|---|---|---|
| Objects overwritten or deleted, the bucket intact | Backtrack, to a point up to its last daily sync | In place: no new bucket, no change for the application | Module 3 |
| A few rows deleted or wrong, that existed at the last monthly archive point | Records from an archive recovery point, with SQL, then load them | Only the rows you need, without restoring the whole database | Module 4A |
| Many rows wrong, or a table damaged | A full restore beside the original, then copy back what you need | Any size, and the live database stays online | Module 4B |
| A wrong change minutes ago, the account intact | AWS point-in-time recovery, to a new cluster | The fastest way back inside the account | Not run here |
| The database, the bucket, or their AWS copies deleted | A SecureVault restore. Recreate the bucket first | The copies live outside the account | Module 5 |
| An account or Region unavailable | A restore into another connected account or Region | No dependency on the source account | Clumio's documentation |
| You need to look, not recover | SQL on an archive recovery point | No database is restored | Module 4A, step 3 |

## How data moves

| Flow | Path | Modules |
|---|---|---|
| Protect | Clumio copies the database and the bucket into SecureVault on its schedule. Backtrack indexes the bucket's versions daily | 1 |
| Inventory | Event rules tell Clumio about new and changed resources. The tag decides what's protected | 1 |
| Roll back | Backtrack copies earlier versions back as current, inside your bucket | 3 |
| Records | SQL runs on an archive recovery point in Clumio's vault. Only the matching rows come back, as a CSV file | 4A |
| Restore a database | A recovery point becomes a snapshot in your account, then a new Aurora cluster. The snapshot is then deleted | 4B, 5 |
| Restore documents | A recovery point's objects are written into a bucket you choose | 5 |
| Evidence | Every protection and restore becomes a Clumio task, with its times | 6 |

## Change a setting

Each setting lives in one place. Change it before `terraform apply`, or after `./lab down`. Mid-workshop, Terraform would try to rebuild what Clumio restored.

| Setting | Where | Note |
|---|---|---|
| AWS Region or account | `terraform.tfvars`: `region`, `account_id` | Run `./lab preflight` again: it checks that Clumio supports the Region, and that you're signed in to the account |
| Resource names | `names.json` | Only if your naming rules require it. The guide shows the defaults |
| Archive retention, tags, IAM rules | `terraform.tfvars` | Each is in the example file, with a comment |
| Clumio token, same tenant | `CLUMIO_API_TOKEN` in your shell | Any time: `read -rs CLUMIO_API_TOKEN && export CLUMIO_API_TOKEN` |
| Clumio tenant | `CLUMIO_API_TOKEN` and `CLUMIO_API_BASE_URL` | Only after `./lab down`, run with the old tenant's token. The connection and policies belong to the tenant that created them |

## Commands

Run each command from the `orders-recovery` folder. Read-only commands never change anything.

| Command | Changes things | Module | What it does |
|---|---|---|---|
| `./lab preflight` | No | 0 | Checks the tools, the sign-in, the Region, and the Clumio token |
| `./lab status` | No | 1 | Shows Clumio's latest recovery points of the database and the documents, and whether the incidents can start |
| `./lab check` | No | All | Reports HEALTHY or BROKEN: every order is there, unchanged, with its intact document |
| `./lab portal` | No | All | Serves the portal at `http://localhost:8080` until Ctrl-C. `--port` picks another port |
| `./lab report` | No | 6 | Shows the scorecard, and writes `.lab/report.html` with every recorded event |
| `./lab seed` | Yes | 1 | Loads 1,000 orders and their documents. `terraform apply` runs it for you |
| `./lab break deploy` | Yes | 2 | Deletes 100 orders, and overwrites 50 documents. Refuses until Clumio holds recovery points of the loaded data |
| `./lab break everything` | Yes | 5 | Deletes the database, the bucket, and every version. Refuses until Clumio holds recovery points, then asks |
| `./lab prepare NAME` | Yes | 4B, 5 | Makes a restored cluster answer SQL: adds an instance, and turns on the RDS Data API |
| `./lab repair --from NAME` | Yes | 4B | Copies only the missing orders from a restored cluster into `orders-db` |
| `./lab repair --from-csv FILE` | Yes | 4A | Copies only the missing orders from a Clumio record-restore CSV into `orders-db`, after checking every row |
| `./lab drop NAME` | Yes | 4B | Deletes a restored cluster. Refuses `orders-db` and any cluster that isn't a workshop restore |
| `./lab rebuild` | Yes | 5 | Recreates the empty documents bucket, for Clumio to restore into |
| `./lab down` | Yes | 7 | Deletes everything the workshop created, then checks that it is gone. Asks first |

## Troubleshooting

Find the message you see in the first column. Every `STOP` message also says what to do next.

| You see | Cause | Resolution |
|---|---|---|
| `STOP: not signed in to AWS` | The sign-in expired | Run `aws sso login --profile orders-test` (or sign in your own way), then run the command again. |
| `STOP: signed in to AWS account …, but terraform.tfvars says …` | The terminal uses another account's profile. Every command checks this first, and changes nothing | Check `AWS_PROFILE`, and `account_id` in `terraform.tfvars`. |
| `STOP: aws … failed:` with an expired token or session | The sign-in expired during a command | Sign in again, then run the command again. |
| `STOP: export CLUMIO_API_TOKEN and CLUMIO_API_BASE_URL first` | A new terminal | Run steps 6 and 7 of [Set up](0-setup.md) again. |
| `STOP: Clumio refused the token or API URL`, or `Clumio answered HTTP 401` | The token expired, or the API URL is wrong | Get a new token, and check `CLUMIO_API_BASE_URL`. |
| `STOP: … is already connected to Clumio` | This account and Region are connected already, by another workshop or by production | Use another test account or Region. |
| `STOP: Clumio can't connect AWS Region …` | Clumio doesn't support this Region | Choose another Region in `terraform.tfvars`. |
| `STOP: …'s default Aurora MySQL is …` | The Region's Aurora version can't use the RDS Data API | Choose another Region in `terraform.tfvars`. |
| `the RDS Data API still isn't ready after 20 minutes` | AWS keeps answering that the Data API is starting, usually while a cluster is created, restored or changed | Wait until the cluster is **Available** in the Amazon RDS console, then run the command again. |
| `database  not queryable: <AWS's answer>` in `./lab check` | The cluster can't take SQL right now, for the reason AWS gives | If the cluster is being created or deleted, wait, then check again. Otherwise do what the answer says, such as `./lab prepare orders-db`. |
| `STOP: port 8080 is in use` | Another program uses the portal's port | Run `./lab portal --port 8081`, and open `http://localhost:8081`. |
| The portal says `CAN'T CHECK` | Your AWS sign-in expired, or AWS refused the call | Do what the message says, such as `aws sso login`. Then check the order again. |
| `terraform apply` stops at `terraform_data.sample_data` | `./lab seed` stopped. Its `STOP` message says why | Fix the cause, then run `terraform apply` again. It continues from there. |
| `protected by  another policy, through rule …` in `./lab status` | Clumio applies the first rule that matches, and an older, wider rule in your tenant matched `orders-db` first | Set `rds_rule_before_id` in `terraform.tfvars` to the rule ID it shows, then run `terraform apply`. Or ask your Clumio administrator to narrow that rule. |
| `./lab status` shows `none yet`, or `ready for the incidents  no` | Clumio hasn't taken the first recovery points yet. With the archive on, that includes the first archive point | Wait, then run `./lab status` again. In the Clumio console, check **Activity**, **Tasks**. |
| `STOP: no SecureVault recovery point of …` from `./lab break` | The safety gate: Clumio has no copy to recover from yet | Nothing was changed. Wait until `./lab status` says `ready for the incidents  yes`. |
| Record restore: error code 111 | The table name in the query is incomplete | Copy it again with the copy icon in **Schema browser**. |
| `STOP: the CSV lacks …` | The query selected only some columns | Query with `SELECT *`, as in Module 4A, step 3. |
| `STOP: the CSV has an order this workshop didn't make` | Another file, or another table | Download the CSV from this record restore. |
| The restored records can't be downloaded | Their download window passed | Run the record restore again. |
| `schema  different: …` in `./lab check` | The database lacks a column, type or index that `./lab seed` created | Name the difference in your evidence. After a restore, compare the source's DDL with the restored one, and fix the difference before you cut over. |
| The restored cluster has another name, such as `restored-orders-db-<number>` | Switching between **Default** and **Custom** cleared the name you entered, so Clumio chose one | In Module 4B, use that name in the next steps: `./lab` recognizes a restore by its subnet group. In Module 5, the name must be `orders-db`. When the cluster is **Available**, not **Backing-up**, rename it: `aws rds modify-db-cluster --db-cluster-identifier <name> --new-db-cluster-identifier orders-db --apply-immediately`. |
| S3 restore: `Error 111: The target bucket has been deleted and cannot be used as a restore destination.` | **Source** means the deleted bucket, even after `./lab rebuild` made one with the same name | Choose **Custom**, and select the rebuilt bucket, as in Module 5. |
| `STOP: … isn't queryable yet` | The restored cluster has no instance, or no RDS Data API | Run `./lab prepare NAME`. |
| `STOP: … doesn't answer SQL after 20 minutes` | The instance is still starting | Wait until the cluster is **Available** in the Amazon RDS console, then run the command again. |
| `STOP: … isn't a workshop restore` | `./lab drop` refuses clusters it didn't recognize as restores | Check the name. To delete another cluster, use the Amazon RDS console. |
| `./lab down` says `STOP` | A delete is still running, or failed | Fix what the message names, then run `./lab down` again. |
| `terraform destroy` fails with `error_code 367` | Your Clumio tenant doesn't allow deleting AWS connections | Ask your Clumio administrator to delete the connection for this account and Region. Then run `./lab down` again. |

## Glossary

See [Words you'll see](../../../docs/words.md), the one glossary for the whole repo.
