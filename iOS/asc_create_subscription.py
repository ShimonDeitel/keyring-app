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
import base64
import hashlib
import json
import os
import re
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
    # Not a simple "has any price -> skip": the first run only priced USA
    # and left ~150 other territories missing, which blocks review
    # submission. Re-check against the full territory count instead of a
    # single existence check -- PATCHing already-correct prices again is
    # harmless.
    _, body = req("GET", f"/subscriptions/{sub_id}", token)
    existing_prices = body["data"]["relationships"].get("prices", {}).get("data") or []

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

    # Apple rejects review submission unless EVERY territory the
    # subscription is available in has upfront pricing, not just USA --
    # STATE_ERROR.IAP_SUBMISSION_NOT_ALLOWED_MISSING_PRICING_DATA lists
    # ~150 missing territories otherwise. Equalizations gives the
    # locally-equivalent price point per territory for the USA base point;
    # the territory code lives inside the base64-decoded point id (field
    # "t"), there's no separate territory relationship on the resource.
    territory_points = {}  # territory code -> price point id
    next_url = f"/subscriptionPricePoints/{price_point_id}/equalizations?limit=200"
    while next_url:
        status, body = req("GET", next_url, token)
        for p in body["data"]:
            padded = p["id"] + "=" * (-len(p["id"]) % 4)
            decoded = json.loads(base64.urlsafe_b64decode(padded))
            territory = decoded.get("t")
            if territory:
                territory_points[territory] = p["id"]
        next_url = body.get("links", {}).get("next")
        if next_url and next_url.startswith("http"):
            next_url = next_url[len(BASE):]
    territory_points["USA"] = price_point_id
    print(f"{len(territory_points)} territories need pricing; {len(existing_prices)} price(s) already set.")

    if len(existing_prices) >= len(territory_points):
        print("Already fully priced; skipping.")
        return

    included = []
    price_refs = []
    for i, (territory, point_id) in enumerate(territory_points.items()):
        placeholder = f"${{price-{i}}}"
        price_refs.append({"type": "subscriptionPrices", "id": placeholder})
        included.append({
            "type": "subscriptionPrices",
            "id": placeholder,
            "attributes": {"preserveCurrentPrice": False},
            "relationships": {
                "subscriptionPricePoint": {"data": {"type": "subscriptionPricePoints", "id": point_id}},
                "territory": {"data": {"type": "territories", "id": territory}},
            },
        })

    status, body = req("PATCH", f"/subscriptions/{sub_id}", token, {
        "data": {
            "type": "subscriptions",
            "id": sub_id,
            "relationships": {"prices": {"data": price_refs}},
        },
        "included": included,
    })
    print(f"Set price (${TARGET_PRICE} USA + {len(territory_points) - 1} equalized territories): {status}")


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


def get_inflight_version_id(token, resource_path, resource_type, relationship_name, relationship_type, relationship_id):
    """Both subscriptionVersions and subscriptionGroupVersions are
    auto-created alongside their parent (subscription / subscription
    group) -- there's no GET path that surfaces them directly, but
    POSTing a new one 409s with STATE_ERROR.ALREADY_EXISTS and names the
    existing id in the error detail. Parse it out of there. (Doesn't use
    the shared req() helper because that already consumes the error body
    once.)"""
    url = BASE + resource_path
    data = json.dumps({
        "data": {
            "type": resource_type,
            "relationships": {relationship_name: {"data": {"type": relationship_type, "id": relationship_id}}},
        }
    }).encode()
    r = urllib.request.Request(url, data=data, method="POST")
    r.add_header("Authorization", f"Bearer {token}")
    r.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(r) as resp:
            body = json.loads(resp.read())
            version_id = body["data"]["id"]
            print(f"Created new {resource_type}: {version_id}")
            return version_id
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            errors = json.loads(raw).get("errors", [])
        except json.JSONDecodeError:
            errors = []
        for err in errors:
            if err.get("code") == "STATE_ERROR.ALREADY_EXISTS":
                match = re.search(r"inflight version with id '([0-9a-f-]+)'", err.get("detail", ""))
                if match:
                    version_id = match.group(1)
                    print(f"Existing {resource_type}: {version_id}")
                    return version_id
        print(f"{resource_type} POST failed unexpectedly ({e.code}): {raw[:1000]}", file=sys.stderr)
        return None


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
    version_id = get_inflight_version_id(
        token, "/subscriptionVersions", "subscriptionVersions", "subscription", "subscriptions", sub_id
    )
    if version_id:
        print(f"SUBSCRIPTION_VERSION_ID={version_id}")

    group_version_id = get_inflight_version_id(
        token, "/subscriptionGroupVersions", "subscriptionGroupVersions", "subscriptionGroup", "subscriptionGroups", group_id
    )
    if group_version_id:
        print(f"SUBSCRIPTION_GROUP_VERSION_ID={group_version_id}")

    _, body = req("GET", f"/subscriptions/{sub_id}", token)
    print(f"Subscription state: {body['data']['attributes'].get('state')}")
    print(f"Subscription ready: group={group_id} subscription={sub_id} productId={PRODUCT_ID}")


if __name__ == "__main__":
    main()
