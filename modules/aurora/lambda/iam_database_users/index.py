"""Creates, converts and removes the engine users behind iam_database_users.

Invoked by aws_lambda_invocation with lifecycle_scope = "CRUD". The event is
the resource's input plus a "tf" key that Terraform adds:

    {
      "cluster_arn": "arn:aws:rds:...:cluster:orders",
      "secret_arn":  "arn:aws:secretsmanager:...",     # credentials of a user that may CREATE ROLE
      "engine":      "postgres" | "mysql",
      "database":    "orders",                          # PostgreSQL: the database to connect to
      "users":       {"orders_rw": {"on_remove": "revoke"}},
      "tf":          {"action": "create" | "update" | "delete", "prev_input": {...} | null}
    }

Every statement goes through the RDS Data API, so the function needs no VPC
and never sees a password: Data API reads the secret itself. The SQL is the
same the module prints in output.iam_database_auth.users[*].engine_sql, made
idempotent, so a re-invocation changes nothing that is already right.

What happens to a user that leaves the map, or on destroy, is that user's
on_remove, read from the input it was last applied with:

    revoke   PostgreSQL: REVOKE rds_iam (password login works again, if any).
             MySQL: ACCOUNT LOCK. The user and what it owns stay.
    drop     DROP ROLE / DROP USER. Refused by PostgreSQL while the role owns
             objects; the error says what to do.
    keep     Nothing. The user keeps its token login.

Returns {"action": ..., "users": {name: status}}, which Terraform keeps as the
invocation's result. Only the AWS SDK and the standard library are used.
"""

import json
import re
import time

# boto3 is imported where it is used, so the tests run the handler with a fake
# client on a machine without the SDK. The Lambda runtime always has it.

# What the module's validation allows; checked again here because this code
# interpolates the name into identifiers.
USER_NAME = re.compile(r"^[A-Za-z_][A-Za-z0-9_-]{0,62}$")
ON_REMOVE = ("revoke", "drop", "keep")

# Data API errors that mean "not yet", not "no": a paused Serverless v2
# instance resuming, a writer mid-failover, an instance still being created.
RETRYABLE = {"DatabaseResumingException", "DatabaseUnavailableException", "DatabaseNotFoundException"}
RETRY_INTERVAL_SECONDS = 5


class Database:
    """One cluster, one secret, one database; executes statements with retries."""

    def __init__(self, client, cluster_arn, secret_arn, database, deadline):
        self.client = client
        self.cluster_arn = cluster_arn
        self.secret_arn = secret_arn
        self.database = database
        self.deadline = deadline

    def execute(self, sql, parameters=None, ddl=False):
        request = {"resourceArn": self.cluster_arn, "secretArn": self.secret_arn, "sql": sql}
        if self.database:
            request["database"] = self.database
        if parameters:
            request["parameters"] = parameters
        if ddl:
            # A DDL statement cut off by the call timeout can leave half a
            # change behind; AWS recommends letting it finish.
            request["continueAfterTimeout"] = True
        while True:
            try:
                return self.client.execute_statement(**request)
            except Exception as error:
                code = error_code(error)
                if code not in RETRYABLE or time.monotonic() + RETRY_INTERVAL_SECONDS > self.deadline:
                    raise
                log("retrying", error=code, statement=sql.split(" ")[0])
                time.sleep(RETRY_INTERVAL_SECONDS)

    def exists(self, sql, parameters):
        response = self.execute(sql, parameters)
        return len(response.get("records") or []) > 0


class Postgres:
    @staticmethod
    def identifier(name):
        return '"' + name.replace('"', '""') + '"'

    def present(self, db, name):
        return db.exists("SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = :name", _string("name", name))

    def has_rds_iam(self, db, name):
        return db.exists(
            "SELECT 1 FROM pg_catalog.pg_auth_members m"
            " JOIN pg_catalog.pg_roles granted ON granted.oid = m.roleid"
            " JOIN pg_catalog.pg_roles member ON member.oid = m.member"
            " WHERE granted.rolname = 'rds_iam' AND member.rolname = :name",
            _string("name", name),
        )

    def ensure(self, db, name):
        ident = self.identifier(name)
        if not self.present(db, name):
            db.execute(f"CREATE ROLE {ident} WITH LOGIN", ddl=True)
            db.execute(f"GRANT rds_iam TO {ident}", ddl=True)
            return "created"
        if not self.has_rds_iam(db, name):
            db.execute(f"GRANT rds_iam TO {ident}", ddl=True)
            return "granted"
        return "unchanged"

    def remove(self, db, name, on_remove):
        ident = self.identifier(name)
        if on_remove == "keep":
            return "kept"
        if not self.present(db, name):
            return "absent"
        if on_remove == "revoke":
            db.execute(f"REVOKE rds_iam FROM {ident}", ddl=True)
            return "revoked"
        try:
            db.execute(f"DROP ROLE {ident}", ddl=True)
        except Exception as error:
            message = error_message(error)
            if "depend" in message or "owner of" in message or "owned by" in message:
                raise RuntimeError(
                    f"{name} owns objects or has privileges, so PostgreSQL refuses DROP ROLE: {message}. "
                    f"Run REASSIGN OWNED BY {ident} TO <owner>; DROP OWNED BY {ident}; first, "
                    f"or set on_remove = \"revoke\" for this user."
                ) from error
            raise
        return "dropped"


class MySQL:
    @staticmethod
    def literal(name):
        return "'" + name.replace("\\", "\\\\").replace("'", "''") + "'"

    def plugin(self, db, name):
        response = db.execute("SELECT plugin FROM mysql.user WHERE user = :name AND host = '%'", _string("name", name))
        records = response.get("records") or []
        if not records:
            return None
        return (records[0][0] or {}).get("stringValue", "")

    def ensure(self, db, name):
        account = f"{self.literal(name)}@'%'"
        plugin = self.plugin(db, name)
        if plugin is None:
            db.execute(f"CREATE USER IF NOT EXISTS {account} IDENTIFIED WITH AWSAuthenticationPlugin AS 'RDS'", ddl=True)
            db.execute(f"ALTER USER {account} REQUIRE SSL", ddl=True)
            return "created"
        if plugin != "AWSAuthenticationPlugin":
            db.execute(f"ALTER USER {account} IDENTIFIED WITH AWSAuthenticationPlugin AS 'RDS'", ddl=True)
            db.execute(f"ALTER USER {account} REQUIRE SSL", ddl=True)
            return "converted"
        db.execute(f"ALTER USER {account} REQUIRE SSL ACCOUNT UNLOCK", ddl=True)
        return "unchanged"

    def remove(self, db, name, on_remove):
        account = f"{self.literal(name)}@'%'"
        if on_remove == "keep":
            return "kept"
        if self.plugin(db, name) is None:
            return "absent"
        if on_remove == "revoke":
            # MySQL has no rds_iam to revoke; a locked account cannot log in
            # by any method, and ACCOUNT UNLOCK on the next ensure reverses it.
            db.execute(f"ALTER USER {account} ACCOUNT LOCK", ddl=True)
            return "locked"
        db.execute(f"DROP USER IF EXISTS {account}", ddl=True)
        return "dropped"


ENGINES = {"postgres": Postgres, "mysql": MySQL}


def _string(name, value):
    return [{"name": name, "value": {"stringValue": value}}]


def error_code(error):
    """The service error code of a botocore ClientError, "" for anything else."""
    return (getattr(error, "response", None) or {}).get("Error", {}).get("Code", "")


def error_message(error):
    return (getattr(error, "response", None) or {}).get("Error", {}).get("Message", "") or str(error)


def log(message, **fields):
    print(json.dumps({"message": message, **fields}, sort_keys=True))


def check_users(users):
    for name, spec in users.items():
        if not USER_NAME.match(name):
            raise ValueError(f"user name {name!r} is not a database user name the module accepts")
        on_remove = (spec or {}).get("on_remove", "revoke")
        if on_remove not in ON_REMOVE:
            raise ValueError(f"user {name}: on_remove must be one of {', '.join(ON_REMOVE)}, not {on_remove!r}")


def handler(event, context, client=None):
    tf = event.get("tf") or {}
    action = tf.get("action") or "create"
    previous = tf.get("prev_input") or {}

    engine_name = event.get("engine", "")
    if engine_name not in ENGINES:
        raise ValueError(f"engine must be postgres or mysql, not {engine_name!r}")
    engine = ENGINES[engine_name]()

    wanted = {} if action == "delete" else dict(event.get("users") or {})
    # On update, users that were in the last applied input and are not in this
    # one leave. On delete, everything in this input leaves.
    leaving = dict(previous.get("users") or {}) if action == "update" else dict(event.get("users") or {}) if action == "delete" else {}
    check_users(wanted)
    check_users(leaving)

    remaining_ms = context.get_remaining_time_in_millis() if context is not None else 300_000
    deadline = time.monotonic() + max(remaining_ms / 1000 - 15, 5)
    if client is None:
        import boto3

        client = boto3.client("rds-data")
    db = Database(
        client,
        event["cluster_arn"],
        event["secret_arn"],
        event.get("database") or None,
        deadline,
    )

    result = {}
    for name in sorted(wanted):
        result[name] = engine.ensure(db, name)
        log("ensured", user=name, status=result[name])
    for name in sorted(leaving):
        if name in wanted:
            continue
        on_remove = (leaving[name] or {}).get("on_remove", "revoke")
        result[name] = engine.remove(db, name, on_remove)
        log("removed", user=name, on_remove=on_remove, status=result[name])

    return {"action": action, "engine": engine_name, "users": result}
