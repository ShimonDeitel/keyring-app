#!/usr/bin/env python3
"""Upload App Store screenshots (iOS/screenshots/*.png, sorted by filename)
to the pending appStoreVersion's en-US localization, display type
APP_IPHONE_67 (6.7"/6.9" bucket).

Requires env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH, APP_ID
"""
import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

import jwt

ASC_KEY_ID = os.environ["ASC_KEY_ID"]
ASC_ISSUER_ID = os.environ["ASC_ISSUER_ID"]
ASC_KEY_PATH = os.environ["ASC_KEY_PATH"]
APP_ID = os.environ["APP_ID"]
DISPLAY_TYPE = os.environ.get("DISPLAY_TYPE", "APP_IPHONE_67")
SCREENSHOTS_DIR = Path(__file__).parent / "screenshots"

BASE = "https://api.appstoreconnect.apple.com/v1"
EDITABLE_STATES = {
    "PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "METADATA_REJECTED",
    "INVALID_BINARY", "REJECTED",
}


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


def put_bytes(url, headers, data):
    r = urllib.request.Request(url, data=data, method="PUT")
    for h in headers:
        r.add_header(h["name"], h["value"])
    with urllib.request.urlopen(r) as resp:
        return resp.status


def main():
    token = make_jwt()

    status, body = req("GET", f"/apps/{APP_ID}/appStoreVersions?limit=10", token)
    editable = [v for v in body["data"] if v["attributes"]["appStoreState"] in EDITABLE_STATES]
    if not editable:
        print("No editable appStoreVersion found; nothing to attach screenshots to.")
        return
    version_id = editable[0]["id"]
    print(f"Using editable version: {editable[0]['attributes']['versionString']} ({version_id})")

    status, body = req("GET", f"/appStoreVersions/{version_id}/appStoreVersionLocalizations", token)
    en_us = next(loc for loc in body["data"] if loc["attributes"]["locale"] == "en-US")
    loc_id = en_us["id"]

    # Find or create the screenshot set for this display type.
    status, body = req("GET", f"/appStoreVersionLocalizations/{loc_id}/appScreenshotSets", token)
    existing_set = next((s for s in body["data"] if s["attributes"]["screenshotDisplayType"] == DISPLAY_TYPE), None)
    if existing_set:
        set_id = existing_set["id"]
        print(f"Reusing existing screenshot set: {set_id}")
        # Clear old screenshots so re-runs don't pile up duplicates.
        status, shots_body = req("GET", f"/appScreenshotSets/{set_id}/appScreenshots", token)
        for shot in shots_body["data"]:
            req("DELETE", f"/appScreenshots/{shot['id']}", token)
            print(f"Deleted old screenshot {shot['id']}")
    else:
        status, body = req(
            "POST",
            "/appScreenshotSets",
            token,
            {
                "data": {
                    "type": "appScreenshotSets",
                    "attributes": {"screenshotDisplayType": DISPLAY_TYPE},
                    "relationships": {"appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": loc_id}}},
                }
            },
        )
        set_id = body["data"]["id"]
        print(f"Created screenshot set: {set_id}")

    files = sorted(SCREENSHOTS_DIR.glob("*.png"))
    if not files:
        print(f"No screenshots found in {SCREENSHOTS_DIR}")
        return

    for path in files:
        data = path.read_bytes()
        checksum = hashlib.md5(data).hexdigest()

        status, body = req(
            "POST",
            "/appScreenshots",
            token,
            {
                "data": {
                    "type": "appScreenshots",
                    "attributes": {"fileName": path.name, "fileSize": len(data)},
                    "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}},
                }
            },
        )
        shot_id = body["data"]["id"]
        upload_ops = body["data"]["attributes"]["uploadOperations"]

        for op in upload_ops:
            offset = op["offset"]
            length = op["length"]
            chunk = data[offset:offset + length]
            put_bytes(op["url"], op["requestHeaders"], chunk)

        status, body = req(
            "PATCH",
            f"/appScreenshots/{shot_id}",
            token,
            {"data": {"type": "appScreenshots", "id": shot_id, "attributes": {"sourceFileChecksum": checksum, "uploaded": True}}},
        )
        print(f"Uploaded {path.name}: {status}")


if __name__ == "__main__":
    main()
