#!/usr/bin/env python3
"""Update promotionalText on the LIVE (READY_FOR_SALE) appStoreVersion.
Unlike description/keywords/subtitle, promotionalText is editable on a
live version with no review required -- the one instant, zero-cost ASO
lever available while 2.1 is still in Apple's review queue.

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

PROMOTIONAL_TEXT = (
    "Stop guessing which key opens what. Photograph, label, and organize every "
    "key on a ring you can fan out at a glance -- free to start, on-device, no account."
)


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

    _, body = req("GET", f"/apps/{APP_ID}/appStoreVersions?limit=10", token)
    live = [v for v in body["data"] if v["attributes"]["appStoreState"] == "READY_FOR_SALE"]
    if not live:
        print("No READY_FOR_SALE version found.")
        return
    version = live[0]
    version_id = version["id"]
    print(f"Live version: {version['attributes']['versionString']} ({version_id})")

    _, body = req("GET", f"/appStoreVersions/{version_id}/appStoreVersionLocalizations", token)
    en_us = next(loc for loc in body["data"] if loc["attributes"]["locale"] == "en-US")
    loc_id = en_us["id"]
    print(f"Current promotionalText: {en_us['attributes'].get('promotionalText')!r}")

    status, body = req(
        "PATCH",
        f"/appStoreVersionLocalizations/{loc_id}",
        token,
        {"data": {"type": "appStoreVersionLocalizations", "id": loc_id, "attributes": {"promotionalText": PROMOTIONAL_TEXT}}},
    )
    print(f"promotionalText updated on LIVE listing (no review needed): {status}")


if __name__ == "__main__":
    main()
