"""Tests for the lab's core logic: the check's verdict, the safety gate, the scorecard, and the CSV a
record restore returns. Standard library only. Run from the workshop folder:

    python3 -m unittest discover -s tests

No AWS or Clumio calls: every function tested here is pure, or reads only local files.
"""

import argparse
import contextlib
import importlib.machinery
import io
import importlib.util
import json
import os
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
LAB_PATH = os.path.join(HERE, "..", "lab")
loader = importlib.machinery.SourceFileLoader("lab", LAB_PATH)
lab = importlib.util.module_from_spec(importlib.util.spec_from_loader("lab", loader))
loader.exec_module(lab)

ALL_ORDERS = set(range(1, 1001))
ALL_ROWS = {i: lab.order_for(i) for i in ALL_ORDERS}  # the database as ./lab seed loads it
INTACT_DOCUMENTS = {i: lab.sha256(lab.document_for(i)) for i in ALL_ORDERS}


class SampleData(unittest.TestCase):
    """Every run and every check must expect the same bytes, or a recovery can't be judged."""

    def test_document_is_fixed(self):
        # Worked by hand from the format: quantity 1 + 1 % 5 = 2, SKU (1 * 7) % 97 = 7.
        self.assertEqual(lab.document_for(1), '{"customer": "Customer 0001", "document": "delivery note", '
                         '"items": [{"quantity": 2, "sku": "SKU-007"}], "order": 1, "reference": "DN-00001"}')
        self.assertEqual(lab.sha256(lab.document_for(1)), "a97db86c829bd4080bfe335d002ae4baaa0d3f47cd5441238aacc170371d224b")

    def test_order_total_is_fixed(self):
        self.assertEqual(lab.order_for(10)["total"], "370.50")  # (10 * 37) % 5000 = 370

    def test_awkward_values_are_there_to_test_an_export(self):
        self.assertIsNone(lab.order_for(7)["note"])                      # 7 % 7 = 0: NULL
        self.assertEqual(lab.order_for(8)["note"], "")                   # 8 % 7 = 1: empty, not NULL
        self.assertEqual(lab.order_for(9)["note"], 'Leave at the door, "side gate"\nCall on arrival')
        self.assertEqual(lab.order_for(10)["note"], "  spaces at both ends  ")
        self.assertEqual(lab.order_for(10)["customer"], "Lim Mei Ling 林美玲 #0010")
        self.assertEqual(lab.order_for(10)["placed_at"], "2026-01-01 01:10:00.010")  # 70 minutes, 10 ms

    def test_totals_the_archive_must_match(self):
        # The figures Module 4 compares with the archive's own SQL.
        from decimal import Decimal
        orders = [lab.order_for(i) for i in lab.ORDER_IDS]
        self.assertEqual(sum(Decimal(o["total"]) for o in orders), Decimal("2419000.00"))
        self.assertEqual(sum(o["note"] is None for o in orders), 142)

    def test_the_bad_deployment_damages_what_the_guide_says(self):
        self.assertEqual(len(lab.DELETED_BY_DEPLOY), 100)
        self.assertEqual(len(lab.OVERWRITTEN_BY_DEPLOY), 50)
        self.assertNotIn(lab.CONTROL_ORDER, lab.DELETED_BY_DEPLOY + lab.OVERWRITTEN_BY_DEPLOY)


class Judge(unittest.TestCase):
    """The check's verdict, the workshop's acceptance test."""

    def test_everything_intact_is_healthy(self):
        findings = {}
        self.assertTrue(lab.judge(dict(ALL_ROWS), dict(INTACT_DOCUMENTS), findings))
        self.assertEqual(findings, {"orders missing": 0, "orders changed": 0, "documents missing": 0,
                                    "documents changed": 0, "control order 1": "intact"})

    def test_after_the_bad_deployment(self):
        documents = dict(INTACT_DOCUMENTS)
        for i in lab.OVERWRITTEN_BY_DEPLOY:
            documents[i] = "0" * 64
        findings = {}
        self.assertFalse(lab.judge({i: r for i, r in ALL_ROWS.items() if i not in lab.DELETED_BY_DEPLOY}, documents, findings))
        self.assertEqual((findings["orders missing"], findings["documents changed"]), (100, 50))
        self.assertEqual(findings["orders changed"], 0)  # a deleted row is missing, not changed
        self.assertEqual(findings["control order 1"], "intact")

    def test_one_missing_document_is_broken(self):
        documents = dict(INTACT_DOCUMENTS)
        del documents[500]
        self.assertFalse(lab.judge(dict(ALL_ROWS), documents, {}))

    def test_a_changed_control_order_is_broken(self):
        documents = dict(INTACT_DOCUMENTS)
        documents[lab.CONTROL_ORDER] = "0" * 64
        findings = {}
        self.assertFalse(lab.judge(dict(ALL_ROWS), documents, findings))
        self.assertEqual(findings["control order 1"], "BROKEN")

    def test_a_changed_schema_is_broken(self):
        findings = {"schema": "different: index orders.by_placed_at.placed_at missing"}
        self.assertFalse(lab.judge(dict(ALL_ROWS), dict(INTACT_DOCUMENTS), findings))

    def test_totals_are_information_not_a_verdict(self):
        findings = {"schema": "matches", "totals": {"orders": 1000, "total": "2419000.00", "null_notes": 142}}
        self.assertTrue(lab.judge(dict(ALL_ROWS), dict(INTACT_DOCUMENTS), findings))

    def test_everything_deleted_is_broken(self):
        findings = {"database": "missing", "documents bucket": "missing"}
        self.assertFalse(lab.judge(None, None, findings))
        self.assertEqual(findings["control order 1"], "BROKEN")


class SchemaDifference(unittest.TestCase):
    SAVED = {"columns": [["orders", "id", "int", "NO"], ["orders", "note", "text", "YES"]],
             "indexes": [["orders", "PRIMARY", "id", 0], ["orders", "by_placed_at", "placed_at", 1]]}

    def test_the_same_schema_matches(self):
        self.assertEqual(lab.schema_difference(self.SAVED, json.loads(json.dumps(self.SAVED))), [])

    def test_a_lost_index_and_a_changed_type_are_named(self):
        current = {"columns": [["orders", "id", "int", "NO"], ["orders", "note", "varchar(255)", "YES"]],
                   "indexes": [["orders", "PRIMARY", "id", 0]]}
        difference = lab.schema_difference(self.SAVED, current)
        self.assertIn("index orders by_placed_at placed_at 1 missing", difference)
        self.assertIn("column orders note text YES missing", difference)
        self.assertIn("column orders note varchar(255) YES added", difference)

    def test_a_change_in_nullability_is_named(self):
        current = {"columns": [["orders", "id", "int", "NO"], ["orders", "note", "text", "NO"]],
                   "indexes": self.SAVED["indexes"]}
        self.assertEqual(lab.schema_difference(self.SAVED, current),
                         ["column orders note text YES missing", "column orders note text NO added"])


class Readiness(unittest.TestCase):
    """The gate before an incident: Clumio must hold copies of the loaded data."""

    SEEDED = "2026-10-20T09:42:17+00:00"

    def test_ready_after_both_recovery_points(self):
        self.assertTrue(lab.readiness(self.SEEDED, {"SecureVault Standard": "2026-10-20T10:02:41.123Z"},
                                      "2026-10-20T10:05:00Z")[0])

    def test_not_ready_before_clumio_finds_the_database(self):
        self.assertFalse(lab.readiness(self.SEEDED, None, "2026-10-20T10:05:00Z")[0])

    def test_not_ready_without_a_documents_recovery_point(self):
        self.assertFalse(lab.readiness(self.SEEDED, {"SecureVault Standard": "2026-10-20T10:02:41Z"}, "")[0])

    def test_with_the_archive_on_an_archive_point_is_needed_too(self):
        standard = {"SecureVault Standard": "2026-10-20T10:02:41Z"}
        self.assertFalse(lab.readiness(self.SEEDED, standard, "2026-10-20T10:05:00Z", needs_archive=True)[0])
        both = dict(standard, **{"SecureVault Archive": "2026-10-20T10:40:00Z"})
        self.assertTrue(lab.readiness(self.SEEDED, both, "2026-10-20T10:05:00Z", needs_archive=True)[0])

    def test_not_ready_when_the_recovery_point_predates_the_data(self):
        self.assertFalse(lab.readiness(self.SEEDED, {"SecureVault Standard": "2026-10-20T09:00:00Z"},
                                       "2026-10-20T10:05:00Z")[0])


class InsertParameters(unittest.TestCase):
    def note(self, order):
        return next(p["value"] for p in lab.insert_parameters(order) if p["name"] == "note")

    def test_a_none_note_goes_in_as_sql_null_and_empty_stays_empty(self):
        self.assertEqual(self.note(lab.order_for(7)), {"isNull": True})
        self.assertEqual(self.note(lab.order_for(8)), {"stringValue": ""})


class Totals(unittest.TestCase):
    def test_an_empty_table_reads_as_zero(self):
        self.assertEqual(lab.describe_totals({"orders": 0, "total": None, "null_notes": None}),
                         "0 orders, 0 in total, 0 notes NULL")


class Scorecard(unittest.TestCase):
    def events(self):
        return [
            {"at": "2026-10-20T10:15:03+00:00", "event": "break deploy"},
            {"at": "2026-10-20T10:16:00+00:00", "event": "check", "state": "BROKEN",
             "findings": {"schema": "matches", "totals": {"orders": 900},
                          "orders missing": 100, "documents changed": 50, "control order 1": "intact"}},
            {"at": "2026-10-20T12:29:03+00:00", "event": "check", "state": "HEALTHY", "findings": {}},
            {"at": "2026-10-20T13:00:00+00:00", "event": "break everything"},
        ]

    def test_time_to_healthy_and_damage(self):
        first, second = lab.incident_scorecard(self.events())
        self.assertEqual(first, ("Bad deployment", "orders missing: 100, documents changed: 50", "2 h 14 min"))
        self.assertEqual(second, ("Everything deleted", "not checked", "not HEALTHY yet"))

    def test_minutes_only(self):
        self.assertEqual(lab.format_duration(14 * 60), "14 min")

    def at(self, minute, event, **details):
        return {"at": f"2026-10-25T10:{minute:02d}:00+00:00", "event": event, **details}

    def test_down_ends_an_incident_that_was_never_recovered(self):
        # A fresh deployment's HEALTHY check must not count as this incident's recovery.
        events = [self.at(0, "break everything"), self.at(5, "check", state="BROKEN", findings={"database": "missing"}),
                  self.at(9, "down"), self.at(40, "seed"), self.at(45, "check", state="HEALTHY", findings={})]
        self.assertEqual(lab.incident_scorecard(events),
                         [("Everything deleted", "database: missing", "not recovered (./lab down)")])

    def test_healthy_without_a_broken_check_means_no_damage_was_found(self):
        # The break was interrupted before its damage: the next check found nothing to recover.
        events = [self.at(0, "break deploy"), self.at(1, "check", state="HEALTHY", findings={})]
        self.assertEqual(lab.incident_scorecard(events), [("Bad deployment", "no damage found", "not applicable")])

    def test_a_check_after_healthy_belongs_to_no_incident(self):
        events = [self.at(0, "break deploy"), self.at(1, "check", state="BROKEN", findings={"orders missing": 100}),
                  self.at(20, "check", state="HEALTHY", findings={}),
                  self.at(30, "check", state="BROKEN", findings={"documents missing": 1})]
        self.assertEqual(lab.incident_scorecard(events), [("Bad deployment", "orders missing: 100", "20 min")])

    def test_an_incident_still_open_when_the_next_starts(self):
        # The gates can't write this log; an older lab could. The first is named, not counted as recovered.
        events = [self.at(0, "break deploy"), self.at(1, "check", state="BROKEN", findings={"orders missing": 100}),
                  self.at(5, "break everything")]
        self.assertEqual(lab.incident_scorecard(events)[0],
                         ("Bad deployment", "orders missing: 100", "not recovered before the next incident"))


class RecordRestoreCsv(unittest.TestCase):
    HEADER = "id,customer,total,status,note,placed_at,document_key,document_sha256\n"
    ROW = ('10,"Lim Mei Ling 林美玲 #0010",370.50,delivered,"  spaces at both ends  ",2026-01-01 01:10:00.010,'
           "documents/order-10.json," + "a" * 64 + "\n")

    def read(self, text):
        with tempfile.NamedTemporaryFile("w", suffix=".csv", delete=False, encoding="utf-8") as file:
            file.write(text)
        try:
            return lab.read_orders_csv(file.name)
        finally:
            os.unlink(file.name)

    def test_a_good_file_keeps_text_exactly(self):
        order = self.read(self.HEADER + self.ROW)[0]
        self.assertEqual((order["id"], order["note"]), ("10", "  spaces at both ends  "))
        self.assertEqual(order["customer"], "Lim Mei Ling 林美玲 #0010")

    def test_a_newline_inside_a_quoted_note(self):
        row = self.ROW.replace('"  spaces at both ends  "', '"Leave at the door, ""side gate""\nCall on arrival"')
        self.assertEqual(self.read(self.HEADER + row)[0]["note"], 'Leave at the door, "side gate"\nCall on arrival')

    def test_iso_times_are_read_into_milliseconds(self):
        for written in ("2026-01-01T01:10:00.010Z", "2026-01-01 01:10:00.010000", "2026-01-01T09:10:00.010+08:00"):
            row = self.ROW.replace("2026-01-01 01:10:00.010", written)
            self.assertEqual(self.read(self.HEADER + row)[0]["placed_at"], "2026-01-01 01:10:00.010", written)

    def test_a_spreadsheet_byte_order_mark(self):
        self.assertEqual(len(self.read("﻿" + self.HEADER + self.ROW)), 1)

    def test_a_repeated_row_counts_once(self):
        self.assertEqual(len(self.read(self.HEADER + self.ROW + self.ROW)), 1)

    def test_the_real_clumio_file_gives_back_exactly_what_was_loaded(self):
        # Downloaded from a live record restore (2026-10-24): every value quoted, NULL as an empty
        # unquoted field, empty text as "", placed_at in microseconds since 1970 (UTC).
        orders = lab.read_orders_csv(os.path.join(HERE, "fixtures", "record-restore-orders-6-to-10.csv"))
        rows = {int(o["id"]): o for o in orders}
        self.assertEqual(sorted(rows), [6, 7, 8, 9, 10])
        self.assertIsNone(rows[7]["note"])   # NULL stays NULL
        self.assertEqual(rows[8]["note"], "")  # empty text stays empty
        self.assertEqual(rows[9]["note"], 'Leave at the door, "side gate"\nCall on arrival')
        self.assertEqual(rows[6]["placed_at"], "2026-01-01 00:42:00.006")
        self.assertEqual(lab.compare_rows(rows), 0)  # every value exactly as ./lab seed loaded it

    def test_unquoted_empty_is_null_and_quoted_empty_is_text(self):
        null_note = self.ROW.replace('"  spaces at both ends  "', "")
        empty_note = self.ROW.replace('"  spaces at both ends  "', '""')
        self.assertIsNone(self.read(self.HEADER + null_note)[0]["note"])
        self.assertEqual(self.read(self.HEADER + empty_note)[0]["note"], "")

    def test_the_reader_follows_rfc_4180(self):
        self.assertEqual(lab.csv_records('a,"b,c",\r\n"",d\n'),
                         [[("a", False), ("b,c", True), ("", False)], [("", True), ("d", False)]])
        for broken in ('"never closed\n', '"closed"then more\n'):
            with self.assertRaises(ValueError, msg=broken):
                lab.csv_records(broken)

    def test_microsecond_times_are_read_into_milliseconds(self):
        row = self.ROW.replace("2026-01-01 01:10:00.010", '"1767229800010000"')
        self.assertEqual(self.read(self.HEADER + row)[0]["placed_at"], "2026-01-01 01:10:00.010")

    def test_the_file_boundary_refuses_what_it_cant_trust(self):
        # Each would otherwise crash with a traceback, or let a guessed value reach the database.
        short_row = self.ROW.replace(',"  spaces at both ends  "', "", 1)  # one field fewer than the header
        shape = {  # each must stop for its own reason, not because a later check trips on shifted values
            "a row with too few fields": (self.HEADER + short_row, "record 2 has 7 fields, the header has 8"),
            "a row with an extra field": (self.HEADER + self.ROW.replace("\n", ',"extra"\n'), "record 2 has 9 fields, the header has 8"),
            "a repeated column name": (self.HEADER.replace("\n", ",note\n") + self.ROW.replace("\n", ',""\n'), "names note twice"),
        }
        for name, (text, message) in shape.items():
            error = io.StringIO()
            with self.subTest(name), contextlib.redirect_stderr(error), self.assertRaises(SystemExit):
                self.read(text)
            self.assertIn(message, error.getvalue(), name)
        cases = {
            "a time far past year 2100": self.HEADER + self.ROW.replace("2026-01-01 01:10:00.010", "99999999999999999999"),
            "an ISO time in year 1": self.HEADER + self.ROW.replace("2026-01-01 01:10:00.010", "0001-01-01T00:00:00"),
            "an ISO time that overflows": self.HEADER + self.ROW.replace("2026-01-01 01:10:00.010", "9999-12-31T23:59:59-01:00"),
        }
        for name, text in cases.items():
            with self.subTest(name), contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
                self.read(text)

    def test_a_file_that_isnt_utf_8_stops_with_what_to_do(self):
        with tempfile.NamedTemporaryFile("wb", suffix=".csv", delete=False) as file:
            file.write((self.HEADER + self.ROW.replace("Lim Mei Ling 林美玲", "Café")).encode("latin-1"))
        error = io.StringIO()
        try:
            with contextlib.redirect_stderr(error), self.assertRaises(SystemExit):
                lab.read_orders_csv(file.name)
        finally:
            os.unlink(file.name)
        self.assertIn("isn't UTF-8", error.getvalue())

    def test_a_file_over_the_size_limit_stops(self):
        error = io.StringIO()
        with contextlib.redirect_stderr(error), self.assertRaises(SystemExit):
            self.read(self.HEADER + self.ROW * 6000)  # about 1.3 MB: far more than 1,000 orders need
        self.assertIn("MB", error.getvalue())

    def test_an_id_written_with_a_leading_zero_is_the_same_order(self):
        orders = self.read(self.HEADER + self.ROW + self.ROW.replace("10,", "010,", 1))
        self.assertEqual([o["id"] for o in orders], ["10"])

    def test_refusals(self):
        for text in ("id,customer\n10,x\n",                                 # missing columns
                     self.HEADER + self.ROW.replace("2026-01-01 01:10:00.010", "1767229800010"),  # milliseconds, not microseconds
                     self.HEADER + self.ROW.replace('"  spaces at both ends  "', '"never closed'),  # a broken quote
                     self.HEADER + self.ROW.replace("10,", "5000,", 1),      # an order the lab didn't make
                     self.HEADER + self.ROW.replace("a" * 64, "z" * 64),    # not a checksum
                     self.HEADER + self.ROW.replace("2026-01-01 01:10:00.010", "yesterday"),  # not a time
                     self.HEADER):                                           # no rows
            with self.assertRaises(SystemExit, msg=text), contextlib.redirect_stderr(io.StringIO()):
                self.read(text)


class SeedGuard(unittest.TestCase):
    """Seeding after an incident would quietly repair it, and the scorecard would lie."""

    def test_an_incident_blocks_seeding_until_down(self):
        saved = lab.EVIDENCE_DIR
        with tempfile.TemporaryDirectory() as folder:
            lab.EVIDENCE_DIR = folder
            log = os.path.join(folder, "events.jsonl")

            def write(event):
                with open(log, "a") as file:
                    file.write(json.dumps({"at": "x", "event": event}) + "\n")
            try:
                self.assertIsNone(lab.incident_since_deploy())
                write("seed")
                write("break deploy")
                self.assertEqual(lab.incident_since_deploy(), "break deploy")
                write("down")
                self.assertIsNone(lab.incident_since_deploy())
            finally:
                lab.EVIDENCE_DIR = saved


class Portal(unittest.TestCase):
    """The local portal names every state a reader can see, and answers only this computer."""

    ROW = {"id": 15, "customer": "Customer 0015", "total": "555.00", "status": "delivered",
           "document_sha256": lab.sha256(lab.document_for(15))}

    def test_every_state_is_named(self):
        found = ("found", self.ROW)
        cases = [
            (found, ("found", lab.document_for(15)), "HEALTHY", "order and document match"),
            (("missing", None), None, "BROKEN", "order missing from the database"),
            (("unavailable", None), None, "BROKEN", "database unavailable"),
            (found, ("missing", None), "BROKEN", "delivery document missing"),
            (found, ("found", lab.document_for(16)), "BROKEN", "delivery document changed"),
            (("cant_check", "AWS answered AccessDenied"), None, "CAN'T CHECK", "AWS answered AccessDenied"),
            (found, ("cant_check", "AWS answered SlowDown"), "CAN'T CHECK", "AWS answered SlowDown"),
        ]
        for order, document, state, reason in cases:
            with self.subTest(state=state, reason=reason):
                self.assertEqual(lab.judge_portal_order(order, document), (state, reason))

    def test_an_expired_sign_in_says_what_to_do(self):
        stderr = "An error occurred (ExpiredTokenException) when calling the ExecuteStatement operation: expired"
        self.assertEqual(lab.portal_failure(stderr), "your AWS sign-in expired: run aws sso login, then check again")
        self.assertEqual(lab.portal_failure("Error when retrieving token from sso: Token has expired and refresh failed"),
                         "your AWS sign-in expired: run aws sso login, then check again")
        self.assertEqual(lab.portal_failure("An error occurred (AccessDenied) when calling the GetObject operation"),
                         "AWS answered AccessDenied")
        self.assertEqual(lab.portal_failure("Read timeout on endpoint URL"), "AWS didn't answer in time")

    def test_only_order_numbers_from_1_to_1000(self):
        for raw, expected in [("10", 10), ("1", 1), ("1000", 1000), ("0", None), ("1001", None),
                              ("-1", None), ("1e3", None), ("", None), ("10; DROP", None)]:
            with self.subTest(raw=raw):
                self.assertEqual(lab.parse_order_id(raw), expected)

    def test_only_this_computer(self):
        self.assertTrue(lab.is_local_host("localhost:8080", 8080))
        self.assertTrue(lab.is_local_host("127.0.0.1:8080", 8080))
        self.assertFalse(lab.is_local_host("attacker.example:8080", 8080))  # a page rebinding its name to 127.0.0.1
        self.assertFalse(lab.is_local_host("localhost:9999", 8080))
        self.assertFalse(lab.is_local_host(None, 8080))

    def test_a_port_in_use_stops_with_what_to_do(self):
        import io, socket, contextlib
        taken = socket.socket()
        taken.bind(("127.0.0.1", 0))
        taken.listen()
        port = taken.getsockname()[1]
        error = io.StringIO()
        lab.ACCOUNT, lab.REGION = "123456789012", "ap-southeast-2"  # as load_settings() sets them
        try:
            with contextlib.redirect_stderr(error), self.assertRaises(SystemExit):
                lab.open_portal_server(port)
        finally:
            taken.close()
            lab.ACCOUNT, lab.REGION = None, None
        self.assertIn(f"port {port} is in use", error.getvalue())
        self.assertIn("--port", error.getvalue())

    def test_an_idle_browser_connection_doesnt_block_the_page(self):
        import socket, threading, urllib.request
        probe = socket.socket()
        probe.bind(("127.0.0.1", 0))
        port = probe.getsockname()[1]
        probe.close()
        lab.ACCOUNT, lab.REGION = "123456789012", "ap-southeast-2"
        server = lab.open_portal_server(port)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        idle = socket.create_connection(("127.0.0.1", port))  # a browser's preconnect: opens, sends nothing
        try:
            request = urllib.request.Request(f"http://127.0.0.1:{port}/", headers={"Host": f"localhost:{port}"})
            with urllib.request.urlopen(request, timeout=5) as response:
                self.assertEqual(response.status, 200)
        finally:
            idle.close()
            server.shutdown()
            server.server_close()
            lab.ACCOUNT, lab.REGION = None, None


class RowComparison(unittest.TestCase):
    """The check compares every row with what ./lab seed loaded. HEALTHY means exact: a NULL that
    became empty text (what a plain LOAD DATA does to Clumio's CSV) is a changed value, like any other."""

    def check(self, rows):
        findings = {}
        healthy = lab.judge(rows, dict(INTACT_DOCUMENTS), findings)
        return healthy, findings

    def test_identical_rows(self):
        healthy, findings = self.check(dict(ALL_ROWS))
        self.assertTrue(healthy)
        self.assertEqual(findings["orders changed"], 0)

    def test_null_that_became_empty_text_is_a_change(self):
        rows = {i: dict(r, note="" if r["note"] is None else r["note"]) for i, r in ALL_ROWS.items()}
        healthy, findings = self.check(rows)
        self.assertFalse(healthy)
        self.assertEqual(findings["orders changed"], "142 (note: 142)")  # 1000 // 7 = 142 NULL notes

    def test_a_changed_value_is_broken(self):
        rows = dict(ALL_ROWS)
        rows[20] = dict(rows[20], total="999.50")
        rows[30] = dict(rows[30], total="1.50")
        rows[40] = dict(rows[40], customer="Tan Wei Ming ??? #0040")  # an export that lost the Chinese characters
        healthy, findings = self.check(rows)
        self.assertFalse(healthy)
        self.assertEqual(findings["orders changed"], "3 (total: 2, customer: 1)")

    def test_empty_text_that_became_null_is_a_change(self):
        rows = dict(ALL_ROWS)
        rows[8] = dict(rows[8], note=None)  # order 8's note is empty text, not NULL
        healthy, findings = self.check(rows)
        self.assertFalse(healthy)
        self.assertEqual(findings["orders changed"], "1 (note: 1)")

    def test_equal_values_in_other_formats(self):
        # The RDS Data API returns DECIMAL as a string, the seeded form; a number must match too. A
        # DATETIME may come with fewer digits, or without milliseconds when they're zero. The T form
        # (ISO 8601, as in a CSV) costs nothing to accept.
        rows = dict(ALL_ROWS)
        rows[10] = dict(rows[10], placed_at="2026-01-01 01:10:00.01")                     # seeded 01:10:00.010
        rows[20] = dict(rows[20], total=740.5)                                            # seeded "740.50"
        rows[140] = dict(rows[140], placed_at="2026-01-01T16:20:00.140")
        rows[1000] = dict(rows[1000], placed_at="2026-01-05 20:40:01")                   # seeded 20:40:01.000
        healthy, findings = self.check(rows)
        self.assertTrue(healthy)
        self.assertEqual(findings["orders changed"], 0)

    def test_a_change_is_damage_on_the_scorecard(self):
        self.assertFalse(lab.is_fine("orders changed", "1 (note: 1)"))
        self.assertTrue(lab.is_fine("orders changed", 0))


class IncidentState(unittest.TestCase):
    """An incident is open from its break until a HEALTHY check, ./lab down, or the next incident.
    The scorecard depends on it."""

    def at(self, minute, event, **details):
        return {"at": f"2026-10-25T10:{minute:02d}:00+00:00", "event": event, **details}

    def test_first_break_records(self):
        events = [self.at(0, "seed"), self.at(5, "check", state="HEALTHY")]
        self.assertEqual(lab.incident_start(events, "break deploy"), ("record", None))

    def test_rerun_continues(self):
        events = [self.at(0, "seed"), self.at(5, "break deploy"), self.at(6, "check", state="BROKEN")]
        self.assertEqual(lab.incident_start(events, "break deploy"), ("continue", "2026-10-25T10:05:00+00:00"))

    def test_other_incident_blocked(self):
        events = [self.at(0, "seed"), self.at(5, "break deploy"), self.at(6, "check", state="BROKEN")]
        self.assertEqual(lab.incident_start(events, "break everything"), ("blocked", "break deploy"))

    def test_after_healthy_a_new_one_starts(self):
        events = [self.at(0, "seed"), self.at(5, "break deploy"), self.at(30, "check", state="HEALTHY")]
        self.assertEqual(lab.incident_start(events, "break everything"), ("record", None))
        self.assertEqual(lab.incident_start(events, "break deploy"), ("record", None))

    def test_down_closes_everything(self):
        events = [self.at(0, "seed"), self.at(5, "break deploy"), self.at(9, "down"), self.at(20, "seed")]
        self.assertEqual(lab.incident_start(events, "break everything"), ("record", None))

    def test_a_continued_incident_has_one_scorecard_row(self):
        events = [self.at(0, "seed"), self.at(5, "break everything"), self.at(40, "check", state="BROKEN",
                  findings={"database": "missing"}), self.at(59, "check", state="HEALTHY")]
        self.assertEqual(len(lab.incident_scorecard(events)), 1)


class PrepareTimeout(unittest.TestCase):
    """At the end of its wait, ./lab prepare says what AWS last answered, not only that it waited."""

    def test_the_last_answer_is_in_the_stop(self):
        import io, contextlib
        cluster = {"DBClusterArn": "arn:aws:rds:ap-southeast-2:123456789012:cluster:orders-db-restore",
                   "HttpEndpointEnabled": True, "DBClusterMembers": [{"DBInstanceIdentifier": "orders-db-restore-1"}]}
        saved = (lab.describe_cluster, lab.aws_answer, lab.WAIT_ROUNDS, lab.time.sleep, lab._secret_arn)
        lab._secret_arn = "arn:aws:secretsmanager:ap-southeast-2:123456789012:secret:orders/db-login-AbCdEf"
        lab.describe_cluster = lambda _cluster_id: cluster
        lab.aws_answer = lambda *args, absent_if=(): (None, "BadRequestException: Access denied for user 'ordersadmin'")
        lab.WAIT_ROUNDS, lab.time.sleep = 2, lambda _seconds: None
        error = io.StringIO()
        try:
            with contextlib.redirect_stderr(error), contextlib.redirect_stdout(io.StringIO()), self.assertRaises(SystemExit):
                lab.prepare("orders-db-restore")
        finally:
            lab.describe_cluster, lab.aws_answer, lab.WAIT_ROUNDS, lab.time.sleep, lab._secret_arn = saved
        self.assertIn("Access denied for user 'ordersadmin'", error.getvalue())


class IncidentFlow(unittest.TestCase):
    """./lab break runs its gates in the right order: a blocked incident changes nothing and asks
    nothing; a new one passes the readiness gate; a continued one skips it and adds no record."""

    def run_break_everything(self, events):
        calls = []
        stubs = {"read_events": lambda: events,
                 "require_recovery_points": lambda: calls.append("readiness"),
                 "confirm_by_account_id": lambda _what, _confirmed=None: calls.append("confirm"),
                 "record": lambda event, **_d: calls.append(f"record {event}"),
                 "delete_cluster": lambda *_a, **_k: calls.append("delete database"),
                 "empty_and_delete_bucket": lambda: calls.append("delete bucket"),
                 "say": lambda _message: None}
        saved = {name: getattr(lab, name) for name in stubs}
        for name, stub in stubs.items():
            setattr(lab, name, stub)
        lab.ACCOUNT = "123456789012"
        try:
            with contextlib.redirect_stderr(io.StringIO()):
                lab.break_everything()
        except SystemExit:
            calls.append("STOP")
        finally:
            for name, original in saved.items():
                setattr(lab, name, original)
            lab.ACCOUNT = None
        return calls

    def at(self, minute, event, **details):
        return {"at": f"2026-10-25T10:{minute:02d}:00+00:00", "event": event, **details}

    def test_a_new_incident_passes_the_gate_then_asks_then_records(self):
        calls = self.run_break_everything([self.at(0, "seed"), self.at(5, "check", state="HEALTHY")])
        self.assertEqual(calls, ["readiness", "confirm", "record break everything", "delete database", "delete bucket"])

    def test_a_rerun_skips_the_gate_and_the_record(self):
        # The first run deleted the database, so Clumio's readiness can't pass again: it mustn't be asked.
        calls = self.run_break_everything([self.at(0, "seed"), self.at(5, "break everything")])
        self.assertEqual(calls, ["confirm", "delete database", "delete bucket"])

    def test_a_blocked_incident_changes_and_asks_nothing(self):
        calls = self.run_break_everything([self.at(0, "seed"), self.at(5, "break deploy")])
        self.assertEqual(calls, ["STOP"])


class DeployFlow(unittest.TestCase):
    """./lab break deploy: blocked first, then readiness for a new incident, then the queryable check,
    and only then the record and the damage."""

    def run_break_deploy(self, events, is_queryable=True):
        calls = []
        stubs = {"read_events": lambda: events,
                 "require_recovery_points": lambda: calls.append("readiness"),
                 "queryable_arn": lambda _cluster: calls.append("queryable") or ("arn:cluster" if is_queryable else None),
                 "record": lambda event, **_d: calls.append(f"record {event}"),
                 "sql": lambda *_a, **_k: calls.append("delete orders"),
                 "upload_documents": lambda _texts: calls.append("overwrite documents"),
                 "say": lambda _message: None}
        saved = {name: getattr(lab, name) for name in stubs}
        for name, stub in stubs.items():
            setattr(lab, name, stub)
        try:
            with contextlib.redirect_stderr(io.StringIO()):
                lab.break_deploy()
        except SystemExit:
            calls.append("STOP")
        finally:
            for name, original in saved.items():
                setattr(lab, name, original)
        return calls

    def at(self, minute, event, **details):
        return {"at": f"2026-10-25T10:{minute:02d}:00+00:00", "event": event, **details}

    def test_a_new_incident(self):
        self.assertEqual(self.run_break_deploy([self.at(0, "seed")]),
                         ["readiness", "queryable", "record break deploy", "delete orders", "overwrite documents"])

    def test_a_database_that_cant_be_queried_records_nothing(self):
        self.assertEqual(self.run_break_deploy([self.at(0, "seed")], is_queryable=False), ["readiness", "queryable", "STOP"])

    def test_a_rerun(self):
        self.assertEqual(self.run_break_deploy([self.at(0, "seed"), self.at(5, "break deploy")]),
                         ["queryable", "delete orders", "overwrite documents"])

    def test_blocked(self):
        self.assertEqual(self.run_break_deploy([self.at(0, "seed"), self.at(5, "break everything")]), ["STOP"])


class PortalErrors(unittest.TestCase):
    """A bug in the portal shows as CAN'T CHECK with its reason, never as a stopped portal."""

    def test_an_unexpected_error_is_named(self):
        import socket, threading, urllib.request, urllib.error, io, contextlib
        probe = socket.socket()
        probe.bind(("127.0.0.1", 0))
        port = probe.getsockname()[1]
        probe.close()
        lab.ACCOUNT, lab.REGION = "123456789012", "ap-southeast-2"
        saved = lab.check_portal_order

        def broken(_cluster_arn, _order_id):
            raise ValueError("a bug")
        lab.check_portal_order = broken
        server = lab.open_portal_server(port)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        request = urllib.request.Request(f"http://127.0.0.1:{port}/api/order?order=10", headers={"Host": f"localhost:{port}"})
        terminal = io.StringIO()
        try:
            with contextlib.redirect_stderr(terminal):
                with self.assertRaises(urllib.error.HTTPError) as answer:
                    urllib.request.urlopen(request, timeout=5)
            body = json.loads(answer.exception.read())
        finally:
            server.shutdown()
            server.server_close()
            lab.check_portal_order = saved
            lab.ACCOUNT, lab.REGION = None, None
        self.assertEqual(answer.exception.code, 500)
        self.assertEqual(body["state"], "CAN'T CHECK")
        self.assertIn("ValueError", body["reason"])
        self.assertIn("ValueError: a bug", terminal.getvalue())  # the full error, in the portal's terminal

    def test_a_browser_that_goes_away_is_not_an_error(self):
        import socket, threading, urllib.request, urllib.error
        probe = socket.socket()
        probe.bind(("127.0.0.1", 0))
        port = probe.getsockname()[1]
        probe.close()
        lab.ACCOUNT, lab.REGION = "123456789012", "ap-southeast-2"
        saved = lab.check_portal_order

        def gone(_cluster_arn, _order_id):
            raise BrokenPipeError("the browser closed the tab")
        lab.check_portal_order = gone
        server = lab.open_portal_server(port)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        request = urllib.request.Request(f"http://127.0.0.1:{port}/api/order?order=10", headers={"Host": f"localhost:{port}"})
        terminal = io.StringIO()
        try:
            with contextlib.redirect_stderr(terminal):
                with self.assertRaises((urllib.error.URLError, ConnectionError)) as gone:
                    urllib.request.urlopen(request, timeout=5)
            self.assertNotIsInstance(gone.exception, urllib.error.HTTPError)  # no answer: the connection just closes
        finally:
            server.shutdown()
            server.server_close()
            lab.check_portal_order = saved
            lab.ACCOUNT, lab.REGION = None, None
        self.assertEqual(terminal.getvalue(), "")


class DataApiStarting(unittest.TestCase):
    """The RDS Data API answers "starting" for a while after it's turned on, and now and then later
    (seen live, 2026-10-24: a batch write, then reads 4 and 17 minutes after). Every Data API call waits
    through it, within WAIT_LIMIT; the readiness probe asks for the answer instead; other errors stop."""

    STARTING = "aws: [ERROR]: An error occurred (HttpEndpointNotEnabledException) when calling the ExecuteStatement operation: HttpEndpoint is being enabled for resource arn"

    def run_with(self, call, failures, failure=None, rounds=5):
        import types
        calls, waits, said = [], [], []

        def fake_run(*command, expect_failure=False):
            calls.append(command[1:3])
            if len(calls) <= failures:
                return types.SimpleNamespace(returncode=254, stdout="", stderr=failure or self.STARTING)
            return types.SimpleNamespace(returncode=0, stdout='{"formattedRecords": "[{\\"one\\": 1}]"}', stderr="")
        saved = (lab.run, lab.WAIT_ROUNDS, lab.time.sleep, lab.say, lab._secret_arn, lab.REGION)
        lab.run, lab.WAIT_ROUNDS, lab.time.sleep, lab.say = fake_run, rounds, waits.append, said.append
        lab._secret_arn, lab.REGION = "arn:aws:secretsmanager:ap-southeast-2:123456789012:secret:x", "ap-southeast-2"
        error = io.StringIO()
        try:
            with contextlib.redirect_stderr(error):
                answer = call()
        except SystemExit:
            answer = "STOP"
        finally:
            lab.run, lab.WAIT_ROUNDS, lab.time.sleep, lab.say, lab._secret_arn, lab.REGION = saved
        return answer, len(calls), len(waits), said, error.getvalue()

    def test_a_read_waits_through_starting(self):
        answer, calls, waits, said, _ = self.run_with(lambda: lab.sql("arn:cluster", "SELECT 1 AS one"), failures=2)
        self.assertEqual((answer, calls, waits), ([{"one": 1}], 3, 2))
        self.assertEqual(len(said), 1)  # one line says it's waiting, not one per round

    def test_a_batch_write_waits_too(self):
        answer, calls, waits, _, _ = self.run_with(lambda: lab.insert_orders("arn:cluster", [lab.order_for(1)]), failures=1)
        self.assertEqual((answer, calls, waits), (None, 2, 1))

    def test_the_wait_is_bounded_and_names_the_last_answer(self):
        answer, calls, _, _, error = self.run_with(lambda: lab.sql("arn:cluster", "SELECT 1"), failures=10, rounds=3)
        self.assertEqual((answer, calls), ("STOP", 3))
        self.assertIn("being enabled", error)

    def test_the_readiness_probe_asks_instead_of_waiting(self):
        cluster = {"DBClusterArn": "arn:cluster", "HttpEndpointEnabled": True, "DBClusterMembers": [{"DBInstanceIdentifier": "i"}]}
        saved = lab.describe_cluster
        lab.describe_cluster = lambda _cluster_id: cluster
        try:
            answer, calls, waits, _, _ = self.run_with(lambda: lab.query_readiness("orders-db"), failures=10)
        finally:
            lab.describe_cluster = saved
        self.assertEqual((answer[0], calls, waits), (None, 1, 0))
        self.assertIn("being enabled", answer[1])

    def test_other_services_never_wait(self):
        unavailable = "aws: [ERROR]: An error occurred (DatabaseUnavailableException) when calling the DescribeDBClusters operation"
        answer, calls, waits, _, _ = self.run_with(lambda: lab.aws("rds", "describe-db-clusters"), failures=10, failure=unavailable)
        self.assertEqual((answer, calls, waits), ("STOP", 1, 0))

    def test_other_errors_stop_at_once(self):
        denied = "aws: [ERROR]: An error occurred (AccessDeniedException) when calling the ExecuteStatement operation"
        answer, calls, waits, _, _ = self.run_with(lambda: lab.sql("arn:cluster", "SELECT 1"), failures=10, failure=denied)
        self.assertEqual((answer, calls, waits), ("STOP", 1, 0))

    def test_the_insert_never_duplicates_a_row(self):
        self.assertIn("INSERT IGNORE", lab.INSERT_ORDER_SQL)  # so a write sent again keeps rows that went in


class CheckReadsTheDatabase(unittest.TestCase):
    """./lab check doesn't probe the Data API: a probe can catch a passing "starting" answer and give
    the wrong advice. It asks AWS whether prepare is needed, then reads; the reads wait out "starting",
    and any other "not queryable" answer becomes a finding, not a crash. No status gate: a cluster that
    is "backing-up" (Clumio backing it up) serves queries, seen live."""

    READY = {"DBClusterArn": "arn:cluster", "HttpEndpointEnabled": True, "Status": "backing-up",
             "DBClusterMembers": [{"DBInstanceIdentifier": "orders-db-1"}]}

    def read(self, cluster, failures=0, failure=None):
        import types
        calls = []

        def fake_run(*command, expect_failure=False):
            calls.append(command)
            if len(calls) <= failures:
                return types.SimpleNamespace(returncode=254, stdout="", stderr=failure or DataApiStarting.STARTING)
            return types.SimpleNamespace(returncode=0, stdout='{"formattedRecords": "[{\\"id\\": 1}]"}', stderr="")

        def no_probe(_cluster_id):
            raise AssertionError("./lab check must not probe the Data API")
        saved = (lab.describe_cluster, lab.describe_secret, lab.query_readiness, lab.run, lab.time.sleep, lab.say,
                 lab._secret_arn, lab.REGION, lab.SCHEMA_FILE, lab.read_events)
        lab.describe_cluster, lab.describe_secret, lab.query_readiness = (lambda _c: cluster), (lambda: "arn:secret"), no_probe
        lab.read_events = lambda: []  # not this computer's real evidence log
        lab.run, lab.time.sleep, lab.say = fake_run, (lambda _s: None), (lambda _m: None)
        lab._secret_arn, lab.REGION, lab.SCHEMA_FILE = "arn:secret", "ap-southeast-2", "/nonexistent/schema.json"
        findings = {}
        try:
            with contextlib.redirect_stderr(io.StringIO()):
                return lab.read_database(findings), findings
        finally:
            (lab.describe_cluster, lab.describe_secret, lab.query_readiness, lab.run, lab.time.sleep, lab.say,
             lab._secret_arn, lab.REGION, lab.SCHEMA_FILE, lab.read_events) = saved

    def test_no_instance_or_data_api_off_means_prepare(self):
        for cluster in (dict(self.READY, DBClusterMembers=[]), dict(self.READY, HttpEndpointEnabled=False)):
            with self.subTest(cluster=cluster):
                rows, findings = self.read(cluster)
                self.assertIsNone(rows)
                self.assertEqual(findings["database"], "not queryable: run ./lab prepare orders-db")

    def test_a_starting_answer_is_waited_through_and_the_rows_come_back(self):
        rows, findings = self.read(self.READY, failures=1)
        self.assertEqual(list(rows), [1])
        self.assertNotIn("database", findings)

    def test_the_check_compares_the_databases_deployment_with_the_log(self):
        import types
        seeded = [{"at": "2026-10-25T10:00:00+00:00", "event": "seed", "deployment": "aaaa1111"}]
        for in_database, expected in (("aaaa1111", None), ("bbbb2222", "from another deployment (bbbb2222). Restore a copy of deployment aaaa1111")):
            def fake_run(*command, expect_failure=False):
                statement = command[command.index("--sql") + 1]
                record = {"id": in_database} if "FROM deployment" in statement else {"id": 1}
                return types.SimpleNamespace(returncode=0, stdout=json.dumps({"formattedRecords": json.dumps([record])}), stderr="")
            saved = (lab.describe_cluster, lab.describe_secret, lab.run, lab.read_events, lab._secret_arn, lab.REGION, lab.SCHEMA_FILE)
            lab.describe_cluster, lab.describe_secret, lab.run = (lambda _c: self.READY), (lambda: "arn:secret"), fake_run
            lab.read_events, lab._secret_arn, lab.REGION, lab.SCHEMA_FILE = (lambda: seeded), "arn:secret", "ap-southeast-2", "/nonexistent"
            findings = {}
            try:
                with contextlib.redirect_stderr(io.StringIO()):
                    lab.read_database(findings)
            finally:
                (lab.describe_cluster, lab.describe_secret, lab.run, lab.read_events, lab._secret_arn, lab.REGION,
                 lab.SCHEMA_FILE) = saved
            with self.subTest(in_database=in_database):
                self.assertEqual(findings.get("deployment"), expected)

    def test_another_not_queryable_answer_is_a_finding_not_a_crash(self):
        bad = "aws: [ERROR]: An error occurred (InvalidResourceStateException) when calling the ExecuteStatement operation: the instance is being deleted"
        rows, findings = self.read(self.READY, failures=1, failure=bad)
        self.assertIsNone(rows)
        self.assertTrue(findings["database"].startswith("not queryable: "), findings)
        self.assertIn("InvalidResourceStateException", findings["database"])


class ProtectionOwner(unittest.TestCase):
    """Clumio applies the first matching rule, so an older, wider rule can claim orders-db (seen live in
    a shared tenant, 2026-10-24). The workshop's evidence must come from its own policy, so the
    readiness gate names who protects the database, and what to do."""

    OURS = "policy-ours"

    def owner(self, protection_info):
        return lab.protection_owner({"name": "orders-db", "protection_info": protection_info}, self.OURS)

    def test_our_policy(self):
        self.assertEqual(self.owner({"policy_id": self.OURS, "rule_id": "rule-ours"}), ("ours", None))
        self.assertIsNone(lab.protection_reason(("ours", None)))

    def test_no_policy_yet(self):
        self.assertEqual(self.owner(None), ("none", None))
        self.assertEqual(lab.protection_reason(("none", None)),
                         "Clumio hasn't applied a policy to orders-db yet: wait, then run ./lab status again")

    def test_another_policy_names_the_rule_and_the_fix(self):
        owner = self.owner({"policy_id": "policy-someone-else", "rule_id": "03427765-b500-4b3d-a189-0da8f278d261"})
        self.assertEqual(owner, ("another", "03427765-b500-4b3d-a189-0da8f278d261"))
        reason = lab.protection_reason(owner)
        self.assertIn("another Clumio policy", reason)
        self.assertIn('rds_rule_before_id = "03427765-b500-4b3d-a189-0da8f278d261"', reason)
        self.assertIn("terraform apply", reason)


class ConfirmAccount(unittest.TestCase):
    """A deletion nobody can undo needs the account ID: typed by a person, or passed by an agent with
    --confirm-account. Either way it must match terraform.tfvars."""

    def confirm(self, given, typed=None):
        import builtins
        saved = (lab.ACCOUNT, builtins.input)
        lab.ACCOUNT = "123456789012"
        prompted = []

        def fake_input(prompt):
            prompted.append(prompt)
            return typed or ""
        builtins.input = fake_input
        error = io.StringIO()
        try:
            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(error):
                lab.confirm_by_account_id(["database orders-db"], confirmed=given)
            outcome = "go"
        except SystemExit:
            outcome = "STOP"
        finally:
            lab.ACCOUNT, builtins.input = saved
        return outcome, len(prompted), error.getvalue()

    def test_a_matching_flag_needs_no_typing(self):
        self.assertEqual(self.confirm("123456789012")[:2], ("go", 0))

    def test_a_wrong_flag_stops_before_anything(self):
        outcome, prompts, error = self.confirm("111122223333")
        self.assertEqual((outcome, prompts), ("STOP", 0))
        self.assertIn("Nothing was deleted", error)

    def test_with_no_one_to_type_it_says_to_pass_the_flag(self):
        # An agent's shell has no terminal: input() ends at once. "Didn't match" would read like a typo.
        import builtins
        saved = (lab.ACCOUNT, builtins.input)
        lab.ACCOUNT = "123456789012"

        def no_terminal(_prompt):
            raise EOFError
        builtins.input = no_terminal
        error = io.StringIO()
        try:
            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(error), \
                    self.assertRaises(SystemExit):
                lab.confirm_by_account_id(["database orders-db"])
        finally:
            lab.ACCOUNT, builtins.input = saved
        self.assertIn("no one typed the account ID", error.getvalue())
        self.assertIn("--confirm-account", error.getvalue())
        self.assertIn("Nothing was deleted", error.getvalue())

    def test_without_the_flag_a_person_types_it(self):
        self.assertEqual(self.confirm(None, typed="123456789012")[:2], ("go", 1))
        self.assertEqual(self.confirm(None, typed="nope")[:2], ("STOP", 1))


class OneTableDefinition(unittest.TestCase):
    """The orders table is written out in a few places, on purpose: plain SQL reads best. This test
    makes them agree, so a missed edit fails here, never at a restore."""

    def test_the_table_the_inserts_and_the_column_list_name_the_same_columns(self):
        import re
        body = lab.ORDERS_TABLE_SQL.split("(", 1)[1].rsplit(")", 1)[0]
        created = [part.split()[0] for part in re.split(r",\s*(?![^()]*\))", body) if not part.strip().startswith("INDEX")]
        inserted = re.search(r"INTO orders \(([^)]*)\)", lab.INSERT_ORDER_SQL).group(1).split(", ")
        placeholders = re.search(r"VALUES \(([^)]*)\)", lab.INSERT_ORDER_SQL).group(1).split(", ")
        parameters = [p["name"] for p in lab.insert_parameters(lab.order_for(1))]
        self.assertEqual(created, list(lab.ORDER_COLUMNS))
        self.assertEqual(inserted, list(lab.ORDER_COLUMNS))
        self.assertEqual(placeholders, [":" + c for c in lab.ORDER_COLUMNS])
        self.assertEqual(parameters, list(lab.ORDER_COLUMNS))
        self.assertEqual(sorted(lab.order_for(1)), sorted(lab.ORDER_COLUMNS))


class Names(unittest.TestCase):
    """Every name lives in names.json. A name seen beyond one account and Region, an S3 bucket
    (global) or a Clumio policy (the whole tenant), carries both, so two workshops never collide."""

    def test_names_with_a_wider_scope_carry_the_account_and_region(self):
        with open(os.path.join(HERE, "..", "names.json")) as file:
            names = json.load(file)
        for key in ("bucket", "clumio_rds_policy", "clumio_s3_policy"):
            with self.subTest(key=key):
                self.assertIn("{account}", names[key])
                self.assertIn("{region}", names[key])

    def test_filling_in_the_account_and_region(self):
        raw = {"bucket": "orders-documents-{account}-{region}", "cluster": "orders-db",
               "protection_tag": {"key": "clumio-protection", "value": "orders"}}
        self.assertEqual(lab.fill_names(raw, "123456789012", "ap-southeast-2"),
                         {"bucket": "orders-documents-123456789012-ap-southeast-2", "cluster": "orders-db",
                          "protection_tag": {"key": "clumio-protection", "value": "orders"}})

    def test_the_bucket_name_fits_s3s_limit(self):
        with open(os.path.join(HERE, "..", "names.json")) as file:
            names = lab.fill_names(json.load(file), "123456789012", "ap-southeast-2")
        self.assertLessEqual(len(names["bucket"]), 63)


class OnlyWhatTheWorkshopMade(unittest.TestCase):
    """lab deletes a cluster or the bucket only when it carries the workshop's tag. A name proves
    nothing: an account can already hold an orders-db, or an orders-db-prod, that isn't ours."""

    OURS = [{"Key": "Workshop", "Value": "orders-recovery"}, {"Key": "clumio-protection", "Value": "orders"}]

    def stubbed(self, stubs, call):
        saved = {name: getattr(lab, name) for name in stubs}
        for name, stub in stubs.items():
            setattr(lab, name, stub)
        error = io.StringIO()
        try:
            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(error):
                return call(), error.getvalue()
        except SystemExit:
            return "STOP", error.getvalue()
        finally:
            for name, original in saved.items():
                setattr(lab, name, original)

    def test_names_json_names_the_workshop_tag(self):
        with open(os.path.join(HERE, "..", "names.json")) as file:
            self.assertEqual(json.load(file)["workshop_tag"], {"key": "Workshop", "value": "orders-recovery"})

    def test_a_restore_is_a_tagged_cluster_other_than_the_live_one(self):
        clusters = {"DBClusters": [
            {"DBClusterIdentifier": "orders-db", "DBSubnetGroup": "orders-db", "TagList": self.OURS},
            {"DBClusterIdentifier": "orders-db-restore", "DBSubnetGroup": "orders-db", "TagList": self.OURS},
            {"DBClusterIdentifier": "restored-orders-db-1792831984188", "DBSubnetGroup": "orders-db", "TagList": self.OURS},
            {"DBClusterIdentifier": "orders-db-prod", "DBSubnetGroup": "orders-db", "TagList": []}]}
        found, _ = self.stubbed({"aws": lambda *_a, **_k: clusters}, lab.restored_clusters)
        self.assertEqual(found, ["orders-db-restore", "restored-orders-db-1792831984188"])

    def test_an_untagged_cluster_is_never_deleted(self):
        calls = []
        cluster = {"DBClusterIdentifier": "orders-db", "Status": "available", "TagList": [],
                   "DBClusterMembers": [{"DBInstanceIdentifier": "orders-db-1"}]}
        outcome, error = self.stubbed({"describe_cluster": lambda _c: cluster, "aws": lambda *a, **_k: calls.append(a),
                                       "run": lambda *a, **_k: calls.append(a), "WAIT_ROUNDS": 1,
                                       "instance_status": lambda _i: "available"}, lambda: lab.delete_cluster("orders-db"))
        self.assertEqual((outcome, calls), ("STOP", []))
        self.assertIn("isn't tagged Workshop = orders-recovery", error)
        self.assertIn("Nothing was deleted", error)

    def test_an_untagged_bucket_is_never_emptied(self):
        calls = []

        def fake_aws(*args, **_kwargs):
            calls.append(args[1])
            return {"TagSet": [{"Key": "Team", "Value": "payments"}]} if args[1] == "get-bucket-tagging" else {}
        outcome, error = self.stubbed({"bucket_exists": lambda: True, "aws": fake_aws}, lab.empty_and_delete_bucket)
        self.assertEqual((outcome, calls), ("STOP", ["get-bucket-tagging"]))
        self.assertIn("Nothing was deleted", error)

    def test_preflight_refuses_an_existing_orders_db(self):
        import types
        stubs = {"shutil": types.SimpleNamespace(which=lambda _t: "/usr/bin/x"),
                 "run": lambda *a, **_k: types.SimpleNamespace(stdout="aws-cli/2.30.0" if "--version" in a else ""),
                 "aws": lambda *_a, **_k: {"DBEngineVersions": [{"EngineVersion": "8.0.mysql_aurora.3.10.3"}]},
                 "get_clumio": lambda _p: (200, {}), "clumio_items": lambda _p: [{"id": "ap-southeast-2"}],
                 "is_clumio_connected": lambda: False, "bucket_exists": lambda: False,
                 "describe_cluster": lambda _c: {"DBClusterIdentifier": "orders-db", "TagList": []}}
        saved_region = lab.REGION
        lab.REGION = "ap-southeast-2"
        try:
            outcome, error = self.stubbed(stubs, lambda: lab.cmd_preflight(None))
        finally:
            lab.REGION = saved_region
        self.assertEqual(outcome, "STOP")
        self.assertIn("orders-db already exists", error)


class DownWaitsForDeletesToShow(unittest.TestCase):
    """AWS shows a delete with a delay: seen live (2026-10-25), S3 still reported the bucket seconds
    after terraform destroy removed it. ./lab down re-checks for a bounded time before it stops."""

    def wait(self, answers):
        calls, slept = [], []

        def left_behind():
            calls.append(1)
            return answers[min(len(calls), len(answers)) - 1]
        saved = (lab.left_behind, lab.time.sleep)
        lab.left_behind, lab.time.sleep = left_behind, slept.append
        error = io.StringIO()
        try:
            with contextlib.redirect_stderr(error):
                lab.wait_until_gone()
            outcome = "gone"
        except SystemExit:
            outcome = "STOP"
        finally:
            lab.left_behind, lab.time.sleep = saved
        return outcome, len(calls), error.getvalue()

    def test_a_delete_that_shows_late_is_waited_for(self):
        self.assertEqual(self.wait([["bucket orders-documents"], []])[:2], ("gone", 2))

    def test_what_stays_is_named_after_a_bounded_wait(self):
        outcome, calls, error = self.wait([["bucket orders-documents"]])
        self.assertEqual((outcome, calls), ("STOP", lab.GONE_ROUNDS))
        self.assertIn("still there: bucket orders-documents", error)


class DownWaitsForClumio(unittest.TestCase):
    """./lab down deletes Clumio's connection. Mid-backup, that strands the backup and its temporary
    snapshots in the account (seen live, 2026-10-25), so down refuses until Clumio is done."""

    def stubbed(self, stubs, call):
        saved = {name: getattr(lab, name) for name in stubs}
        for name, stub in stubs.items():
            setattr(lab, name, stub)
        error = io.StringIO()
        try:
            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(error):
                return call(), error.getvalue()
        except SystemExit:
            return "STOP", error.getvalue()
        finally:
            for name, original in saved.items():
                setattr(lab, name, original)

    def test_down_refuses_before_deleting_while_a_backup_runs(self):
        calls = []
        outcome, error = self.stubbed({
            "restored_clusters": lambda: [], "describe_cluster": lambda _c: None,
            "backups_running": lambda: ["4042118284"],
            "confirm_by_account_id": lambda *_a, **_k: calls.append("confirm"),
            "delete_cluster": lambda *_a, **_k: calls.append("delete")},
            lambda: lab.cmd_down(argparse.Namespace(confirm_account="123456789012")))
        self.assertEqual((outcome, calls), ("STOP", []))
        self.assertIn("4042118284", error)
        self.assertIn("Nothing was deleted", error)

    def test_running_means_queued_or_in_progress_for_this_database(self):
        paths = []

        def tasks(path):
            paths.append(path)
            return [{"id": "1", "status": "in_progress"}, {"id": "2", "status": "queued"},
                    {"id": "3", "status": "completed"}, {"id": "4", "status": "failed"}]
        found, _ = self.stubbed({"database_in_clumio": lambda: {"id": "db-1"}, "clumio_items": tasks}, lab.backups_running)
        self.assertEqual(found, ["1", "2"])
        self.assertIn("primary_entity.id", paths[0])
        self.assertNotIn("status", paths[0])  # Clumio answers 504 when status is in the filter (seen live)

    def test_nothing_runs_when_clumio_has_no_database(self):
        found, _ = self.stubbed({"database_in_clumio": lambda: None}, lab.backups_running)
        self.assertEqual(found, [])

    def test_clumios_temporary_snapshots_of_our_database_are_named(self):
        snapshots = {"DBClusterSnapshots": [
            {"DBClusterSnapshotIdentifier": "clumio-airgap-encrypted-t1-org2", "DBClusterIdentifier": "orders-db"},
            {"DBClusterSnapshotIdentifier": "clumio-airgap-encrypted-t9-org2", "DBClusterIdentifier": "payments-db"},
            {"DBClusterSnapshotIdentifier": "nightly", "DBClusterIdentifier": "orders-db"}]}
        left, _ = self.stubbed({
            "restored_clusters": lambda: [], "describe_cluster": lambda _c: None, "bucket_exists": lambda: False,
            "describe_secret": lambda: None, "is_clumio_connected": lambda: False, "clumio_items": lambda _p: [],
            "aws": lambda *_a, **_k: snapshots}, lab.left_behind)
        self.assertEqual(left, ["Clumio's temporary snapshot clumio-airgap-encrypted-t1-org2 (delete it in the Amazon RDS console)"])


class Deployment(unittest.TestCase):
    """Clumio keeps old entries with the same name, and every run loads the same sample data. So a
    restore of another deployment's copy would look HEALTHY. The deployment ID tells them apart."""

    def at(self, minute, event, **details):
        return {"at": f"2026-10-25T10:{minute:02d}:00+00:00", "event": event, **details}

    def test_this_deployment_is_the_last_seed_since_the_last_down(self):
        events = [self.at(0, "seed", deployment="aaaa1111"), self.at(5, "down"),
                  self.at(9, "seed", deployment="bbbb2222"), self.at(12, "check", state="HEALTHY")]
        self.assertEqual(lab.this_deployment(events), "bbbb2222")
        self.assertIsNone(lab.this_deployment(events[:2]))
        self.assertIsNone(lab.this_deployment([]))

    def test_each_state_of_the_copy_has_its_own_finding(self):
        self.assertIsNone(lab.deployment_finding("bbbb2222", ["bbbb2222"]))
        self.assertEqual(lab.deployment_finding("bbbb2222", ["aaaa1111"]),
                         "from another deployment (aaaa1111). Restore a copy of deployment bbbb2222")
        self.assertEqual(lab.deployment_finding("bbbb2222", []), "missing: this copy has no deployment record")
        self.assertEqual(lab.deployment_finding(None, ["bbbb2222"]),
                         "can't tell: this computer has no record of ./lab seed. If it didn't finish, run it again")

    def test_a_wrong_deployment_is_never_fine(self):
        findings = {"deployment": lab.deployment_finding("bbbb2222", ["aaaa1111"])}
        self.assertFalse(lab.is_fine("deployment", findings["deployment"]))

    def test_seed_keeps_the_deployment_id_it_already_wrote(self):
        statements = []

        def fake_sql(_arn, statement, parameters=()):
            statements.append(statement)
            return [{"id": "aaaa1111"}] if statement.startswith("SELECT") else []
        saved = lab.sql
        lab.sql = fake_sql
        try:
            self.assertEqual(lab.ensure_deployment("arn:cluster"), "aaaa1111")
        finally:
            lab.sql = saved
        self.assertFalse(any(s.startswith("INSERT") for s in statements))

    def test_a_first_seed_writes_a_new_deployment_id(self):
        inserted = []

        def fake_sql(_arn, statement, parameters=()):
            if statement.startswith("INSERT"):
                inserted.append(parameters)
            return []
        saved = lab.sql
        lab.sql = fake_sql
        try:
            new_id = lab.ensure_deployment("arn:cluster")
        finally:
            lab.sql = saved
        self.assertRegex(new_id, r"^[0-9a-f]{8}$")
        self.assertEqual(len(inserted), 1)


class MissingSecret(unittest.TestCase):
    def test_it_names_the_command_that_creates_it(self):
        saved = (lab.describe_secret, lab._secret_arn)
        lab.describe_secret, lab._secret_arn = (lambda: None), None
        error = io.StringIO()
        try:
            with contextlib.redirect_stderr(error), self.assertRaises(SystemExit):
                lab.secret_arn()
        finally:
            lab.describe_secret, lab._secret_arn = saved
        self.assertIn("terraform apply creates it", error.getvalue())


class ConfirmAccountWiring(unittest.TestCase):
    """An agent's --confirm-account must reach the confirmation: if the wiring broke, the run would
    fall back to a prompt no agent can answer."""

    def stubbed(self, stubs, command, args):
        saved = {name: getattr(lab, name) for name in stubs}
        for name, stub in stubs.items():
            setattr(lab, name, stub)
        try:
            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                command(args)
        except SystemExit:
            pass
        finally:
            for name, original in saved.items():
                setattr(lab, name, original)

    def test_break_everything_receives_the_flag(self):
        received = []
        self.stubbed({"break_everything": received.append}, lab.cmd_break,
                     argparse.Namespace(incident="everything", confirm_account="123456789012"))
        self.assertEqual(received, ["123456789012"])

    def test_down_confirms_with_the_flag_before_it_deletes_anything(self):
        calls = []

        def refuse(_what, confirmed=None):  # as a mismatched account ID does
            calls.append(f"confirm {confirmed}")
            raise SystemExit(1)
        self.stubbed({"restored_clusters": lambda: ["orders-db-restore"], "describe_cluster": lambda _c: None,
                      "backups_running": lambda: [], "confirm_by_account_id": refuse, "delete_cluster": lambda *_a, **_k: calls.append("delete")},
                     lab.cmd_down, argparse.Namespace(confirm_account="111122223333"))
        self.assertEqual(calls, ["confirm 111122223333"])


class ReportPage(unittest.TestCase):
    """The report is shared with teams and auditors: it shows only the account's last four digits, and
    times people can read."""

    def test_the_account_is_masked_and_times_are_readable(self):
        events = [{"at": "2026-10-24T08:48:31+00:00", "event": "break deploy"},
                  {"at": "2026-10-24T09:10:06+00:00", "event": "check", "state": "HEALTHY", "findings": {}}]
        page = lab.report_html(events, "111122223333", "ap-southeast-2")
        self.assertNotIn("111122223333", page)
        self.assertIn("ending 3333", page)
        self.assertIn("<td>2026-10-24 08:48</td>", page)  # the column header says UTC, once
        self.assertNotIn("+00:00", page)

    def test_values_from_the_log_are_masked_and_escaped(self):
        # AWS's own error text names the cluster ARN, with the full account ID (seen live, 2026-10-24).
        aws_answer = ("not queryable: HttpEndpoint is being enabled for resource "
                      "arn:aws:rds:ap-southeast-2:111122223333:cluster:orders-db.")
        events = [{"at": "2026-10-24T12:31:41+00:00", "event": "check", "state": "BROKEN",
                   "findings": {"database": aws_answer}},
                  {"at": "2026-10-24T12:40:00+00:00", "event": "repair", "source": "<script>x</script>.csv", "copied": 1}]
        page = lab.report_html(events, "111122223333", "ap-southeast-2")
        self.assertNotIn("111122223333", page)
        self.assertIn("arn:aws:rds:ap-southeast-2:XXXXXXXX3333:cluster:orders-db", page)
        self.assertNotIn("<script>", page)
        self.assertIn("&lt;script&gt;x&lt;/script&gt;.csv", page)


class PortalPageText(unittest.TestCase):
    """The portal is the workshop's live demo: what it shows must belong to the order just checked.
    Standard library only, so this reads the page's text rather than running its JavaScript."""

    def test_the_page_says_it_is_checking_and_wraps_long_values(self):
        self.assertIn("Checking", lab.PORTAL_PAGE)
        self.assertIn("pre-wrap", lab.PORTAL_PAGE)

    def test_every_button_waits_for_its_answer(self):
        self.assertIn('onclick="busy(check)"', lab.PORTAL_PAGE)
        self.assertIn('onclick="busy(openDocument)"', lab.PORTAL_PAGE)
        self.assertEqual(lab.PORTAL_PAGE.count("onclick="), 2)

    def test_the_last_answer_is_cleared_before_the_check_waits(self):
        check = lab.PORTAL_PAGE.split("async function check()")[1].split("async function")[0]
        self.assertLess(check.index('getElementById("detail").textContent = ""'), check.index("await"))


class SettingsRegion(unittest.TestCase):
    def test_govcloud_regions_are_refused(self):
        import tempfile as tf
        saved = (lab.HERE, lab.ACCOUNT, lab.REGION)
        error = io.StringIO()
        with tf.TemporaryDirectory() as folder:
            with open(os.path.join(folder, "terraform.tfvars"), "w") as file:
                file.write('account_id = "123456789012"\nregion = "us-gov-west-1"\n')
            lab.HERE = folder
            try:
                with contextlib.redirect_stderr(error), self.assertRaises(SystemExit):
                    lab.load_settings()
            finally:
                lab.HERE, lab.ACCOUNT, lab.REGION = saved
        self.assertIn("set region in terraform.tfvars", error.getvalue())


if __name__ == "__main__":
    unittest.main()
