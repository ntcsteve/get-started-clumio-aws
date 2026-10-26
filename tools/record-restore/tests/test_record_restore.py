"""Tests for record_restore: a Clumio record-restore CSV back into any Aurora MySQL table. Standard
library only, against a fake database. Run from the repo root:

    python3 -m unittest discover -s tools/record-restore/tests
"""

import contextlib
import io
import os
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
import record_restore as rr  # noqa: E402

ORDERS = [  # the workshop's table, as information_schema describes it (seen live)
    {"name": "id", "type": "int", "nullable": "NO", "length": None, "precision": 10, "scale": 0, "time_digits": None},
    {"name": "customer", "type": "varchar", "nullable": "NO", "length": 80, "precision": None, "scale": None, "time_digits": None},
    {"name": "total", "type": "decimal", "nullable": "NO", "length": None, "precision": 10, "scale": 2, "time_digits": None},
    {"name": "status", "type": "varchar", "nullable": "NO", "length": 20, "precision": None, "scale": None, "time_digits": None},
    {"name": "note", "type": "text", "nullable": "YES", "length": 65535, "precision": None, "scale": None, "time_digits": None},
    {"name": "placed_at", "type": "datetime", "nullable": "NO", "length": None, "precision": None, "scale": None, "time_digits": 3},
    {"name": "document_key", "type": "varchar", "nullable": "NO", "length": 80, "precision": None, "scale": None, "time_digits": None},
    {"name": "document_sha256", "type": "char", "nullable": "NO", "length": 64, "precision": None, "scale": None, "time_digits": None},
]
# A made-up second table with other types: proves nothing in the tool is about orders.
SHIPMENTS = [
    {"name": "region", "type": "char", "nullable": "NO", "length": 2, "precision": None, "scale": None, "time_digits": None},
    {"name": "number", "type": "bigint", "nullable": "NO", "length": None, "precision": 19, "scale": 0, "time_digits": None},
    {"name": "weight", "type": "decimal", "nullable": "YES", "length": None, "precision": 5, "scale": 2, "time_digits": None},
    {"name": "label", "type": "varchar", "nullable": "YES", "length": 5, "precision": None, "scale": None, "time_digits": None},
    {"name": "shipped_on", "type": "date", "nullable": "NO", "length": None, "precision": None, "scale": None, "time_digits": None},
    {"name": "ratio", "type": "double", "nullable": "YES", "length": None, "precision": 22, "scale": None, "time_digits": None},
    {"name": "seen_at", "type": "timestamp", "nullable": "YES", "length": None, "precision": None, "scale": None, "time_digits": 0},
]


class FakeDatabase:
    """Answers like Aurora MySQL through the RDS Data API. Inserts land only on commit; a rollback
    drops them. Text keys compare case-insensitively, as MySQL's default collation does."""

    def __init__(self, tables, keys, existing=(), strict=True, fail_on_insert=None):
        self.tables, self.keys, self.existing = tables, keys, set(existing)
        self.strict, self.fail_on_insert = strict, fail_on_insert
        self.inserted, self.pending, self.log = [], [], []

    def query(self, statement, parameters=(), transaction=None):
        values = {p["name"]: list(p["value"].values())[0] for p in parameters}
        if "information_schema.COLUMNS" in statement:
            return list(self.tables.get(values["table"], []))
        if "information_schema.KEY_COLUMN_USAGE" in statement:
            return [{"name": n} for n in self.keys.get(values["table"], [])]
        if statement.startswith("SELECT @@SESSION.sql_mode"):
            return [{"mode": "STRICT_TRANS_TABLES,NO_ZERO_DATE" if self.strict else "NO_ZERO_DATE"}]
        if statement.startswith("SET time_zone"):
            self.log.append(("time zone", transaction))
            return []
        if " IN (" in statement:  # which of these keys are already there: (:k0_0, :k0_1), (:k1_0, ...)
            names = statement[len("SELECT "):statement.index(" FROM")].replace("`", "").split(", ")
            asked = [tuple(values[f"k{i}_{j}"] for j in range(len(names))) for i in range(len(values) // len(names))]
            fold = lambda key: tuple(v.lower() if isinstance(v, str) else v for v in key)  # noqa: E731
            return [dict(zip(names, have)) for have in self.existing if fold(have) in {fold(a) for a in asked}]
        raise AssertionError(f"unexpected statement: {statement}")

    def insert(self, statement, parameter_sets, transaction):
        self.log.append(("insert", transaction))
        if self.fail_on_insert and len([e for e in self.log if e[0] == "insert"]) == self.fail_on_insert:
            raise rr.RestoreError("the RDS Data API refused: Duplicate entry")
        self.pending.append((statement, parameter_sets))

    def begin(self):
        self.log.append(("begin", "tx-1"))
        return "tx-1"

    def commit(self, transaction):
        self.log.append(("commit", transaction))
        self.inserted, self.pending = self.inserted + self.pending, []

    def rollback(self, transaction):
        self.log.append(("rollback", transaction))
        self.pending = []


def write_csv(text):
    file = tempfile.NamedTemporaryFile("w", suffix=".csv", delete=False, encoding="utf-8")
    file.write(text)
    file.close()
    return file.name


class ReadingTheFile(unittest.TestCase):
    def read(self, text, max_mb=1):
        path = write_csv(text)
        try:
            return rr.read_csv(path, max_mb)
        finally:
            os.unlink(path)

    def test_the_reader_follows_rfc_4180(self):
        self.assertEqual(rr.parse_csv('a,"b,c",\r\n"",d\n'),
                         [[("a", False), ("b,c", True), ("", False)], [("", True), ("d", False)]])
        for broken in ('"never closed\n', '"closed"then more\n'):
            with self.assertRaises(ValueError, msg=broken):
                rr.parse_csv(broken)

    def test_unquoted_empty_is_null_and_quoted_empty_is_text(self):
        header, rows = self.read('a,b,c\n"x",,""\n')
        self.assertEqual((header, rows), (["a", "b", "c"], [{"a": "x", "b": None, "c": ""}]))

    def test_a_spreadsheet_byte_order_mark_and_a_blank_last_line(self):
        self.assertEqual(self.read("﻿a\n1\n\n")[1], [{"a": "1"}])

    def test_the_file_boundary_refuses_what_it_cant_trust(self):
        cases = {
            "too few fields": ("a,b\n1\n", "record 2 has 1 fields, the header has 2"),
            "too many fields": ("a,b\n1,2,3\n", "record 2 has 3 fields, the header has 2"),
            "a repeated column": ("a,A\n1,2\n", "names 'a' twice"),
            "a broken quote": ('a\n"x\n', "malformed"),
            "no rows": ("a,b\n", "no rows"),
        }
        for name, (text, message) in cases.items():
            with self.subTest(name), self.assertRaises(rr.RestoreError) as caught:
                self.read(text)
            self.assertIn(message, str(caught.exception))

    def test_a_file_that_isnt_utf_8(self):
        path = tempfile.NamedTemporaryFile("wb", suffix=".csv", delete=False).name
        with open(path, "wb") as file:
            file.write("a\nCafé\n".encode("latin-1"))
        try:
            with self.assertRaises(rr.RestoreError) as caught:
                rr.read_csv(path, 1)
        finally:
            os.unlink(path)
        self.assertIn("isn't UTF-8", str(caught.exception))

    def test_a_file_over_the_size_limit(self):
        with self.assertRaises(rr.RestoreError) as caught:
            self.read("a\n" + "x" * 2_000_000 + "\n", max_mb=1)
        self.assertIn("MB", str(caught.exception))

    def test_a_missing_file(self):
        with self.assertRaises(rr.RestoreError) as caught:
            rr.read_csv("/nonexistent/restored.csv", 1)
        self.assertIn("not found", str(caught.exception))


class TheTableDescribesItself(unittest.TestCase):
    def test_columns_and_key_come_from_information_schema(self):
        columns, key = rr.describe_table(FakeDatabase({"orders": ORDERS}, {"orders": ["id"]}), "orders")
        self.assertEqual([c.name for c in columns], [c["name"] for c in ORDERS])
        self.assertEqual(key, ["id"])

    def test_a_missing_table_or_key_stops(self):
        db = FakeDatabase({"orders": ORDERS}, {})
        for table, message in (("nope", "no table nope"), ("orders", "no primary key")):
            with self.subTest(table), self.assertRaises(rr.RestoreError) as caught:
                rr.describe_table(db, table)
            self.assertIn(message, str(caught.exception))

    def test_an_unsafe_table_name_stops_before_any_query(self):
        with self.assertRaises(rr.RestoreError):
            rr.describe_table(FakeDatabase({}, {}), "orders; DROP TABLE orders")


class CheckingEveryRow(unittest.TestCase):
    def columns(self, table, key):
        return rr.describe_table(FakeDatabase({"t": table}, {"t": key}), "t")

    def test_the_real_clumio_file_reads_back_exactly(self):
        # Downloaded from a live record restore (2026-10-24): every value quoted, NULL as an empty
        # unquoted field, empty text as "", placed_at in microseconds since 1970 (UTC).
        columns, key = self.columns(ORDERS, ["id"])
        header, rows = rr.read_csv(os.path.join(HERE, "fixtures", "record-restore-orders-6-to-10.csv"), 1)
        checked = {r["id"]: r for r in rr.check_rows(columns, key, header, rows)}
        self.assertEqual(sorted(checked), [6, 7, 8, 9, 10])
        self.assertIsNone(checked[7]["note"])   # NULL stays NULL
        self.assertEqual(checked[8]["note"], "")  # empty text stays empty
        self.assertEqual(checked[9]["note"], 'Leave at the door, "side gate"\nCall on arrival')
        self.assertEqual(checked[6]["placed_at"], "2026-01-01 00:42:00.006")
        self.assertEqual(checked[6]["total"], "222.50")

    def test_another_table_with_other_types_needs_no_code(self):
        columns, key = self.columns(SHIPMENTS, ["region", "number"])
        header = ["region", "number", "weight", "label", "shipped_on", "ratio", "seen_at"]
        rows = [{"region": "MY", "number": "9007199254740993", "weight": "12.5", "label": "", "shipped_on": "2026-10-24",
                 "ratio": "0.25", "seen_at": "1761300000000000"},
                {"region": "SG", "number": "7", "weight": None, "label": None, "shipped_on": "2026-01-02",
                 "ratio": None, "seen_at": None}]
        checked = rr.check_rows(columns, key, header, rows)
        self.assertEqual(checked[0], {"region": "MY", "number": 9007199254740993, "weight": "12.50", "label": "",
                                      "shipped_on": "2026-10-24", "ratio": 0.25, "seen_at": "2025-10-24 10:00:00"})
        self.assertEqual(checked[1]["weight"], None)

    def test_times_in_every_form_clumio_or_iso_writes(self):
        columns, key = self.columns(ORDERS, ["id"])
        placed_at = next(c for c in columns if c.name == "placed_at")
        for written in ("1767229800010000", "2026-01-01T01:10:00.010Z", "2026-01-01 01:10:00.010000",
                        "2026-01-01T09:10:00.010+08:00"):
            self.assertEqual(rr.read_value(placed_at, written, 2), "2026-01-01 01:10:00.010", written)

    def test_values_that_dont_fit_stop_and_name_where(self):
        columns, key = self.columns(SHIPMENTS, ["region", "number"])
        good = {"region": "MY", "number": "1", "weight": "1.00", "label": "a", "shipped_on": "2026-10-24",
                "ratio": "1", "seen_at": "2026-10-24 10:00:00"}
        cases = {
            "not a whole number": ({"number": "1.5"}, "number"),
            "quoted empty in a number": ({"number": ""}, "number"),
            "too many digits": ({"weight": "1234.5"}, "weight"),
            "too many decimals": ({"weight": "1.234"}, "weight"),
            "text too long": ({"label": "abcdef"}, "label"),
            "NULL where NOT NULL": ({"region": None}, "region"),
            "not a date": ({"shipped_on": "yesterday"}, "shipped_on"),
            "a time far past 9999": ({"seen_at": "99999999999999999999"}, "seen_at"),
            "an ISO time that overflows": ({"seen_at": "9999-12-31T23:59:59-01:00"}, "seen_at"),
            "not a number": ({"ratio": "many"}, "ratio"),
        }
        header = list(good)
        for name, (change, column) in cases.items():
            with self.subTest(name), self.assertRaises(rr.RestoreError) as caught:
                rr.check_rows(columns, key, header, [dict(good, **change)])
            self.assertIn(f"row 2, {column}", str(caught.exception))

    def test_a_time_window_catches_milliseconds_read_as_microseconds(self):
        # 1767229800010 is milliseconds; read as microseconds it lands in January 1970.
        columns, key = self.columns(ORDERS, ["id"])
        placed_at = next(c for c in columns if c.name == "placed_at")
        with self.assertRaises(rr.RestoreError):
            rr.read_value(placed_at, "1767229800010", 2, earliest="2000-01-01")

    def test_columns_must_match_the_table(self):
        columns, key = self.columns(SHIPMENTS[:2], ["region", "number"])
        for header, message in ((["region"], "lacks number"), (["region", "number", "extra"], "has 'extra'")):
            with self.subTest(message), self.assertRaises(rr.RestoreError) as caught:
                rr.check_rows(columns, key, header, [{h: "1" for h in header}])
            self.assertIn(message, str(caught.exception))

    def test_unsupported_types_stop_naming_the_type(self):
        for column in ({"name": "doc", "type": "json"}, {"name": "at", "type": "datetime", "time_digits": 6}):
            table = [dict(SHIPMENTS[1]), dict({"nullable": "YES", "length": None, "precision": None, "scale": None,
                                              "time_digits": None}, **column)]
            with self.subTest(column["name"]), self.assertRaises(rr.RestoreError) as caught:
                self.columns(table, ["number"])
            self.assertIn(column["name"], str(caught.exception))

    def test_repeats_read_once_and_conflicts_stop(self):
        columns, key = self.columns(SHIPMENTS[:2], ["region", "number"])
        header = ["region", "number"]
        same = rr.check_rows(columns, key, header, [{"region": "MY", "number": "010"}, {"region": "MY", "number": "10"}])
        self.assertEqual(len(same), 1)  # 010 and 10 are the same key
        columns, key = self.columns(SHIPMENTS[:4], ["region", "number"])
        header = ["region", "number", "weight", "label"]
        with self.assertRaises(rr.RestoreError) as caught:
            rr.check_rows(columns, key, header, [{"region": "MY", "number": "1", "weight": "1", "label": "a"},
                                                 {"region": "MY", "number": "1", "weight": "2", "label": "a"}])
        self.assertIn("two different rows", str(caught.exception))


class CopyingOnlyWhatsMissing(unittest.TestCase):
    def setup(self, existing):
        db = FakeDatabase({"t": SHIPMENTS[:2]}, {"t": ["region", "number"]}, existing)
        columns, key = rr.describe_table(db, "t")
        rows = rr.check_rows(columns, key, ["region", "number"],
                             [{"region": "MY", "number": "1"}, {"region": "MY", "number": "2"}])
        return db, columns, key, rows

    def test_rows_already_there_are_left_as_they_are(self):
        db, columns, key, rows = self.setup(existing={("MY", 1)})
        result = rr.copy_missing(db, "t", columns, key, rows)
        self.assertEqual(result, (1, 1))  # 1 missing and copied, 1 already there
        statement, parameter_sets = db.inserted[0]
        self.assertEqual(statement, "INSERT INTO `t` (`region`, `number`) VALUES (:region, :number)")
        self.assertEqual(parameter_sets, [[{"name": "region", "value": {"stringValue": "MY"}},
                                           {"name": "number", "value": {"longValue": 2}}]])

    def test_check_mode_writes_nothing(self):
        db, columns, key, rows = self.setup(existing=set())
        self.assertEqual(rr.copy_missing(db, "t", columns, key, rows, write=False), (2, 0))
        self.assertEqual(db.inserted, [])

    def test_parameters_carry_each_type_and_null(self):
        db = FakeDatabase({"t": SHIPMENTS}, {"t": ["region", "number"]})
        columns, _ = rr.describe_table(db, "t")
        row = {"region": "MY", "number": 1, "weight": "12.50", "label": None, "shipped_on": "2026-10-24",
               "ratio": 0.25, "seen_at": "2026-10-24 10:00:00"}
        values = {p["name"]: p for p in rr.parameters(columns, row)}
        self.assertEqual(values["weight"], {"name": "weight", "value": {"stringValue": "12.50"}, "typeHint": "DECIMAL"})
        self.assertEqual(values["label"], {"name": "label", "value": {"isNull": True}})
        self.assertEqual(values["shipped_on"]["typeHint"], "DATE")
        self.assertEqual(values["seen_at"]["typeHint"], "TIMESTAMP")
        self.assertEqual(values["ratio"], {"name": "ratio", "value": {"doubleValue": 0.25}})


class AllOrNothing(unittest.TestCase):
    """MySQL is the final judge of every value; one transaction makes its verdict all or nothing."""

    def rows(self, count):
        return [{"region": "MY", "number": n} for n in range(1, count + 1)]

    def test_a_refused_batch_undoes_every_batch(self):
        db = FakeDatabase({"t": SHIPMENTS[:2]}, {"t": ["region", "number"]}, fail_on_insert=2)
        columns, key = rr.describe_table(db, "t")
        with self.assertRaises(rr.RestoreError) as caught:
            rr.copy_missing(db, "t", columns, key, self.rows(1000), batch_bytes=2_000)  # small batches: several
        self.assertIn("Duplicate entry", str(caught.exception))
        self.assertEqual(db.inserted, [])
        self.assertIn(("rollback", "tx-1"), db.log)

    def test_a_database_not_in_strict_mode_stops_before_writing(self):
        db = FakeDatabase({"t": SHIPMENTS[:2]}, {"t": ["region", "number"]}, strict=False)
        columns, key = rr.describe_table(db, "t")
        with self.assertRaises(rr.RestoreError) as caught:
            rr.copy_missing(db, "t", columns, key, self.rows(2))
        self.assertIn("strict SQL mode", str(caught.exception))
        self.assertFalse([e for e in db.log if e[0] == "insert"])

    def test_times_are_written_in_utc_inside_the_transaction(self):
        db = FakeDatabase({"t": SHIPMENTS[:2]}, {"t": ["region", "number"]})
        columns, key = rr.describe_table(db, "t")
        rr.copy_missing(db, "t", columns, key, self.rows(2))
        self.assertEqual([e for e in db.log if e[0] != "insert"][:3], [("begin", "tx-1"), ("time zone", "tx-1"), ("commit", "tx-1")])
        self.assertTrue(all(t == "tx-1" for kind, t in db.log if kind == "insert"))

    def test_batches_stay_under_the_size_limit(self):
        db = FakeDatabase({"t": SHIPMENTS[:2]}, {"t": ["region", "number"]})
        columns, key = rr.describe_table(db, "t")
        rr.copy_missing(db, "t", columns, key, self.rows(1000), batch_bytes=5_000)
        import json
        self.assertTrue(all(len(json.dumps(sets)) <= 5_000 for _, sets in db.inserted))
        self.assertEqual(sum(len(sets) for _, sets in db.inserted), 1000)

    def test_a_key_the_database_compares_differently_stops(self):
        # MySQL's default collation ignores case: "my" is already there as far as the database knows.
        db = FakeDatabase({"t": SHIPMENTS[:2]}, {"t": ["region", "number"]}, existing={("my", 1)})
        columns, key = rr.describe_table(db, "t")
        with self.assertRaises(rr.RestoreError) as caught:
            rr.copy_missing(db, "t", columns, key, self.rows(1))
        self.assertIn("compares keys differently", str(caught.exception))
        self.assertEqual(db.inserted, [])

    def test_keys_as_the_data_api_returns_them_match(self):
        # The Data API returns a DECIMAL as text and a BIGINT as a number (seen live).
        table = [dict(SHIPMENTS[2], nullable="NO"), SHIPMENTS[1]]
        db = FakeDatabase({"t": table}, {"t": ["weight", "number"]}, existing={("12.50", 7)})
        columns, key = rr.describe_table(db, "t")
        rows = rr.check_rows(columns, key, ["weight", "number"], [{"weight": "12.5", "number": "7"}])
        self.assertEqual(rr.copy_missing(db, "t", columns, key, rows), (0, 1))


class OnlyTrueMessages(unittest.TestCase):
    """Findings that could write wrong data or print a false message (the rule after review)."""

    def test_timestamp_and_float_keys_are_refused(self):
        # A timestamp key is looked up in the cluster's time zone; a float key doesn't compare exactly.
        for column in (SHIPMENTS[6], SHIPMENTS[5]):
            db = FakeDatabase({"t": [dict(column, nullable="NO")]}, {"t": [column["name"]]})
            with self.subTest(column["name"]), self.assertRaises(rr.RestoreError) as caught:
                rr.describe_table(db, "t")
            self.assertIn("primary key", str(caught.exception))

    def test_a_lost_commit_response_doesnt_claim_nothing_was_written(self):
        db = FakeDatabase({"t": SHIPMENTS[:2]}, {"t": ["region", "number"]})

        def lost(_transaction):
            raise rr.RestoreError("the RDS Data API refused: connection reset")
        db.commit = lost
        path = write_csv("region,number\nMY,1\n")
        out, err = io.StringIO(), io.StringIO()
        try:
            with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
                code = rr.main(["--csv", path, "--table", "t"], database=db)
        finally:
            os.unlink(path)
        self.assertEqual(code, 1)
        self.assertIn("outcome is unknown", err.getvalue())
        self.assertNotIn("Nothing was written", err.getvalue())

    def test_a_request_too_large_for_this_computer_is_a_named_stop(self):
        saved = rr.subprocess.run

        def too_long(*_a, **_k):
            raise OSError(7, "Argument list too long")
        rr.subprocess.run = too_long
        try:
            with self.assertRaises(rr.RestoreError) as caught:
                rr.DataApi("arn:cluster", "arn:secret", "orders", "ap-southeast-2").query("SELECT 1")
        finally:
            rr.subprocess.run = saved
        self.assertIn("too large", str(caught.exception))


class SmallBoundaries(unittest.TestCase):
    def test_numbers_python_reads_but_mysql_wouldnt_mean_the_same(self):
        ratio = rr.Column("ratio", "double", "float", True, None, 22, None, 0)
        with self.assertRaises(rr.RestoreError):
            rr.read_value(ratio, "1_000", 2)
        self.assertEqual(rr.read_value(ratio, "-2.5e3", 2), -2500.0)

    def test_a_time_before_1970(self):
        at = rr.Column("born", "datetime", "time", False, None, None, None, 0)
        self.assertEqual(rr.read_value(at, "-86400000000", 2), "1969-12-31 00:00:00")

    def test_header_names_are_shown_safely(self):
        path = write_csv("\x1b[31mred,\x1b[31mred\n1,2\n")
        try:
            with self.assertRaises(rr.RestoreError) as caught:
                rr.read_csv(path, 1)
        finally:
            os.unlink(path)
        self.assertNotIn("\x1b", str(caught.exception))


class TheCommandLine(unittest.TestCase):
    def run_main(self, argv, db):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = rr.main(argv, database=db)
        return code, out.getvalue(), err.getvalue()

    def test_check_then_copy(self):
        path = write_csv("region,number\nMY,1\nMY,2\n")
        db = FakeDatabase({"t": SHIPMENTS[:2]}, {"t": ["region", "number"]}, {("MY", 1)})
        try:
            code, out, _ = self.run_main(["--check", "--csv", path, "--table", "t"], db)
            self.assertEqual((code, db.inserted), (0, []))
            self.assertIn("checked 2 rows: 1 missing from t, 1 already there. Nothing was written (--check)", out)
            code, out, _ = self.run_main(["--csv", path, "--table", "t"], db)
            self.assertEqual(code, 0)
            self.assertIn("copied 1 rows into t; 1 were already there", out)
        finally:
            os.unlink(path)

    def test_a_stop_is_one_line_and_exit_code_1(self):
        path = write_csv("region,number\nMY,x\n")
        db = FakeDatabase({"t": SHIPMENTS[:2]}, {"t": ["region", "number"]})
        try:
            code, _, err = self.run_main(["--csv", path, "--table", "t"], db)
        finally:
            os.unlink(path)
        self.assertEqual(code, 1)
        self.assertTrue(err.startswith("STOP: row 2, number"), err)
        self.assertIn("Nothing was written", err)
        self.assertEqual(db.inserted, [])


if __name__ == "__main__":
    unittest.main()
