#!/usr/bin/env python3
"""Cancel the current open review submission so the app version becomes
editable again (reverts to DEVELOPER_REJECTED) -- used when a newer build
needs to replace the one already submitted for review.

Requires env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH, APP_ID
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


def main():
    token = make_jwt()
    _, existing = req("GET", f"/apps/{APP_ID}/reviewSubmissions", token)
    open_submission = next((s for s in existing["data"] if s["attributes"].get("state") in OPEN_STATES), None)
    if not open_submission:
        print("No open review submission to cancel.")
        return
    submission_id = open_submission["id"]
    print(f"Canceling review submission {submission_id} (state={open_submission['attributes']['state']})")
    status, body = req("PATCH", f"/reviewSubmissions/{submission_id}", token, {
        "data": {"type": "reviewSubmissions", "id": submission_id, "attributes": {"canceled": True}}
    })
    print(f"Canceled: HTTP {status}, state={body['data']['attributes'].get('state')}")


if __name__ == "__main__":
    main()
