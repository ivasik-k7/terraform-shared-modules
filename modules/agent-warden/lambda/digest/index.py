"""Daily activity digest for the AI agent role.

Runs on a schedule, summarises the role's last 24h of CloudTrail activity by
human (sourceIdentity) and action, and publishes it to SNS.

Two data paths:
- CloudTrail Lake (EVENT_DATA_STORE_ARN set): server-side SQL, scales to busy
  shared accounts.
- LookupEvents fallback: throttled at ~2 req/s with no server-side role filter;
  on very busy accounts the scan may not finish inside the timeout, in which
  case the digest says so rather than pretending the count is complete.
"""
import collections
import datetime
import json
import os
import time

import boto3

cloudtrail = boto3.client("cloudtrail")
sns = boto3.client("sns")

ROLE_NAME = os.environ["ROLE_NAME"]
TOPIC_ARN = os.environ["TOPIC_ARN"]
EDS_ARN = os.environ.get("EVENT_DATA_STORE_ARN", "")

LOOKUP_DEADLINE_SECONDS = 90


def _lake_counts(start, end):
    eds_id = EDS_ARN.split("/")[-1]
    sql = (
        "SELECT eventName, COALESCE(userIdentity.sessionContext.sourceIdentity, "
        "userIdentity.principalId) AS actor "
        f"FROM {eds_id} "
        f"WHERE eventTime > timestamp '{start:%Y-%m-%d %H:%M:%S}' "
        f"AND eventTime <= timestamp '{end:%Y-%m-%d %H:%M:%S}' "
        f"AND userIdentity.sessionContext.sessionIssuer.userName = '{ROLE_NAME}'"
    )
    query_id = cloudtrail.start_query(QueryStatement=sql)["QueryId"]
    while True:
        status = cloudtrail.describe_query(QueryId=query_id)["QueryStatus"]
        if status in ("FINISHED", "FAILED", "CANCELLED", "TIMED_OUT"):
            break
        time.sleep(2)
    if status != "FINISHED":
        raise RuntimeError(f"Lake query {query_id} ended as {status}")

    by_actor, by_event = collections.Counter(), collections.Counter()
    token = None
    while True:
        kwargs = {"QueryId": query_id}
        if token:
            kwargs["NextToken"] = token
        page = cloudtrail.get_query_results(**kwargs)
        for row in page.get("QueryResultRows", []):
            fields = {k: v for cell in row for k, v in cell.items()}
            by_event[fields.get("eventName", "?")] += 1
            by_actor[fields.get("actor") or "?"] += 1
        token = page.get("NextToken")
        if not token:
            break
    return by_actor, by_event, False


def _lookup_counts(start, end):
    by_actor, by_event = collections.Counter(), collections.Counter()
    truncated = False
    deadline = time.monotonic() + LOOKUP_DEADLINE_SECONDS

    paginator = cloudtrail.get_paginator("lookup_events")
    for page in paginator.paginate(StartTime=start, EndTime=end):
        if time.monotonic() > deadline:
            truncated = True
            break
        for ev in page.get("Events", []):
            # precise match: the session must have been ISSUED by our role.
            try:
                detail = json.loads(ev["CloudTrailEvent"])
                issuer = detail["userIdentity"]["sessionContext"]["sessionIssuer"]
            except (KeyError, ValueError, TypeError):
                continue
            if issuer.get("type") != "Role" or issuer.get("userName") != ROLE_NAME:
                continue
            by_event[ev.get("EventName", "?")] += 1
            actor = detail["userIdentity"].get("sessionContext", {}).get("sourceIdentity") or ev.get("Username", "?")
            by_actor[actor] += 1
    return by_actor, by_event, truncated


def handler(event, _context):
    end = datetime.datetime.now(datetime.timezone.utc)
    start = end - datetime.timedelta(hours=24)

    if EDS_ARN:
        by_actor, by_event, truncated = _lake_counts(start, end)
    else:
        by_actor, by_event, truncated = _lookup_counts(start, end)

    total = sum(by_event.values())
    if total == 0:
        body = f"AI role {ROLE_NAME}: no activity in the last 24h."
    else:
        top_actions = "\n".join(f"  {n:>4}  {name}" for name, n in by_event.most_common(10))
        top_actors = "\n".join(f"  {n:>4}  {who}" for who, n in by_actor.most_common(10))
        body = (
            f"AI role {ROLE_NAME} - {total} API calls in the last 24h\n\n"
            f"Top actions:\n{top_actions}\n\nBy actor:\n{top_actors}"
        )
    if truncated:
        body += (
            "\n\nWARNING: scan hit the LookupEvents time budget - counts are a lower "
            "bound. Provide digest_event_data_store_arn (CloudTrail Lake) for complete digests."
        )

    sns.publish(TopicArn=TOPIC_ARN, Subject=f"[AI DIGEST] {ROLE_NAME}", Message=body)
    return {"events": total, "truncated": truncated}
