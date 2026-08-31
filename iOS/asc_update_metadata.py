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


EDITABLE_STATES = {
    "PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "METADATA_REJECTED",
    "INVALID_BINARY", "REJECTED",
}


def main():
    token = make_jwt()

    # --- Subtitle lives on appInfoLocalizations. An app can have TWO
    # appInfo objects at once (the live one + the one for the pending
    # version) -- must pick the editable one, not just data[0]. ---
    status, body = req("GET", f"/apps/{APP_ID}/appInfos", token)
    for info in body["data"]:
        print(f"appInfo {info['id']}: state={info['attributes'].get('appStoreState')}")
    editable_infos = [i for i in body["data"] if i["attributes"].get("appStoreState") in EDITABLE_STATES]
    if not editable_infos:
        print("No editable appInfo found; skipping subtitle update.")
        app_info_id = None
    else:
        app_info_id = editable_infos[0]["id"]
        print(f"Using editable appInfo: {app_info_id}")

    if app_info_id:
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

    editable = [v for v in versions if v["attributes"]["appStoreState"] in EDITABLE_STATES]
    if not editable:
        print("No editable appStoreVersion found; skipping description/keywords/promo text.")
        return
    version = editable[0]
    version_id = version["id"]
    print(f"Using editable version: {version['attributes']['versionString']} ({version_id})")

    # Check what build (if any) is actually attached -- the appStoreVersion's
    # own versionString doesn't auto-follow an uploaded build's
    # CFBundleShortVersionString, so it can lag behind what altool uploaded.
    attached_build_id = None
    try:
        status, build_body = req("GET", f"/appStoreVersions/{version_id}/build", token)
        build_data = build_body.get("data")
        if build_data:
            attached_build_id = build_data.get("id")
            print(f"Attached build: {attached_build_id}")
        else:
            print("No build attached to this appStoreVersion yet.")
    except Exception as e:
        print(f"Could not fetch attached build: {e}")

    if not attached_build_id:
        # altool uploads land in /builds but are never auto-selected onto a
        # version -- list every build for the app and, once one has finished
        # processing, attach the newest.
        status, builds_body = req("GET", f"/apps/{APP_ID}/builds?sort=-uploadedDate&limit=10", token)
        for b in builds_body["data"]:
            a = b["attributes"]
            print(f"build {b['id']}: version={a.get('version')} processingState={a.get('processingState')} uploadedDate={a.get('uploadedDate')}")
        ready = [b for b in builds_body["data"] if b["attributes"].get("processingState") == "VALID"]
        if ready:
            newest = ready[0]
            status, body = req(
                "PATCH",
                f"/appStoreVersions/{version_id}",
                token,
                {
                    "data": {
                        "type": "appStoreVersions",
                        "id": version_id,
                        "relationships": {"build": {"data": {"type": "builds", "id": newest["id"]}}},
                    }
                },
            )
            print(f"Attached build {newest['id']} (version {newest['attributes'].get('version')}) to appStoreVersion: {status}")
        else:
            print("No VALID (finished-processing) build available yet -- Apple is still processing the upload. Re-run this workflow in a few minutes.")

    if version["attributes"]["versionString"] != "2.0":
        status, body = req(
            "PATCH",
            f"/appStoreVersions/{version_id}",
            token,
            {"data": {"type": "appStoreVersions", "id": version_id, "attributes": {"versionString": "2.0"}}},
        )
        print(f"versionString corrected to 2.0: {status}")

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
