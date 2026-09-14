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
    version_id = None
    if pending:
        version_id = pending[0]["id"]
        print(f"Target version: {version_id} ({pending[0]['attributes']['versionString']})")

        # Apple rejects the submission until the attached build declares its
        # export-compliance status. Info.plist now sets this at build time
        # (ITSAppUsesNonExemptEncryption), so only PATCH builds where it's
        # still unset -- Apple 409s ENTITY_ERROR.ATTRIBUTE.INVALID if you
        # try to "update" a value that's already set, even to the same value.
        _, build_body = req("GET", f"/appStoreVersions/{version_id}/build", token)
        if build_body.get("data"):
            build_id = build_body["data"]["id"]
            _, full_build = req("GET", f"/builds/{build_id}", token)
            if full_build["data"]["attributes"].get("usesNonExemptEncryption") is None:
                req("PATCH", f"/builds/{build_id}", token, {
                    "data": {"type": "builds", "id": build_id, "attributes": {"usesNonExemptEncryption": False}}
                })
                print(f"Set usesNonExemptEncryption=false on build {build_id}")
            else:
                print(f"Build {build_id} already declares usesNonExemptEncryption={full_build['data']['attributes']['usesNonExemptEncryption']}")
    else:
        print("No appStoreVersion in PREPARE_FOR_SUBMISSION (already submitted, or none pending) -- "
              "still checking whether the subscription needs attaching to the open submission.")

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

    has_version_item = version_id is not None and any(
        i.get("relationships", {}).get("appStoreVersion", {}).get("data", {}).get("id") == version_id
        for i in existing_items
    )
    if not version_id:
        print("No pending appStoreVersion to attach (already attached earlier, or none pending).")
    elif has_version_item:
        print("appStoreVersion already attached.")
    else:
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

    # Ride the new Keyring Pro Monthly subscription along with this version
    # submission -- Apple requires a subscription group's first subscription
    # to go out with an app version, it can't go live on its own.
    subscription_version_id = os.environ.get("SUBSCRIPTION_VERSION_ID")
    sub_attach_failed = False
    if subscription_version_id:
        has_sub_item = any(
            i.get("relationships", {}).get("subscriptionVersion", {}).get("data", {}).get("id") == subscription_version_id
            for i in existing_items
        )
        if has_sub_item:
            print("subscriptionVersion already attached.")
        else:
            try:
                _, body = req("POST", "/reviewSubmissionItems", token, {
                    "data": {
                        "type": "reviewSubmissionItems",
                        "relationships": {
                            "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": submission_id}},
                            "subscriptionVersion": {"data": {"type": "subscriptionVersions", "id": subscription_version_id}},
                        },
                    }
                })
                print(f"Attached subscriptionVersion to submission item: {body['data']['id']}")
            except urllib.error.HTTPError as e:
                sub_attach_failed = True
                print(f"subscriptionVersion attach failed ({e.code}) on the current submission (state={open_submission['attributes']['state'] if open_submission else 'new'}).", file=sys.stderr)

    # A submission already WAITING_FOR_REVIEW/IN_REVIEW is locked against new
    # items -- that's exactly the case here (2.1 was submitted before this
    # script knew about the subscription). Cancel it and resubmit fresh with
    # both items together rather than leaving the subscription stranded.
    if sub_attach_failed and open_submission and open_submission["attributes"]["state"] != "READY_FOR_REVIEW":
        print(f"Canceling locked submission {submission_id} to resubmit with the subscription included.")
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

        # Canceling the old submission likely reverted the app version back
        # to PREPARE_FOR_SUBMISSION -- re-fetch rather than trust the
        # possibly-stale version_id captured before the cancel.
        _, versions = req("GET", f"/apps/{APP_ID}/appStoreVersions?limit=10", token)
        pending = [v for v in versions["data"] if v["attributes"]["appStoreState"] == "PREPARE_FOR_SUBMISSION"]
        version_id = pending[0]["id"] if pending else version_id
        print(f"Version to re-attach after cancel: {version_id}")

        if version_id:
            _, body = req("POST", "/reviewSubmissionItems", token, {
                "data": {
                    "type": "reviewSubmissionItems",
                    "relationships": {
                        "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": submission_id}},
                        "appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}},
                    },
                }
            })
            print(f"Re-attached appStoreVersion: {body['data']['id']}")

        _, body = req("POST", "/reviewSubmissionItems", token, {
            "data": {
                "type": "reviewSubmissionItems",
                "relationships": {
                    "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": submission_id}},
                    "subscriptionVersion": {"data": {"type": "subscriptionVersions", "id": subscription_version_id}},
                },
            }
        })
        print(f"Attached subscriptionVersion: {body['data']['id']}")

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
