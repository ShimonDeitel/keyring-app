#!/usr/bin/env python3
"""Create the Keyring Pro Monthly auto-renewable subscription in App Store
Connect (group -> localization -> subscription -> localization ->
availability -> price -> review screenshot), so the product referenced by
PurchaseManager.proMonthlyID actually exists and is purchasable.

The one-time keyring_pro_unlock IAP is untouched and stays forever for
existing purchasers -- this only adds the new subscription alongside it.

Schema verified against Apple's real OpenAPI-generated Swift SDK types
(AvdLee/appstoreconnect-swift-sdk), same source used for the custom-product-
pages and review-submission work earlier in this project. Price-setting
follows the previously-solved recipe: PATCH the subscription with a
compound `included` price, not POST /v1/subscriptionPrices directly (that
409s with a misleading error -- see project memory
asc-subscription-initial-price-patch).

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

BASE = "https://api.appstoreconnect.apple.com/v1"
SCREENSHOTS_DIR = Path(__file__).parent / "screenshots"

GROUP_REFERENCE_NAME = "Keyring Pro Group"
GROUP_LOCALIZED_NAME = "Keyring Pro"
PRODUCT_ID = "keyring_pro_monthly"
SUBSCRIPTION_NAME = "Keyring Pro Monthly"
SUBSCRIPTION_DESCRIPTION = "Unlimited keys, loan reminders, location, search."  # <=55 chars
TARGET_PRICE = "2.99"


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


def get_or_create_group(token):
    _, body = req("GET", f"/apps/{APP_ID}/subscriptionGroups", token)
    for g in body["data"]:
        if g["attributes"]["referenceName"] == GROUP_REFERENCE_NAME:
            print(f"Reusing existing subscription group: {g['id']}")
            return g["id"], False
    _, body = req("POST", "/subscriptionGroups", token, {
        "data": {
            "type": "subscriptionGroups",
            "attributes": {"referenceName": GROUP_REFERENCE_NAME},
            "relationships": {"app": {"data": {"type": "apps", "id": APP_ID}}},
        }
    })
    group_id = body["data"]["id"]
    print(f"Created subscription group: {group_id}")
    return group_id, True


def ensure_group_localization(token, group_id):
    _, body = req("GET", f"/subscriptionGroups/{group_id}/subscriptionGroupLocalizations", token)
    if any(loc["attributes"]["locale"] == "en-US" for loc in body["data"]):
        print("Group localization (en-US) already exists.")
        return
    req("POST", "/subscriptionGroupLocalizations", token, {
        "data": {
            "type": "subscriptionGroupLocalizations",
            "attributes": {"name": GROUP_LOCALIZED_NAME, "locale": "en-US"},
            "relationships": {"subscriptionGroup": {"data": {"type": "subscriptionGroups", "id": group_id}}},
        }
    })
    print("Created group localization (en-US).")


def get_or_create_subscription(token, group_id):
    _, body = req("GET", f"/subscriptionGroups/{group_id}/subscriptions", token)
    for s in body["data"]:
        if s["attributes"]["productId"] == PRODUCT_ID:
            print(f"Reusing existing subscription: {s['id']}")
            return s["id"], False
    _, body = req("POST", "/subscriptions", token, {
        "data": {
            "type": "subscriptions",
            "attributes": {
                "name": SUBSCRIPTION_NAME,
                "productId": PRODUCT_ID,
                "familySharable": False,
                "subscriptionPeriod": "ONE_MONTH",
                "groupLevel": 1,
            },
            "relationships": {"group": {"data": {"type": "subscriptionGroups", "id": group_id}}},
        }
    })
    sub_id = body["data"]["id"]
    print(f"Created subscription: {sub_id}")
    return sub_id, True


def ensure_subscription_localization(token, sub_id):
    _, body = req("GET", f"/subscriptions/{sub_id}/subscriptionLocalizations", token)
    if any(loc["attributes"]["locale"] == "en-US" for loc in body["data"]):
        print("Subscription localization (en-US) already exists.")
        return
    req("POST", "/subscriptionLocalizations", token, {
        "data": {
            "type": "subscriptionLocalizations",
            "attributes": {"name": SUBSCRIPTION_NAME, "locale": "en-US", "description": SUBSCRIPTION_DESCRIPTION},
            "relationships": {"subscription": {"data": {"type": "subscriptions", "id": sub_id}}},
        }
    })
    print("Created subscription localization (en-US).")


def ensure_availability(token, sub_id):
    try:
        req("POST", "/subscriptionAvailabilities", token, {
            "data": {
                "type": "subscriptionAvailabilities",
                "attributes": {"availableInNewTerritories": True},
                "relationships": {
                    "subscription": {"data": {"type": "subscriptions", "id": sub_id}},
                    "availableTerritories": {"data": [{"type": "territories", "id": "USA"}]},
                },
            }
        })
        print("Created subscription availability (USA + new territories).")
    except urllib.error.HTTPError as e:
        # Already-set availability (or a deprecated/rejected endpoint on this
        # account) shouldn't abort the whole run -- pricing is the part that
        # actually blocks purchasability, so keep going and let that step
        # surface a real error if availability truly wasn't set.
        print(f"subscriptionAvailabilities POST failed ({e.code}); continuing -- may already be set.")


def ensure_price(token, sub_id):
    _, body = req("GET", f"/subscriptions/{sub_id}", token)
    if body["data"]["relationships"].get("prices", {}).get("data"):
        print("Subscription already has a price; skipping.")
        return

    price_point_id = None
    next_url = f"/subscriptions/{sub_id}/pricePoints?filter[territory]=USA&limit=200"
    while next_url and not price_point_id:
        status, body = req("GET", next_url, token)
        for p in body["data"]:
            if p["attributes"].get("customerPrice") == TARGET_PRICE:
                price_point_id = p["id"]
                break
        next_url = body.get("links", {}).get("next")
        if next_url and next_url.startswith("http"):
            next_url = next_url[len(BASE):]

    if not price_point_id:
        print(f"No USA price point found matching ${TARGET_PRICE}; skipping price setup.", file=sys.stderr)
        return

    status, body = req("PATCH", f"/subscriptions/{sub_id}", token, {
        "data": {
            "type": "subscriptions",
            "id": sub_id,
            "relationships": {"prices": {"data": [{"type": "subscriptionPrices", "id": "${new-price}"}]}},
        },
        "included": [{
            "type": "subscriptionPrices",
            "id": "${new-price}",
            "attributes": {"preserveCurrentPrice": False},
            "relationships": {
                "subscriptionPricePoint": {"data": {"type": "subscriptionPricePoints", "id": price_point_id}},
                "territory": {"data": {"type": "territories", "id": "USA"}},
            },
        }],
    })
    print(f"Set price (${TARGET_PRICE} USA, point {price_point_id}): {status}")


def ensure_review_note(token, sub_id):
    _, body = req("GET", f"/subscriptions/{sub_id}", token)
    if body["data"]["attributes"].get("reviewNote"):
        print("Review note already set.")
        return
    req("PATCH", f"/subscriptions/{sub_id}", token, {
        "data": {
            "type": "subscriptions",
            "id": sub_id,
            "attributes": {"reviewNote": "Unlocks unlimited keys/keyrings, loan reminders, location history, and duplicate detection. Same entitlement as the existing keyring_pro_unlock one-time IAP."},
        }
    })
    print("Set review note.")


def ensure_review_screenshot(token, sub_id):
    _, body = req("GET", f"/subscriptions/{sub_id}/appStoreReviewScreenshot", token)
    if body.get("data"):
        print("Review screenshot already attached.")
        return
    path = SCREENSHOTS_DIR / "05-paywall.png"
    if not path.exists():
        print(f"{path} not found; skipping review screenshot.", file=sys.stderr)
        return
    data = path.read_bytes()
    checksum = hashlib.md5(data).hexdigest()
    _, body = req("POST", "/subscriptionAppStoreReviewScreenshots", token, {
        "data": {
            "type": "subscriptionAppStoreReviewScreenshots",
            "attributes": {"fileName": path.name, "fileSize": len(data)},
            "relationships": {"subscription": {"data": {"type": "subscriptions", "id": sub_id}}},
        }
    })
    shot_id = body["data"]["id"]
    for op in body["data"]["attributes"]["uploadOperations"]:
        chunk = data[op["offset"]:op["offset"] + op["length"]]
        put_bytes(op["url"], op["requestHeaders"], chunk)
    req("PATCH", f"/subscriptionAppStoreReviewScreenshots/{shot_id}", token, {
        "data": {"type": "subscriptionAppStoreReviewScreenshots", "id": shot_id,
                  "attributes": {"sourceFileChecksum": checksum, "uploaded": True}}
    })
    print(f"Uploaded review screenshot: {shot_id}")


def main():
    token = make_jwt()
    group_id, _ = get_or_create_group(token)
    ensure_group_localization(token, group_id)
    sub_id, _ = get_or_create_subscription(token, group_id)
    ensure_subscription_localization(token, sub_id)
    ensure_availability(token, sub_id)
    ensure_price(token, sub_id)
    ensure_review_screenshot(token, sub_id)
    ensure_review_note(token, sub_id)
    print(f"Subscription ready: group={group_id} subscription={sub_id} productId={PRODUCT_ID}")

    _, body = req("GET", f"/subscriptions/{sub_id}", token)
    print(f"Subscription attributes: {json.dumps(body['data']['attributes'], indent=2)}")

    _, body = req("GET", f"/subscriptions/{sub_id}/appStoreReviewScreenshot", token)
    print(f"Review screenshot: {json.dumps(body.get('data'), indent=2)}")

    _, body = req("GET", f"/subscriptions/{sub_id}/subscriptionLocalizations", token)
    print(f"Localizations: {json.dumps(body.get('data'), indent=2)[:1500]}")

    _, body = req("GET", f"/subscriptionGroups/{group_id}/subscriptionGroupLocalizations", token)
    print(f"Group localizations: {json.dumps(body.get('data'), indent=2)[:1500]}")

    _, body = req("GET", f"/subscriptions/{sub_id}/prices", token)
    print(f"Prices: {json.dumps(body.get('data'), indent=2)[:1500]}")


if __name__ == "__main__":
    main()
