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

TARGET_VERSION = "2.1"

SUBTITLE = "Key Organizer & Tracker"
KEYWORDS = "key,keyring,organizer,identifier,tracker,spare,lost,inventory,holder,manager,household,locksmith"
PROMOTIONAL_TEXT = (
    "New in 2.1: loan reminders that actually notify you when a key is due back, "
    "plus everything from 2.0 -- location confirmation, duplicate detection, and Siri Shortcuts."
)
WHATS_NEW = """Keyring 2.1:
- Loan reminders -- set a return date when you loan a key and get notified the day it's due
- Small fixes and polish

Thanks for using Keyring -- keep the feedback coming."""

DESCRIPTION = """Stop wondering what that mystery key opens. Keyring lets you photograph and label every key so you always know which is which -- then tap the ring to fan them out for quick browsing.

NEW IN 2.1
- Loan reminders -- get notified the day a loaned key is due back, not just a note that it's overdue

ALSO INCLUDED
- Loan tracking -- know exactly who has your spare key and when it's due back
- Location confirmation -- log where you last saw a key, with a map
- Duplicate detection -- instantly spot near-identical keys by photo, entirely on-device
- Full activity history for every key
- Siri Shortcuts and Spotlight search

FREE
Photograph and organize up to 5 keys on one keyring, completely free -- no account needed, everything stays on your device.

KEYRING PRO -- $2.99/month, cancel anytime (a one-time unlock option is also available)
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

    # altool uploads land in /builds but are never auto-selected onto a
    # version. Always check for the highest build NUMBER across the app,
    # not just "is something already attached" -- a growing history of
    # already-VALID older builds means a naive first-attach-wins check
    # never notices a newer upload once anything is attached at all (bit
    # us: a 2.0-era build stayed attached to the 2.1 version because it
    # was "already attached", even after a genuinely newer build existed).
    status, builds_body = req("GET", f"/builds?filter[app]={APP_ID}&sort=-uploadedDate&limit=10", token)
    all_builds = builds_body["data"]
    for b in all_builds:
        a = b["attributes"]
        print(f"build {b['id']}: version={a.get('version')} processingState={a.get('processingState')} uploadedDate={a.get('uploadedDate')}")

    if not all_builds:
        print("No builds found for this app yet.")
    else:
        latest = max(all_builds, key=lambda b: int(b["attributes"].get("version") or 0))
        if latest["id"] == attached_build_id:
            print(f"Already attached to the latest build (version {latest['attributes'].get('version')}).")
        elif latest["attributes"].get("processingState") == "VALID":
            status, body = req(
                "PATCH",
                f"/appStoreVersions/{version_id}",
                token,
                {
                    "data": {
                        "type": "appStoreVersions",
                        "id": version_id,
                        "relationships": {"build": {"data": {"type": "builds", "id": latest["id"]}}},
                    }
                },
            )
            print(f"Attached build {latest['id']} (version {latest['attributes'].get('version')}) to appStoreVersion: {status}")
        else:
            print(f"Latest build (version {latest['attributes'].get('version')}) is still processingState={latest['attributes'].get('processingState')} -- not attaching yet. Re-run in a few minutes.")

    if version["attributes"]["versionString"] != TARGET_VERSION:
        status, body = req(
            "PATCH",
            f"/appStoreVersions/{version_id}",
            token,
            {"data": {"type": "appStoreVersions", "id": version_id, "attributes": {"versionString": TARGET_VERSION}}},
        )
        print(f"versionString corrected to {TARGET_VERSION}: {status}")

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
                    "whatsNew": WHATS_NEW,
                },
            }
        },
    )
    print(f"Description/keywords/promo text updated: {status}")


if __name__ == "__main__":
    main()
