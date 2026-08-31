#!/usr/bin/env python3
"""Submit the pending PREPARE_FOR_SUBMISSION app store version for Apple
review, using the current reviewSubmissions flow (appStoreVersionSubmissions
was retired). Schema confirmed against Apple's real OpenAPI-generated Swift
SDK types (AvdLee/appstoreconnect-swift-sdk), not just the spec mirror used
elsewhere in this repo, since the mirror lacks this resource entirely.

Flow:
  GET  /v1/apps/{id}/reviewSubmissions          -- reuse an open one if present
  POST /v1/reviewSubmissions                    -- platform + app relationship
  POST /v1/reviewSubmissionItems                -- attach the appStoreVersion
  PATCH /v1/reviewSubmissions/{id}               -- attributes.submitted = true

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

    _, versions = req("GET", f"/apps/{APP_ID}/appStoreVersions?limit=10", token)
    pending = [v for v in versions["data"] if v["attributes"]["appStoreState"] == "PREPARE_FOR_SUBMISSION"]
    if not pending:
        print("No appStoreVersion in PREPARE_FOR_SUBMISSION -- nothing to submit.")
        return
    version_id = pending[0]["id"]
    print(f"Target version: {version_id} ({pending[0]['attributes']['versionString']})")

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

        _, body = req("POST", "/reviewSubmissionItems", token, {
            "data": {
                "type": "reviewSubmissionItems",
                "relationships": {
                    "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": submission_id}},
                    "appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}},
                },
            }
        })
        print(f"Attached version to submission item: {body['data']['id']}")

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
