# 7. Clean up

**Requires:** a started session: see [Start a session](0-setup.md#start-a-session). Run it at any time to stop the workshop.

To stop AWS charges, delete everything the workshop created. One command does it, and then checks that nothing is left.

1. Stop the portal: in its terminal, press Ctrl-C. Then run the clean-up command. It lists what it will delete: any restored clusters, any instance added after Terraform built the database, and everything Terraform built. Read the list, then enter the account ID. It deletes the restored clusters, then runs `terraform destroy` without asking again.

   ```bash
   ./lab down
   ```

   **You should see** this on the last line:

   ```text
   DONE: the workshop is gone. Clumio keeps recovery points it already took until their retention ends
   ```

2. If it says `STOP` instead, fix what the message names, and run `./lab down` again. It is safe to run again: it skips what is already deleted, and waits for what is still being deleted.

> [!NOTE]
> `./lab down` deletes only what carries the tag `Workshop = orders-recovery`. A restore keeps that tag from `orders-db`. If you removed it, or restored with **Custom** tags, delete that cluster in the Amazon RDS console.

> [!NOTE]
> If `terraform destroy` fails with `error_code 367`, your Clumio tenant doesn't allow deleting AWS connections. Ask your Clumio administrator to delete the connection for this account and Region. Then run `./lab down` again.

## Next: your own data

The step from a workshop to your own estate: protect one of your own non-production databases or buckets, recover it, and check it with your own tests. This repo's production steps use the same modules as this workshop.

1. Follow this repo's [README](../../../README.md): steps 0 and 1 for the account, then step 2a, 2b, or both. Protect by tag, so new resources with the tag are covered too.
2. For a database, set `pitr_retention_days` to its current value, so nothing changes for it.
3. Wait for the first recovery points. Then recover a copy into a new cluster or bucket, as in Module 4B or 5.
4. Check it with your own tests: row counts and totals of key tables, and a smoke test of the application. Note the time it took. Then delete the copy.
5. Keep [Choose the way back](../../../docs/operate.md#choose-the-way-back) with your incident runbooks. Set an impact tolerance for the service, as AnyCompany did. Then repeat the recovery test on a schedule, so its time stays current, and hold each result against that tolerance.

You'll learn what this workshop can't tell you: how long protection and recovery take at your size, and whether your own checks pass.

**Key takeaway:** One command removes the workshop, and then checks that nothing is left. Recovery points that Clumio already took stay until their retention ends.

## Summary

AnyCompany's Friday deployment, and the worst case after it, are both behind you. You deployed an application with its protection as code, broke it twice, recovered it, and measured how long each recovery took. You learned how to:

- Protect a database and a bucket with Clumio policies that deploy with the application
- Measure what a bad deployment did to the data, even when nothing alerts
- Roll documents back in place with Backtrack, to a point before the bad deployment
- Choose by the size of the damage: records from an archive with SQL, or a whole database beside the original
- Recover after the database, the bucket, and their AWS backups were deleted
- Prove a recovery with a scorecard and Clumio's task records

**Learn more:** [Clumio documentation](https://documentation.commvault.com/clumio/)
