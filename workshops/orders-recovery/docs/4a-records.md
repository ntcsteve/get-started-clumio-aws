# 4A. Recover the orders from the archive

**Requires:** [3. Recover the documents](3-documents.md). In a new terminal, first [start a session](0-setup.md#start-a-session).

The bad deployment deleted 100 orders. Customers kept ordering since, so rolling the whole database back would lose their orders too. Instead, you bring back only the 100 that are missing. You do it two ways, in order. In a real incident, you'd pick one, by the size of the damage.

| Way back | When to use it | What it takes |
|---|---|---|
| **4A. Records** (first) | A few rows that existed at the last monthly archive recovery point | SQL on an archive recovery point returns just those rows, with no restore. Preparing the archive can take up to 48 hours |
| **4B. Whole database** (then) | Damage of any size | A full restore beside the original. You copy back only what's missing |

**With AWS's own backups:** a restore brings back the whole cluster. Then you find the 100 rows and copy them back yourself.

Skipped Module 2, step 6, because the archive was still preparing? You can run its two queries now, before step 3, to see what was there before the bad deployment.

You need the archive recovery point from [Module 1, step 7](1-deploy.md#wait-for-the-first-recovery-points), ready to query. It was taken before the bad deployment, so it holds every order the bad deployment deleted.

1. Open **Record restore**: from Clumio's email, or in the Clumio console under **AWS**, **Inventory**, **RDS resources**, `orders-db`, by choosing **Restore** on that archive recovery point. If Clumio lists more than one `orders-db`, first, at the top of **Inventory**, choose your account in **All accounts** and your Region in **All regions**.

   Clumio offers **Prepare records for restore** instead? The point is in cold storage. Choose it, and come back when Clumio emails that it's ready, which can take up to 48 hours. If no archive recovery point is from before the change time, use 4B.

> [!NOTE]
> Clumio makes the archive recovery point ready for SQL in its own vault. Nothing is restored into your account.

2. In **Schema browser**, next to the `orders_…` table, not `deployment_…`, choose the copy icon. It copies the table's full name.

3. Enter this query with the name you copied, and choose **Preview first 10 records**. It selects every tenth order: exactly the ones the bad deployment deleted. Without `ORDER BY`, the preview shows them in no set order.

   ```sql
   SELECT * FROM <orders table> WHERE id % 10 = 0 ORDER BY id
   ```

   **You should see** orders 10, 20, 30, and so on.

   ![Clumio Record restore: Schema browser, the query, and a preview of orders 10, 20 and 30](../images/4-1-record-query.png)

4. Choose **Initiate record restore**. Only these 100 rows leave the vault, as a CSV file. When it's ready, choose **Activity**, **Tasks**, then the record retrieval task, and choose **Download content**. In the test run, the task took 8 seconds.

   ![The record retrieval task, completed: 100 records, with Download content](../images/4-2-restored-records.png)

5. Load the missing orders back. Drag the CSV from your Downloads folder into the terminal to paste its path. The command checks every row against the `orders` table's own definition, then copies only the orders that are missing. It uses the kit's [record-restore tool](../../../tools/record-restore/README.md), which works the same way for your own tables.

   ```bash
   ./lab repair --from-csv <the CSV file>
   ```

   **You should see:**

   ```text
   Copied 100 of 100 missing orders from <the CSV's file name>. Next: ./lab check
   ```

6. Verify against the archive. In **Record restore**, preview these two:

   ```sql
   SELECT COUNT(*) AS orders, SUM(total) AS total FROM <orders table>
   ```

   ```sql
   SELECT COUNT(*) AS null_notes FROM <orders table> WHERE note IS NULL
   ```

   **You should see** `1000` and `2419000.00`, then `142`. In the next step, `./lab check` shows the same orders, total and NULL count. Clumio's CSV writes NULL as an empty field and empty text as `""`, and the repair keeps them apart. A spreadsheet re-save loses that difference, and the check reports `orders changed  14 (note: 14)`, BROKEN. So pass the CSV to `./lab` untouched.

> [!NOTE]
> Use `%` for remainders, not `MOD`. Error code 111 means the table name is incomplete: copy it again with the copy icon.

## Check the application

1. Check the data.

   ```bash
   ./lab check
   ```

   **You should see:**

   ```text
     schema               matches
     totals               1000 orders, 2419000.00 in total, 142 notes NULL
     orders missing       0
     orders changed       0
     documents missing    0
     documents changed    0
     control order 1      intact
   HEALTHY
   ```

   `orders changed  0` means every value matches what `./lab seed` loaded, down to the 142 notes that are NULL rather than empty. `schema  matches` means the database still has the columns, types and indexes `./lab seed` created.

2. In the portal, check order `10`: HEALTHY again. AnyCompany has every order back.

### Is the schema right?

A record restore returns rows, not the table's definition. So after 4A, ask two questions: did the rows come back exactly, and is the table still what it should be? `./lab check` answers both, three ways:

| Check | How | After 4A |
|---|---|---|
| The schema | Every column's name, type and nullability, and every index, against the copy `./lab seed` saved in `.lab/schema.json` | `schema  matches` |
| Every value | All 8 columns of all 1,000 orders against what was loaded. A value written another way, such as `370.5` for `370.50`, is the same value | `orders changed  0` |
| An independent count | The archive's own SQL, `COUNT(*)`, `SUM(total)` and the NULL count, against the `totals` line | `1000`, `2419000.00`, `142` on both sides |

Two things to know before you rely on it in production:

- **The archive's types aren't the database's.** The Schema browser lists `placed_at` as `bigint`, and the CSV writes it as microseconds since 1970 in UTC. `./lab repair --from-csv` converts it back to `DATETIME(3)`, and checks every row before it writes. Validate against the live schema, never the archive's.
- **Rows can't repair a structure.** If a deployment drops a column, changes a type or removes an index, the CSV has nowhere to go. Restore the whole database instead, as in 4B or Module 5: it comes back with its schema, and `./lab check` compares that schema the same way. In production, keep the table definitions in versioned migrations, so you can compare a restore with what should be there.

### In production: your own tables

For a table of your own in Aurora MySQL, use the kit's [record-restore tool](../../../tools/record-restore/README.md). It reads the table's definition, checks every row of Clumio's CSV against it, and copies only the missing rows: `--check` first, then the copy. No code changes per table.

**Next:** [4B. Recover the whole database](4b-database.md)
