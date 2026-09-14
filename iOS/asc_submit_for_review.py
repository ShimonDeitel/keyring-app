#!/usr/bin/env python3
"""Submit the pending app version -- and, if ready, the new Keyring Pro
Monthly subscription -- for Apple review, using the current
reviewSubmissions flow (appStoreVersionSubmissions was retired). Schema
confirmed against Apple's real OpenAPI-generated Swift SDK types
(AvdLee/appstoreconnect-swift-sdk), not just the spec mirror used
elsewhere in this repo, since the mirror lacks this resource entirely.

A subscription group's FIRST subscription can't go live on its own --
Apple requires both the subscriptionVersion AND the subscriptionGroupVersion
to ride along with an app version submission
(STATE_ERROR.SUBSCRIPTION_SUBMISSION_REQUIRES_GROUP_VERSION). If the app
version was already submitted on its own before the subscription was
READY_TO_SUBMIT, the review submission is locked against new items --
cancel it (reverts the version to DEVELOPER_REJECTED, not
PREPARE_FOR_SUBMISSION) and resubmit fresh with everything together.

Requires env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH, APP_ID
Optional env: SUBSCRIPTION_VERSION_ID, SUBSCRIPTION_GROUP_VERSION_ID
"""
import json
import os
import sys
import time
import urllib.error
import urllib.request

import jwt

ASC_KEY_ID = os.environ["ASC_KEY_ID"]
ASC_ISSUER_ID = os.environ["ASC_ISSUER_ID"]
ASC_KEY_PATH = os.environ["ASC_KEY_PATH"]
APP_ID = os.environ["APP_ID"]

BASE = "https://api.appstoreconnect.apple.com/v1"
OPEN_STATES = {"READY_FOR_REVIEW", "WAITING_FOR_REVIEW", "IN_REVIEW", "UNRESOLVED_ISSUES"}
# DEVELOPER_REJECTED is the state a version lands in after *we* cancel a
# review submission -- it's editable-again, not "Apple rejected it".
PENDING_STATES = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "METADATA_REJECTED", "INVALID_BINARY", "REJECTED"}


def make_jwt():
    with open(ASC_KEY_PATH) as f:
        private_key = f.read()
    now = int(time.time())
    payload = {"iss": ASC_ISSUER_ID, "iat": now, "exp": now + 19 * 60, "aud": "appstoreconnect-v1"}
    headers = {"kid": ASC_KEY_ID, "typ": "JWT"}
    return jwt.encode(payload, private_key, algorithm="ES256", headers=headers)


def req(method, path, token, body=None):
    url = path if path.startswith("http") else BASE + path
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(url, data=data, method=method)
    r.add_header("Authorization", f"Bearer {token}")
    r.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(r) as resp:
            raw = resp.read()
            return resp.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as e:
        raw = e.read()
        print(f"HTTP {e.code} on {method} {url}: {raw.decode()[:2000]}", file=sys.stderr)
        raise


def find_pending_version(token):
    _, versions = req("GET", f"/apps/{APP_ID}/appStoreVersions?limit=10", token)
    pending = [v for v in versions["data"] if v["attributes"]["appStoreState"] in PENDING_STATES]
    return pending[0]["id"] if pending else None


def ensure_export_compliance(token, version_id):
    _, build_body = req("GET", f"/appStoreVersions/{version_id}/build", token)
    if not build_body.get("data"):
        return
    build_id = build_body["data"]["id"]
    _, full_build = req("GET", f"/builds/{build_id}", token)
    if full_build["data"]["attributes"].get("usesNonExemptEncryption") is None:
        req("PATCH", f"/builds/{build_id}", token, {
            "data": {"type": "builds", "id": build_id, "attributes": {"usesNonExemptEncryption": False}}
        })
        print(f"Set usesNonExemptEncryption=false on build {build_id}")
    else:
        print(f"Build {build_id} already declares usesNonExemptEncryption={full_build['data']['attributes']['usesNonExemptEncryption']}")


def desired_items(version_id, subscription_version_id, subscription_group_version_id):
    items = []
    if version_id:
        items.append(("appStoreVersion", "appStoreVersions", version_id))
    if subscription_version_id:
        items.append(("subscriptionVersion", "subscriptionVersions", subscription_version_id))
    if subscription_group_version_id:
        items.append(("subscriptionGroupVersion", "subscriptionGroupVersions", subscription_group_version_id))
    return items


def attach_items(token, submission_id, items, existing_items):
    """Attach each (relationship_name, type, id) not already present.
    Returns True if every item ended up attached (already-present or
    newly attached), False if any attach was rejected."""
    all_ok = True
    for rel_name, rel_type, rel_id in items:
        already = any(
            i.get("relationships", {}).get(rel_name, {}).get("data", {}).get("id") == rel_id
            for i in existing_items
        )
        if already:
            print(f"{rel_name} already attached.")
            continue
        try:
            _, body = req("POST", "/reviewSubmissionItems", token, {
                "data": {
                    "type": "reviewSubmissionItems",
                    "relationships": {
                        "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": submission_id}},
                        rel_name: {"data": {"type": rel_type, "id": rel_id}},
                    },
                }
            })
            print(f"Attached {rel_name}: {body['data']['id']}")
        except urllib.error.HTTPError as e:
            all_ok = False
            print(f"{rel_name} attach failed ({e.code}).", file=sys.stderr)
    return all_ok


def main():
    token = make_jwt()

    version_id = find_pending_version(token)
    if version_id:
        print(f"Pending app version: {version_id}")
        ensure_export_compliance(token, version_id)
    else:
        print("No pending app version (already submitted, or none pending).")

    subscription_version_id = os.environ.get("SUBSCRIPTION_VERSION_ID")
    subscription_group_version_id = os.environ.get("SUBSCRIPTION_GROUP_VERSION_ID")

    _, existing = req("GET", f"/apps/{APP_ID}/reviewSubmissions", token)
    open_submission = next((s for s in existing["data"] if s["attributes"].get("state") in OPEN_STATES), None)

    if open_submission:
        submission_id = open_submission["id"]
        print(f"Reusing existing open review submission: {submission_id} (state={open_submission['attributes']['state']})")
    else:
        _, body = req("POST", "/reviewSubmissions", token, {
            "data": {
                "type": "reviewSubmissions",
                "attributes": {"platform": "IOS"},
                "relationships": {"app": {"data": {"type": "apps", "id": APP_ID}}},
            }
        })
        submission_id = body["data"]["id"]
        print(f"Created review submission: {submission_id}")

    _, items_body = req("GET", f"/reviewSubmissions/{submission_id}/items", token)
    existing_items = items_body["data"]
    print(f"Submission has {len(existing_items)} item(s) already attached")

    items = desired_items(version_id, subscription_version_id, subscription_group_version_id)
    all_attached = attach_items(token, submission_id, items, existing_items)

    # A submission already WAITING_FOR_REVIEW/IN_REVIEW is locked against
    # new items -- cancel and resubmit fresh with everything together
    # rather than leaving anything stranded.
    if not all_attached and open_submission and open_submission["attributes"]["state"] != "READY_FOR_REVIEW":
        print(f"Canceling locked submission {submission_id} to resubmit with everything included.")
        req("PATCH", f"/reviewSubmissions/{submission_id}", token, {
            "data": {"type": "reviewSubmissions", "id": submission_id, "attributes": {"canceled": True}}
        })

        _, body = req("POST", "/reviewSubmissions", token, {
            "data": {
                "type": "reviewSubmissions",
                "attributes": {"platform": "IOS"},
                "relationships": {"app": {"data": {"type": "apps", "id": APP_ID}}},
            }
        })
        submission_id = body["data"]["id"]
        print(f"Created fresh review submission: {submission_id}")

        # Canceling reverts the app version to DEVELOPER_REJECTED (still a
        # PENDING_STATE) -- re-fetch rather than trust the possibly-stale
        # version_id captured before the cancel.
        version_id = find_pending_version(token) or version_id
        print(f"Version to re-attach after cancel: {version_id}")

        items = desired_items(version_id, subscription_version_id, subscription_group_version_id)
        all_attached = attach_items(token, submission_id, items, [])

    if not all_attached:
        print("Not everything attached even after retrying -- not submitting. Check the errors above.", file=sys.stderr)
        sys.exit(1)

    status, body = req("PATCH", f"/reviewSubmissions/{submission_id}", token, {
        "data": {
            "type": "reviewSubmissions",
            "id": submission_id,
            "attributes": {"submitted": True},
        }
    })
    print(f"Submit for review: HTTP {status}, state={body['data']['attributes'].get('state')}")


if __name__ == "__main__":
    main()
