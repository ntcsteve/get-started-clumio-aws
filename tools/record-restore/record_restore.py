#!/usr/bin/env python3
"""Put rows from a Clumio record-restore CSV back into an Aurora MySQL table, safely.

The table describes itself, through information_schema, so any table works with no code to change.
Every row is checked against its column's type before anything is written; then only the rows whose
primary key is missing are copied. See README.md beside this file.

  python3 record_restore.py --check --csv FILE --table T --database D --cluster-arn A --secret-arn S --region R
  python3 record_restore.py         --csv FILE --table T --database D --cluster-arn A --secret-arn S --region R

Standard library only. Talks to the database through the AWS CLI's RDS Data API.
"""

import argparse
import collections
import datetime
import decimal
import json
import math
import os
import re
import subprocess
import sys

SAFE_NAME = r"[A-Za-z_][A-Za-z0-9_]{0,63}"  # names go into SQL as identifiers, so only these
BATCH = 200  # rows per statement: well under the RDS Data API's request size limit

# information_schema's DATA_TYPE, by the rule that reads it. Anything else stops, naming the type.
KINDS = {**{t: "integer" for t in ("tinyint", "smallint", "mediumint", "int", "integer", "bigint")},
         **{t: "decimal" for t in ("decimal", "numeric")},
         **{t: "float" for t in ("float", "double", "real")},
         **{t: "text" for t in ("char", "varchar", "tinytext", "text", "mediumtext", "longtext")},
         "date": "date", "datetime": "time", "timestamp": "time"}
# Aurora MySQL's own limits for each time type, in UTC.
TIME_RANGE = {"datetime": ("1000-01-01", "9999-12-31 23:59:59.999999"), "timestamp": ("1970-01-01 00:00:01", "2038-01-19 03:14:08")}

Column = collections.namedtuple("Column", "name type kind nullable length precision scale time_digits")

COLUMNS_SQL = ("SELECT COLUMN_NAME AS name, DATA_TYPE AS type, IS_NULLABLE AS nullable, CHARACTER_MAXIMUM_LENGTH AS length, "
               "NUMERIC_PRECISION AS `precision`, NUMERIC_SCALE AS scale, DATETIME_PRECISION AS time_digits "
               "FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = :table "
               "ORDER BY ORDINAL_POSITION")
KEY_SQL = ("SELECT COLUMN_NAME AS name FROM information_schema.KEY_COLUMN_USAGE "
           "WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = :table AND CONSTRAINT_NAME = 'PRIMARY' ORDER BY ORDINAL_POSITION")


class RestoreError(Exception):
    """A reason to stop, for a person to read. `written` counts rows already copied when it happened."""

    def __init__(self, message, written=0):
        super().__init__(message)
        self.written = written


# --- 1. Read the file ---------------------------------------------------------------------------

def parse_csv(text):
    """The records of a CSV (RFC 4180), each a list of (value, was_quoted). Pure. Python's csv module
    can't tell an empty unquoted field from a quoted "" before 3.12, and Clumio writes NULL as the first
    and empty text as the second (seen live). A malformed quote raises ValueError."""
    records, record, position = [], [], 0
    while position < len(text):
        if text[position] == '"':
            value, position = read_quoted_field(text, position, len(records) + 1)
            record.append((value, True))
        else:
            end = position
            while end < len(text) and text[end] not in ",\r\n":
                end += 1
            record.append((text[position:end], False))
            position = end
        if position < len(text) and text[position] == ",":
            position += 1
            if position == len(text):
                record.append(("", False))
            continue
        if text.startswith("\r\n", position):
            position += 2
        elif position < len(text):
            position += 1
        records.append(record)
        record = []
    if record:
        records.append(record)
    return records


def read_quoted_field(text, position, record_number):
    """One quoted field starting at position: (its value, the position after it). "" is a literal quote."""
    value, position = [], position + 1
    while True:
        end = text.find('"', position)
        if end == -1:
            raise ValueError(f"record {record_number} has a quote that is never closed")
        value.append(text[position:end])
        if text.startswith('""', end):
            value.append('"')
            position = end + 2
            continue
        position = end + 1
        if position < len(text) and text[position] not in ",\r\n":
            raise ValueError(f"record {record_number} has text after a closing quote")
        return "".join(value), position


def read_csv(path, max_mb):
    """(header, rows) from the file: names lowercased, each row a dict of name to text, or None for NULL.
    The file comes from outside, so its shape is checked here, before any value is read."""
    if not os.path.isfile(path):
        raise RestoreError(f"{path} not found")
    size_mb = os.path.getsize(path) / 1_000_000
    if size_mb > max_mb:
        raise RestoreError(f"{path} is {size_mb:.1f} MB, over the {max_mb} MB limit. Is it the right file?")
    try:
        with open(path, newline="", encoding="utf-8-sig") as file:  # utf-8-sig: a spreadsheet's byte-order mark
            text = file.read()
    except UnicodeDecodeError:
        raise RestoreError("the CSV isn't UTF-8, the way Clumio writes it. Download it again, "
                           "and don't save it from a spreadsheet") from None
    try:
        records = parse_csv(text)
    except ValueError as error:
        raise RestoreError(f"the CSV is malformed: {error}. Download it again from Clumio") from None
    header = [value.strip().lower() for value, _quoted in records[0]] if records else []
    repeated = sorted({name for name in header if header.count(name) > 1})
    if repeated:
        raise RestoreError(f"the CSV's header names {', '.join(repeated)} twice. Download it again from Clumio")
    rows = []
    for number, record in enumerate(records[1:], 2):
        if record == [("", False)]:  # a blank line
            continue
        if len(record) != len(header):
            raise RestoreError(f"the CSV's record {number} has {len(record)} fields, the header has {len(header)}")
        rows.append({name: (value if value or quoted else None) for name, (value, quoted) in zip(header, record)})
    if not rows:
        raise RestoreError("the CSV has no rows. Check the query that made it")
    return header, rows


# --- 2. Describe the table ----------------------------------------------------------------------

def describe_table(query, table):
    """(columns, primary key column names) of a table, from information_schema. query(statement,
    parameters) returns rows as dicts. Stops on a table it can't copy into safely."""
    if not re.fullmatch(SAFE_NAME, table):
        raise RestoreError(f"{table!r} isn't a table name this tool accepts (letters, digits and _)")
    name = [{"name": "table", "value": {"stringValue": table}}]
    found = query(COLUMNS_SQL, name)
    if not found:
        raise RestoreError(f"there's no table {table} in this database")
    columns = []
    for c in found:
        kind = KINDS.get(str(c["type"]).lower())
        time_digits = int(c.get("time_digits") or 0)
        if kind is None or (kind == "time" and time_digits > 3) or not re.fullmatch(SAFE_NAME, c["name"]):
            shown = f"{c['type']}({time_digits})" if kind == "time" else c["type"]
            raise RestoreError(f"{table}.{c['name']} is {shown}: this tool doesn't read that yet. "
                               "Add it in record_restore.py, in read_value, with a test")
        columns.append(Column(c["name"], str(c["type"]).lower(), kind, c["nullable"] == "YES", c.get("length"),
                              c.get("precision"), c.get("scale"), time_digits))
    key = [k["name"] for k in query(KEY_SQL, name)]
    if not key:
        raise RestoreError(f"{table} has no primary key: the key is how only the missing rows are copied")
    return columns, key


# --- 3. Check every row -------------------------------------------------------------------------

def read_value(column, text, row, earliest=None, latest=None):
    """One CSV value, checked and converted for its column. Pure. None is NULL. Text stays exact;
    every other kind is trimmed first. earliest and latest narrow a time column's range, so that, say,
    milliseconds read as microseconds (they land in 1970) can be refused."""
    where = f"row {row}, {column.name}"
    if text is None:
        if not column.nullable:
            raise RestoreError(f"{where}: NULL, but the column is NOT NULL")
        return None
    if column.kind == "text":
        if column.length and len(text) > column.length:
            raise RestoreError(f"{where}: {len(text)} characters, more than its {column.length}")
        return text
    value = text.strip()
    if column.kind == "integer":
        if not re.fullmatch(r"-?[0-9]{1,20}", value):
            raise RestoreError(f"{where}: {value[:30]!r} isn't a whole number")
        return int(value)
    if column.kind == "decimal":
        if not re.fullmatch(r"-?[0-9]{1,65}(\.[0-9]{1,30})?", value):
            raise RestoreError(f"{where}: {value[:30]!r} isn't a number")
        whole, _, fraction = value.lstrip("-").partition(".")
        scale, precision = int(column.scale or 0), int(column.precision or 65)
        if len(fraction.rstrip("0")) > scale or len(whole.lstrip("0")) > precision - scale:
            raise RestoreError(f"{where}: {value[:30]!r} doesn't fit decimal({precision},{scale})")
        return f"{decimal.Decimal(value):.{scale}f}"
    if column.kind == "float":
        try:
            number = float(value)
        except ValueError:
            number = math.nan
        if not math.isfinite(number):
            raise RestoreError(f"{where}: {value[:30]!r} isn't a number")
        return number
    if column.kind == "date":
        try:
            return datetime.date.fromisoformat(value).isoformat()
        except ValueError:
            raise RestoreError(f"{where}: {value[:30]!r} isn't a date such as 2026-10-24") from None
    return read_time(column, value, where, earliest, latest)


def read_time(column, value, where, earliest, latest):
    """A datetime or timestamp: microseconds since 1970 in UTC, as Clumio writes it (seen live), or ISO
    8601. Returned as the database takes it, with the column's fractional digits, never fewer."""
    low, high = (datetime.datetime.fromisoformat(t) for t in TIME_RANGE[column.type])
    low = max(low, datetime.datetime.fromisoformat(earliest)) if earliest else low
    high = min(high, datetime.datetime.fromisoformat(latest)) if latest else high
    epoch = datetime.datetime(1970, 1, 1)
    if re.fullmatch(r"[0-9]{1,19}", value):
        microseconds = int(value)  # checked as a number first, so a huge one can't overflow the conversion
        if not (low - epoch) // datetime.timedelta(microseconds=1) <= microseconds < (high - epoch) // datetime.timedelta(microseconds=1):
            raise RestoreError(f"{where}: {value[:30]!r} isn't a time in microseconds since 1970, from {low:%Y-%m-%d} to {high:%Y-%m-%d}")
        moment = epoch + datetime.timedelta(microseconds=microseconds)
    else:
        try:
            moment = datetime.datetime.fromisoformat(value.replace("T", " ").replace("Z", "+00:00"))
            if moment.tzinfo:
                moment = moment.astimezone(datetime.timezone.utc).replace(tzinfo=None)
        except (ValueError, OverflowError):
            raise RestoreError(f"{where}: {value[:30]!r} isn't a time") from None
        if not low <= moment < high:
            raise RestoreError(f"{where}: {value[:30]!r} isn't a time from {low:%Y-%m-%d} to {high:%Y-%m-%d}")
    digits = column.time_digits
    if moment.microsecond % 10 ** (6 - digits):
        raise RestoreError(f"{where}: {value[:30]!r} has more precision than the column holds")
    shown = moment.strftime("%Y-%m-%d %H:%M:%S.%f")
    return shown[:19] if digits == 0 else shown[:20 + digits]


def check_rows(columns, key, header, rows, earliest=None, latest=None):
    """Every row checked and converted, one per primary key. Pure. Stops on the first problem, naming
    the row; nothing is written before every row has passed."""
    names = [c.name.lower() for c in columns]
    lacking = [n for n in names if n not in header]
    if lacking:
        raise RestoreError(f"the CSV lacks {', '.join(lacking)}, which the table has. Query the archive with SELECT *")
    extra = [h for h in header if h not in names]
    if extra:
        raise RestoreError(f"the CSV has {', '.join(extra)}, which the table lacks. Query the archive with SELECT *")
    by_key = {}
    for number, row in enumerate(rows, 2):
        checked = {c.name: read_value(c, row[c.name.lower()], number, earliest, latest) for c in columns}
        row_key = tuple(checked[k] for k in key)
        if row_key in by_key and by_key[row_key] != checked:
            raise RestoreError(f"row {number}: two different rows have the same primary key "
                               f"({', '.join(f'{k} {checked[k]}' for k in key)})")
        by_key[row_key] = checked
    return list(by_key.values())


# --- 4. Copy only what's missing ----------------------------------------------------------------

def parameters(columns, row):
    """One row as RDS Data API parameters, each typed for its column; None is SQL NULL. Pure."""
    def one(column):
        value = row[column.name]
        if value is None:
            return {"isNull": True}, None
        return {"integer": ({"longValue": value}, None), "float": ({"doubleValue": value}, None),
                "decimal": ({"stringValue": value}, "DECIMAL"), "date": ({"stringValue": value}, "DATE"),
                "time": ({"stringValue": value}, "TIMESTAMP"), "text": ({"stringValue": value}, None)}[column.kind]
    result = []
    for column in columns:
        value, hint = one(column)
        parameter = {"name": column.name, "value": value}
        if hint:
            parameter["typeHint"] = hint
        result.append(parameter)
    return result


def copy_missing(query, insert, table, columns, key, rows, write=True):
    """(missing, already there). Copies the missing rows unless write is False. insert(statement,
    parameter_sets) runs one statement once per parameter set."""
    key_columns = [next(c for c in columns if c.name == k) for k in key]
    present = set()
    for start in range(0, len(rows), BATCH):
        batch = rows[start:start + BATCH]
        tuples = ", ".join("(" + ", ".join(f":k{i}_{j}" for j in range(len(key))) + ")" for i in range(len(batch)))
        statement = (f"SELECT {', '.join(f'`{k}`' for k in key)} FROM `{table}` "
                     f"WHERE ({', '.join(f'`{k}`' for k in key)}) IN ({tuples})")
        named = [dict(p, name=f"k{i}_{j}") for i, r in enumerate(batch) for j, p in enumerate(parameters(key_columns, r))]
        found = query(statement, named)
        present |= {tuple(read_found(c, f[c.name]) for c in key_columns) for f in found}
    missing = [r for r in rows if tuple(r[k] for k in key) not in present]
    if write:
        statement = (f"INSERT INTO `{table}` ({', '.join(f'`{c.name}`' for c in columns)}) "
                     f"VALUES ({', '.join(f':{c.name}' for c in columns)})")
        copied = 0
        for start in range(0, len(missing), BATCH):
            try:
                insert(statement, [parameters(columns, r) for r in missing[start:start + BATCH]])
            except RestoreError as error:
                raise RestoreError(str(error), written=copied) from None
            copied += len(missing[start:start + BATCH])
    return len(missing), len(rows) - len(missing)


def read_found(column, value):
    """A key value as the database returned it, in the form check_rows gives it, so the two compare."""
    if column.kind == "integer":
        return int(value)
    return read_value(column, str(value), 0) if column.kind != "text" else value


# --- The command line ---------------------------------------------------------------------------

def data_api(cluster_arn, secret_arn, database, region):
    """query and insert functions over the AWS CLI's RDS Data API."""
    def run(*args):
        result = subprocess.run(["aws", "rds-data", *args, "--resource-arn", cluster_arn, "--secret-arn", secret_arn,
                                 "--database", database, "--region", region, "--output", "json"],
                                capture_output=True, text=True)
        if result.returncode != 0:
            raise RestoreError(f"the RDS Data API refused: {result.stderr.strip()[:300]}")
        return json.loads(result.stdout or "{}")

    def query(statement, params=()):
        answer = run("execute-statement", "--sql", statement, "--parameters", json.dumps(list(params)),
                     "--format-records-as", "JSON")
        return json.loads(answer.get("formattedRecords") or "[]")

    def insert(statement, parameter_sets):
        run("batch-execute-statement", "--sql", statement, "--parameter-sets", json.dumps(parameter_sets))
    return query, insert


def main(argv=None, database=None):
    parser = argparse.ArgumentParser(prog="record_restore.py", description=__doc__.split("\n\n")[0])
    parser.add_argument("--csv", required=True, help="the CSV from Clumio's record restore, untouched")
    parser.add_argument("--table", required=True, help="the table to copy the missing rows into")
    parser.add_argument("--check", action="store_true", help="check every row and count what's missing; write nothing")
    parser.add_argument("--max-mb", type=float, default=1, help="refuse a larger file (default 1)")
    for name in ("--database", "--cluster-arn", "--secret-arn", "--region"):
        parser.add_argument(name, required=database is None)
    args = parser.parse_args(argv)
    query, insert = database or data_api(args.cluster_arn, args.secret_arn, args.database, args.region)
    try:
        columns, key = describe_table(query, args.table)
        header, rows = read_csv(args.csv, args.max_mb)
        checked = check_rows(columns, key, header, rows)
        missing, already = copy_missing(query, insert, args.table, columns, key, checked, write=not args.check)
    except RestoreError as error:
        done = f"{error.written} rows were copied before this; run it again to copy the rest" if error.written else "Nothing was written"
        print(f"STOP: {error}. {done}", file=sys.stderr)
        return 1
    if args.check:
        print(f"checked {len(checked)} rows: {missing} missing from {args.table}, {already} already there. "
              "Nothing was written (--check)")
    else:
        print(f"copied {missing} rows into {args.table}; {already} were already there")
    return 0


if __name__ == "__main__":
    sys.exit(main())
