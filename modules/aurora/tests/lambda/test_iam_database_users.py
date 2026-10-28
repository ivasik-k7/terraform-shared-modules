#!/usr/bin/env python3
"""Runs the user-creating Lambda (lambda/iam_database_users/index.py) against a
fake RDS Data API client that records every statement and answers the lookups
from a scripted catalogue. Proves what the function sends for each engine and
lifecycle action, what it refuses, and that it waits out a resuming cluster.

    python3 tests/lambda/test_iam_database_users.py

No AWS calls, no network, no SDK: every test passes a fake client in, and
the errors it raises carry the same .response shape as botocore's ClientError.
"""

import pathlib
import sys
import time
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2] / "lambda" / "iam_database_users"))

import index  # noqa: E402


class ClientError(Exception):
    """The shape of botocore.exceptions.ClientError, without botocore."""

    def __init__(self, code, message=""):
        super().__init__(f"An error occurred ({code}) when calling ExecuteStatement: {message}")
        self.response = {"Error": {"Code": code, "Message": message}}


def client_error(code, message=""):
    return ClientError(code, message)


class FakeDataApi:
    """Records execute_statement calls. Lookups are answered from `present`
    (PostgreSQL role names, and whether they hold rds_iam) or `plugins`
    (MySQL user -> plugin). `failures` is a queue of exceptions raised before
    the next call succeeds."""

    def __init__(self, present=None, plugins=None, failures=None):
        self.present = dict(present or {})
        self.plugins = dict(plugins or {})
        self.failures = list(failures or [])
        self.calls = []

    def execute_statement(self, **request):
        self.calls.append(request)
        if self.failures:
            raise self.failures.pop(0)
        sql = request["sql"]
        name = (request.get("parameters") or [{}])[0].get("value", {}).get("stringValue")
        if sql.startswith("SELECT 1 FROM pg_catalog.pg_roles"):
            return {"records": [[{"longValue": 1}]] if name in self.present else []}
        if sql.startswith("SELECT 1 FROM pg_catalog.pg_auth_members"):
            return {"records": [[{"longValue": 1}]] if self.present.get(name) else []}
        if sql.startswith("SELECT plugin FROM mysql.user"):
            return {"records": [[{"stringValue": self.plugins[name]}]] if name in self.plugins else []}
        return {"numberOfRecordsUpdated": 0}

    @property
    def statements(self):
        return [c["sql"] for c in self.calls if not c["sql"].startswith("SELECT")]


class Context:
    def __init__(self, remaining_ms=300_000):
        self.remaining_ms = remaining_ms

    def get_remaining_time_in_millis(self):
        return self.remaining_ms


def event(action="create", users=None, prev_users=None, engine="postgres", database="orders"):
    return {
        "cluster_arn": "arn:aws:rds:eu-west-2:111122223333:cluster:orders",
        "secret_arn": "arn:aws:secretsmanager:eu-west-2:111122223333:secret:rds!cluster-abc",
        "engine": engine,
        "database": database,
        "users": users if users is not None else {"orders_rw": {"on_remove": "revoke"}},
        "tf": {"action": action, "prev_input": None if prev_users is None else {"users": prev_users}},
    }


class PostgresCreate(unittest.TestCase):
    def test_a_missing_role_is_created_with_login_and_granted_rds_iam(self):
        api = FakeDataApi()
        result = index.handler(event(), Context(), client=api)
        self.assertEqual(result["users"], {"orders_rw": "created"})
        self.assertEqual(api.statements, ['CREATE ROLE "orders_rw" WITH LOGIN', 'GRANT rds_iam TO "orders_rw"'])

    def test_every_call_names_the_cluster_the_secret_and_the_database(self):
        api = FakeDataApi()
        index.handler(event(), Context(), client=api)
        for call in api.calls:
            self.assertEqual(call["resourceArn"], "arn:aws:rds:eu-west-2:111122223333:cluster:orders")
            self.assertEqual(call["secretArn"], "arn:aws:secretsmanager:eu-west-2:111122223333:secret:rds!cluster-abc")
            self.assertEqual(call["database"], "orders")

    def test_ddl_continues_after_the_call_timeout_and_lookups_do_not(self):
        api = FakeDataApi()
        index.handler(event(), Context(), client=api)
        for call in api.calls:
            self.assertEqual(call.get("continueAfterTimeout", False), not call["sql"].startswith("SELECT"), call["sql"])

    def test_an_existing_role_without_the_grant_is_only_granted(self):
        api = FakeDataApi(present={"orders_rw": False})
        result = index.handler(event(), Context(), client=api)
        self.assertEqual(result["users"], {"orders_rw": "granted"})
        self.assertEqual(api.statements, ['GRANT rds_iam TO "orders_rw"'])

    def test_a_role_that_is_already_right_is_left_alone(self):
        api = FakeDataApi(present={"orders_rw": True})
        result = index.handler(event(), Context(), client=api)
        self.assertEqual(result["users"], {"orders_rw": "unchanged"})
        self.assertEqual(api.statements, [])

    def test_lookups_pass_the_name_as_a_parameter_not_in_the_sql(self):
        api = FakeDataApi()
        index.handler(event(), Context(), client=api)
        lookups = [c for c in api.calls if c["sql"].startswith("SELECT")]
        self.assertTrue(lookups)
        for call in lookups:
            self.assertNotIn("orders_rw", call["sql"])
            self.assertEqual(call["parameters"], [{"name": "name", "value": {"stringValue": "orders_rw"}}])

    def test_users_are_handled_in_name_order(self):
        api = FakeDataApi()
        result = index.handler(event(users={"zeta": {}, "alpha": {}}), Context(), client=api)
        self.assertEqual(list(result["users"]), ["alpha", "zeta"])


class PostgresUpdateAndDelete(unittest.TestCase):
    def test_a_user_that_left_the_map_is_revoked_by_default(self):
        api = FakeDataApi(present={"orders_rw": True, "old_etl": True})
        result = index.handler(
            event("update", users={"orders_rw": {"on_remove": "revoke"}}, prev_users={"orders_rw": {"on_remove": "revoke"}, "old_etl": {}}),
            Context(), client=api,
        )
        self.assertEqual(result["users"], {"orders_rw": "unchanged", "old_etl": "revoked"})
        self.assertEqual(api.statements, ['REVOKE rds_iam FROM "old_etl"'])

    def test_on_remove_is_read_from_the_input_the_user_was_applied_with(self):
        # The current input no longer has the user, so only prev_input can say.
        api = FakeDataApi(present={"old_etl": True})
        result = index.handler(event("update", users={}, prev_users={"old_etl": {"on_remove": "drop"}}), Context(), client=api)
        self.assertEqual(result["users"], {"old_etl": "dropped"})
        self.assertEqual(api.statements, ['DROP ROLE "old_etl"'])

    def test_keep_touches_nothing(self):
        api = FakeDataApi(present={"old_etl": True})
        result = index.handler(event("update", users={}, prev_users={"old_etl": {"on_remove": "keep"}}), Context(), client=api)
        self.assertEqual(result["users"], {"old_etl": "kept"})
        self.assertEqual(api.calls, [])

    def test_a_departed_user_that_no_longer_exists_is_reported_absent(self):
        api = FakeDataApi()
        result = index.handler(event("update", users={}, prev_users={"old_etl": {"on_remove": "drop"}}), Context(), client=api)
        self.assertEqual(result["users"], {"old_etl": "absent"})
        self.assertEqual(api.statements, [])

    def test_delete_removes_every_user_of_the_current_input_by_its_own_setting(self):
        api = FakeDataApi(present={"a": True, "b": True, "c": True})
        result = index.handler(
            event("delete", users={"a": {"on_remove": "revoke"}, "b": {"on_remove": "drop"}, "c": {"on_remove": "keep"}}),
            Context(), client=api,
        )
        self.assertEqual(result["users"], {"a": "revoked", "b": "dropped", "c": "kept"})
        self.assertEqual(api.statements, ['REVOKE rds_iam FROM "a"', 'DROP ROLE "b"'])

    def test_a_drop_refused_for_owned_objects_says_what_to_do(self):
        api = FakeDataApi(present={"old_etl": True}, failures=[])
        api.failures = []
        original = api.execute_statement

        def refuse_drop(**request):
            if request["sql"].startswith("DROP ROLE"):
                api.calls.append(request)
                raise client_error("DatabaseErrorException", 'role "old_etl" cannot be dropped because some objects depend on it')
            return original(**request)

        api.execute_statement = refuse_drop
        with self.assertRaises(RuntimeError) as raised:
            index.handler(event("delete", users={"old_etl": {"on_remove": "drop"}}), Context(), client=api)
        self.assertIn("REASSIGN OWNED BY", str(raised.exception))
        self.assertIn('on_remove = "revoke"', str(raised.exception))


class MySQL(unittest.TestCase):
    def test_a_missing_user_is_created_with_the_plugin_and_tls(self):
        api = FakeDataApi()
        result = index.handler(event(engine="mysql", database=""), Context(), client=api)
        self.assertEqual(result["users"], {"orders_rw": "created"})
        self.assertEqual(api.statements, [
            "CREATE USER IF NOT EXISTS 'orders_rw'@'%' IDENTIFIED WITH AWSAuthenticationPlugin AS 'RDS'",
            "ALTER USER 'orders_rw'@'%' REQUIRE SSL",
        ])
        self.assertTrue(all("database" not in c for c in api.calls), "MySQL needs no database for user management")

    def test_a_password_user_is_converted_to_the_plugin(self):
        api = FakeDataApi(plugins={"orders_rw": "mysql_native_password"})
        result = index.handler(event(engine="mysql"), Context(), client=api)
        self.assertEqual(result["users"], {"orders_rw": "converted"})
        self.assertEqual(api.statements[0], "ALTER USER 'orders_rw'@'%' IDENTIFIED WITH AWSAuthenticationPlugin AS 'RDS'")

    def test_an_iam_user_is_unlocked_and_kept(self):
        api = FakeDataApi(plugins={"orders_rw": "AWSAuthenticationPlugin"})
        result = index.handler(event(engine="mysql"), Context(), client=api)
        self.assertEqual(result["users"], {"orders_rw": "unchanged"})
        self.assertEqual(api.statements, ["ALTER USER 'orders_rw'@'%' REQUIRE SSL ACCOUNT UNLOCK"])

    def test_revoke_locks_the_account_and_drop_drops_it(self):
        api = FakeDataApi(plugins={"a": "AWSAuthenticationPlugin", "b": "AWSAuthenticationPlugin"})
        result = index.handler(event("delete", engine="mysql", users={"a": {"on_remove": "revoke"}, "b": {"on_remove": "drop"}}), Context(), client=api)
        self.assertEqual(result["users"], {"a": "locked", "b": "dropped"})
        self.assertEqual(api.statements, ["ALTER USER 'a'@'%' ACCOUNT LOCK", "DROP USER IF EXISTS 'b'@'%'"])


class Refusals(unittest.TestCase):
    def test_a_name_the_module_would_not_accept_runs_no_sql(self):
        api = FakeDataApi()
        with self.assertRaises(ValueError):
            index.handler(event(users={'x"; DROP ROLE postgres; --': {}}), Context(), client=api)
        self.assertEqual(api.calls, [])

    def test_an_unknown_on_remove_runs_no_sql(self):
        api = FakeDataApi()
        with self.assertRaises(ValueError):
            index.handler(event("delete", users={"orders_rw": {"on_remove": "nuke"}}), Context(), client=api)
        self.assertEqual(api.calls, [])

    def test_an_unknown_engine_is_refused(self):
        with self.assertRaises(ValueError):
            index.handler(event(engine="oracle"), Context(), client=FakeDataApi())

    def test_identifiers_are_quoted_even_for_names_that_pass(self):
        # A hyphen is legal in the module's names and needs quoting in SQL.
        api = FakeDataApi()
        index.handler(event(users={"orders-rw": {}}), Context(), client=api)
        self.assertEqual(api.statements[0], 'CREATE ROLE "orders-rw" WITH LOGIN')


class Retries(unittest.TestCase):
    def setUp(self):
        self.sleeps = []
        self._sleep = index.time.sleep
        index.time.sleep = lambda s: self.sleeps.append(s)

    def tearDown(self):
        index.time.sleep = self._sleep

    def test_a_resuming_cluster_is_waited_for(self):
        api = FakeDataApi(failures=[client_error("DatabaseResumingException"), client_error("DatabaseUnavailableException")])
        result = index.handler(event(), Context(), client=api)
        self.assertEqual(result["users"], {"orders_rw": "created"})
        self.assertEqual(self.sleeps, [index.RETRY_INTERVAL_SECONDS] * 2)

    def test_a_real_error_is_not_retried(self):
        api = FakeDataApi(failures=[client_error("HttpEndpointNotEnabledException")])
        with self.assertRaises(ClientError):
            index.handler(event(), Context(), client=api)
        self.assertEqual(self.sleeps, [])

    def test_retrying_stops_before_the_function_times_out(self):
        api = FakeDataApi(failures=[client_error("DatabaseResumingException")] * 100)
        with self.assertRaises(ClientError):
            # 20 s left: one retry window at most, never a hundred.
            index.handler(event(), Context(remaining_ms=20_000), client=api)
        self.assertLessEqual(len(self.sleeps), 1)


class Output(unittest.TestCase):
    def test_the_result_names_the_action_the_engine_and_each_user(self):
        result = index.handler(event(), Context(), client=FakeDataApi())
        self.assertEqual(result, {"action": "create", "engine": "postgres", "users": {"orders_rw": "created"}})

    def test_the_secret_is_never_logged(self):
        import contextlib
        import io

        buffer = io.StringIO()
        with contextlib.redirect_stdout(buffer):
            index.handler(event(), Context(), client=FakeDataApi())
        self.assertNotIn("secretsmanager", buffer.getvalue())


if __name__ == "__main__":
    unittest.main(verbosity=1)
