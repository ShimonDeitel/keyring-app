#!/usr/bin/env python3
"""Read-only status probe: prints the current appStoreVersion state and
attached build so we know whether the 2.0 release still needs a manual
Submit for Review action, or is already in flight.

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


def make_jwt():
    with open(ASC_KEY_PATH) as f:
        private_key = f.read()
    now = int(time.time())
    payload = {"iss": ASC_ISSUER_ID, "iat": now, "exp": now + 19 * 60, "aud": "appstoreconnect-v1"}
    headers = {"kid": ASC_KEY_ID, "typ": "JWT"}
    return jwt.encode(payload, private_key, algorithm="ES256", headers=headers)


def req(method, path, token):
    url = path if path.startswith("http") else BASE + path
    r = urllib.request.Request(url, method=method)
    r.add_header("Authorization", f"Bearer {token}")
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
    for v in body["data"]:
        attrs = v["attributes"]
        print(f"version {v['id']}: versionString={attrs.get('versionString')} state={attrs.get('appStoreState')} released={attrs.get('releaseType')}")

    _, body = req("GET", f"/apps/{APP_ID}/appCustomProductPages", token)
    for p in body["data"]:
        print(f"custom product page: {p['attributes']['name']} visible={p['attributes'].get('visible')}")


if __name__ == "__main__":
    main()
