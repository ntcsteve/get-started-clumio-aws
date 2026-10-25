# Record restore: from a Clumio CSV back into Aurora MySQL

Part of [Get started with Clumio on AWS](../../README.md). A Clumio record restore returns rows from an archive recovery point as a CSV file. This tool puts them back into a table, safely: it checks every row against the table's own definition, then copies only the rows that are missing. It writes nothing until every row has passed.

It works for any table in Aurora MySQL, with no code to change: the table describes itself, through `information_schema`. The [orders workshop](../../workshops/orders-recovery/docs/4a-records.md) uses it in Module 4A.

```
 CSV from Clumio ──▶ read it: an empty unquoted field is NULL, "" is empty text
 the target table ──▶ its columns, types, NOT NULL, primary key (information_schema)
                         │
                         ▼  every value checked and converted for its column
                      any bad value ──▶ STOP, nothing written
                         │
                         ▼
                      copy only the rows whose primary key is missing
```

## Run it

You need Python 3, the AWS CLI v2 signed in to the database's account, the RDS Data API turned on for the cluster, and the ARN of the secret that holds the database login.

1. Check the file without writing anything:

   ```bash
   python3 tools/record-restore/record_restore.py --check \
     --csv restored-records.csv --table orders --database orders \
     --cluster-arn arn:aws:rds:<region>:<account>:cluster:<cluster> \
     --secret-arn arn:aws:secretsmanager:<region>:<account>:secret:<secret> \
     --region <region>
   ```

   **You should see** how many rows passed, and how many are missing from the table: `checked 100 rows: 100 missing from orders, 0 already there. Nothing was written (--check)`.

2. Copy the missing rows: run the same command without `--check`.

   **You should see** `copied 100 rows into orders; 0 were already there`.

3. Check the result with your own tests: row counts, totals of key columns, and a smoke test of the application.

Download the CSV from Clumio, and pass it untouched. A spreadsheet re-save erases the difference between NULL and empty text.

## What it does, and when it stops

Every stop names the row and column, and writes nothing.

| Case | Result |
|---|---|
| The file is missing, larger than `--max-mb` (1 MB by default), or not UTF-8 | STOP |
| A quote is broken, a row has more or fewer fields than the header, or the header repeats a name | STOP |
| The table doesn't exist, or has no primary key | STOP: the key is how it knows a row is missing |
| A column of the table isn't in the CSV, or the CSV has a column the table lacks | STOP. Query the archive with `SELECT *` |
| A column's type isn't one of the types below | STOP, naming the type |
| A value doesn't fit its column: not a number, too long, out of range, or NULL in a NOT NULL column | STOP |
| The file repeats a row exactly | Read once |
| The file has two different rows with the same primary key | STOP |
| Every row passed | Rows already in the table are left as they are; the missing ones are copied |

## Types it reads

| Type in Aurora MySQL | How the CSV writes it | Seen in a live run |
|---|---|---|
| `tinyint`, `smallint`, `mediumint`, `int`, `bigint` | A whole number | Yes |
| `decimal`, `numeric` | A number, within the column's digits and scale | Yes |
| `char`, `varchar`, `tinytext`, `text`, `mediumtext`, `longtext` | Text, kept exactly, spaces and newlines included | Yes |
| `datetime`, `timestamp`, with up to 3 fractional digits | Microseconds since 1970 in UTC, as Clumio writes it, or ISO 8601 | Yes, microseconds |
| `date` | ISO 8601, such as `2026-10-24` | No: check the result |
| `float`, `double` | A number | No: check the result |

Other types, such as `json`, `blob`, `enum` or `datetime(6)`, stop with the type named. Add them in `record_restore.py`, in `read_value`, with a test.

## Not covered

Aurora PostgreSQL, other databases, and tables without a primary key. The SQL is standard apart from MySQL's identifier quotes, so PostgreSQL is a small step, but it isn't built or tested.

## For AI agents

- Run `--check` first, and show the person its output. Copy only after their go: the copy writes to a database.
- Never edit the CSV to get past a STOP. The STOP names what's wrong with the file or the table: tell the person.
- The tool reads its login from the secret, through the RDS Data API. Never print the secret.
- Tests: `python3 -m unittest discover -s tools/record-restore/tests`. They run offline, against a fake database.
