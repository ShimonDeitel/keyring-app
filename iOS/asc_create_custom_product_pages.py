#!/usr/bin/env python3
"""Create App Store custom product pages (Phase 6 ASO) via the App Store
Connect API. Each targets a different search intent with its own
promotional text, reusing the main listing's screenshots since they
already show the relevant features honestly.

Flow per page (all confirmed against Apple's published OpenAPI spec):
  POST /v1/appCustomProductPages                 (name, app relationship)
  POST /v1/appCustomProductPageVersions           (appCustomProductPage relationship)
  POST /v1/appCustomProductPageLocalizations      (locale, promotionalText, version relationship)
  POST /v1/appScreenshotSets                      (screenshotDisplayType, localization relationship)
  POST /v1/appScreenshots (+upload) for each image
  PATCH /v1/appCustomProductPages/{id}            (visible: true)

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

# Each targets real, already-shipped functionality -- no Family Sharing page
# since CloudKit sharing isn't live yet (see Phase 2 blocker notes).
PAGES = [
    {
        "name": "Key Organizer",
        "promotionalText": "Organize every key you own on a real keyring you can fan out and browse -- free to start, no account needed.",
    },
    {
        "name": "Key Identifier",
        "promotionalText": "Stop wondering what that mystery key opens. Photograph and label every key so you always know which is which.",
    },
    {
        "name": "Spare Keys",
        "promotionalText": "Track spare and loaned keys -- know exactly who has your spare and when it's due back.",
    },
]


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


def upload_screenshots(token, set_id, files):
    for path in files:
        data = path.read_bytes()
        checksum = hashlib.md5(data).hexdigest()
        status, body = req(
            "POST", "/appScreenshots", token,
            {"data": {"type": "appScreenshots", "attributes": {"fileName": path.name, "fileSize": len(data)},
                      "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}}}},
        )
        shot_id = body["data"]["id"]
        for op in body["data"]["attributes"]["uploadOperations"]:
            chunk = data[op["offset"]:op["offset"] + op["length"]]
            put_bytes(op["url"], op["requestHeaders"], chunk)
        req("PATCH", f"/appScreenshots/{shot_id}", token,
            {"data": {"type": "appScreenshots", "id": shot_id, "attributes": {"sourceFileChecksum": checksum, "uploaded": True}}})
        print(f"    uploaded {path.name}")


def create_page(token, page):
    print(f"Creating custom product page: {page['name']}")

    # The live API rejects a bare page POST with 409 ENTITY_ERROR.RELATIONSHIP.REQUIRED --
    # it needs the version and localization created in the SAME request as a JSON:API
    # compound document (an "included" array with temporary reference ids), not as
    # separate follow-up POSTs. Confirmed against the real API, not just the spec example.
    version_lid = "tmp-version"
    loc_lid = "tmp-localization"
    _, body = req("POST", "/appCustomProductPages", token, {
        "data": {
            "type": "appCustomProductPages",
            "attributes": {"name": page["name"]},
            "relationships": {
                "app": {"data": {"type": "apps", "id": APP_ID}},
                "appCustomProductPageVersions": {"data": [{"type": "appCustomProductPageVersions", "id": version_lid}]},
            },
        },
        "included": [
            {
                "type": "appCustomProductPageVersions",
                "id": version_lid,
                "relationships": {
                    "appCustomProductPageLocalizations": {"data": [{"type": "appCustomProductPageLocalizations", "id": loc_lid}]}
                },
            },
            {
                "type": "appCustomProductPageLocalizations",
                "id": loc_lid,
                "attributes": {"locale": "en-US", "promotionalText": page["promotionalText"]},
            },
        ],
    })
    page_id = body["data"]["id"]
    print(f"  page: {page_id}")

    _, vbody = req("GET", f"/appCustomProductPages/{page_id}/appCustomProductPageVersions", token)
    version_id = vbody["data"][0]["id"]
    print(f"  version: {version_id}")

    _, lbody = req("GET", f"/appCustomProductPageVersions/{version_id}/appCustomProductPageLocalizations", token)
    loc_id = lbody["data"][0]["id"]
    print(f"  localization: {loc_id}")

    _, body = req("POST", "/appScreenshotSets", token, {
        "data": {"type": "appScreenshotSets", "attributes": {"screenshotDisplayType": DISPLAY_TYPE},
                 "relationships": {"appCustomProductPageLocalization": {"data": {"type": "appCustomProductPageLocalizations", "id": loc_id}}}}
    })
    set_id = body["data"]["id"]
    print(f"  screenshot set: {set_id}")

    files = sorted(SCREENSHOTS_DIR.glob("*.png"))
    upload_screenshots(token, set_id, files)

    status, _ = req("PATCH", f"/appCustomProductPages/{page_id}", token,
                     {"data": {"type": "appCustomProductPages", "id": page_id, "attributes": {"visible": True}}})
    print(f"  set visible: {status}")
    return page_id


def main():
    token = make_jwt()

    _, body = req("GET", f"/apps/{APP_ID}/appCustomProductPages", token)
    existing_names = {p["attributes"]["name"] for p in body["data"]}
    print(f"Existing custom product pages: {existing_names or 'none'}")

    for page in PAGES:
        if page["name"] in existing_names:
            print(f"Skipping {page['name']} (already exists)")
            continue
        try:
            create_page(token, page)
        except Exception as e:
            print(f"FAILED to create {page['name']}: {e}", file=sys.stderr)


if __name__ == "__main__":
    main()
