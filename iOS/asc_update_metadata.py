#!/usr/bin/env python3
"""Update App Store Connect listing metadata (subtitle, keywords,
description, promotional text) for Keyring 2.0.

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

SUBTITLE = "Key Organizer & Tracker"
KEYWORDS = "key,keyring,organizer,identifier,tracker,spare,lost,inventory,holder,manager,household,locksmith"
PROMOTIONAL_TEXT = (
    "New in 2.0: loan tracking, location confirmation with maps, on-device "
    "duplicate detection, full activity history, and Siri Shortcuts support."
)
DESCRIPTION = """Stop wondering what that mystery key opens. Keyring lets you photograph and label every key so you always know which is which -- then tap the ring to fan them out for quick browsing.

NEW IN 2.0
- Loan tracking -- know exactly who has your spare key and when it's due back
- Location confirmation -- log where you last saw a key, with a map
- Duplicate detection -- instantly spot near-identical keys by photo, entirely on-device
- Full activity history for every key
- Siri Shortcuts and Spotlight search

FREE
Photograph and organize up to 5 keys on one keyring, completely free -- no account needed, everything stays on your device.

KEYRING PRO -- one-time purchase, yours forever
- Unlimited keys and keyrings
- Loan, spare, and lost-key tracking
- Location history with maps
- Full activity log
- Visual duplicate detection
- Search across every keyring

Your keys, your data. Keyring works fully offline and never asks for an account."""


def make_jwt():
    with open(ASC_KEY_PATH) as f:
        private_key = f.read()
    now = int(time.time())
    payload = {
        "iss": ASC_ISSUER_ID,
        "iat": now,
        "exp": now + 19 * 60,
        "aud": "appstoreconnect-v1",
    }
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

    # --- Subtitle lives on appInfoLocalizations ---
    status, body = req("GET", f"/apps/{APP_ID}/appInfos", token)
    app_info_id = body["data"][0]["id"]
    print(f"appInfo: {app_info_id}")

    status, body = req("GET", f"/appInfos/{app_info_id}/appInfoLocalizations", token)
    en_us = next(loc for loc in body["data"] if loc["attributes"]["locale"] == "en-US")
    loc_id = en_us["id"]
    print(f"appInfoLocalization (en-US): {loc_id}, current subtitle={en_us['attributes'].get('subtitle')!r}")

    status, body = req(
        "PATCH",
        f"/appInfoLocalizations/{loc_id}",
        token,
        {"data": {"type": "appInfoLocalizations", "id": loc_id, "attributes": {"subtitle": SUBTITLE}}},
    )
    print(f"Subtitle updated: {status}")

    # --- Description/keywords/promotional text live on appStoreVersionLocalizations,
    # scoped to a specific (editable) appStoreVersion ---
    status, body = req("GET", f"/apps/{APP_ID}/appStoreVersions?limit=10", token)
    versions = body["data"]
    for v in versions:
        print(f"version {v['attributes']['versionString']}: state={v['attributes']['appStoreState']}")

    editable_states = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "METADATA_REJECTED", "INVALID_BINARY", "REJECTED"}
    editable = [v for v in versions if v["attributes"]["appStoreState"] in editable_states]
    if not editable:
        print("No editable appStoreVersion found; skipping description/keywords/promo text.")
        return
    version = editable[0]
    version_id = version["id"]
    print(f"Using editable version: {version['attributes']['versionString']} ({version_id})")

    status, body = req("GET", f"/appStoreVersions/{version_id}/appStoreVersionLocalizations", token)
    en_us_v = next(loc for loc in body["data"] if loc["attributes"]["locale"] == "en-US")
    v_loc_id = en_us_v["id"]

    status, body = req(
        "PATCH",
        f"/appStoreVersionLocalizations/{v_loc_id}",
        token,
        {
            "data": {
                "type": "appStoreVersionLocalizations",
                "id": v_loc_id,
                "attributes": {
                    "description": DESCRIPTION,
                    "keywords": KEYWORDS,
                    "promotionalText": PROMOTIONAL_TEXT,
                },
            }
        },
    )
    print(f"Description/keywords/promo text updated: {status}")


if __name__ == "__main__":
    main()
