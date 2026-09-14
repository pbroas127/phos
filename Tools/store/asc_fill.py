# Fills the Phos App Store listing through the App Store Connect API.
# The app record itself must exist first (Apple only allows creating it on the website).
# Usage: python asc_fill.py [--screenshots-only | --text-only]
import hashlib, json, pathlib, sys, urllib.request

HERE = pathlib.Path(__file__).parent
sys.path.insert(0, str(HERE.parent.parent / ".secrets"))
from asc import call  # noqa: E402

M = json.loads((HERE / "metadata.json").read_text(encoding="utf-8"))


def ok(s, j, what):
    if s >= 300:
        print(f"FAILED {what}: {s} {json.dumps(j)[:600]}")
        return False
    print(f"ok {what}")
    return True


def app_id():
    s, j = call("GET", f"/v1/apps?filter[bundleId]={M['bundleId']}")
    if not j.get("data"):
        sys.exit("App record not found. Create it in App Store Connect first.")
    return j["data"][0]["id"]


def fill_info(aid):
    s, j = call("PATCH", f"/v1/apps/{aid}", {"data": {"type": "apps", "id": aid, "attributes": {
        "contentRightsDeclaration": "USES_THIRD_PARTY_CONTENT"}}})
    ok(s, j, "content rights")

    s, j = call("GET", f"/v1/apps/{aid}/appInfos")
    info = next(x for x in j["data"] if x["attributes"].get("appStoreState") != "READY_FOR_SALE")
    iid = info["id"]
    s, j = call("PATCH", f"/v1/appInfos/{iid}", {"data": {"type": "appInfos", "id": iid, "relationships": {
        "primaryCategory": {"data": {"type": "appCategories", "id": M["primaryCategory"]}},
        "secondaryCategory": {"data": {"type": "appCategories", "id": M["secondaryCategory"]}}}}})
    ok(s, j, "categories")

    s, j = call("GET", f"/v1/appInfos/{iid}/appInfoLocalizations")
    loc = next(x for x in j["data"] if x["attributes"]["locale"] == "en-US")
    s, j = call("PATCH", f"/v1/appInfoLocalizations/{loc['id']}", {"data": {"type": "appInfoLocalizations", "id": loc["id"],
        "attributes": {"name": M["name"], "subtitle": M["subtitle"], "privacyPolicyUrl": M["privacyPolicyUrl"]}}})
    ok(s, j, "name, subtitle and privacy url")

    s, j = call("GET", f"/v1/appInfos/{iid}/ageRatingDeclaration")
    rid = j["data"]["id"]
    attrs = {k: ("NONE" if isinstance(v, str) else False) for k, v in j["data"]["attributes"].items()
             if k not in ("kidsAgeBand", "developerAgeRatingInfoUrl", "ageRatingOverride", "ageRatingOverrideV2", "koreaAgeRatingOverride")}
    # Scripture includes historical accounts of war and violence.
    attrs["violenceRealistic"] = "INFREQUENT_OR_MILD"
    attrs["parentalControls"] = False
    s, j = call("PATCH", f"/v1/ageRatingDeclarations/{rid}", {"data": {"type": "ageRatingDeclarations", "id": rid, "attributes": attrs}})
    ok(s, j, "age rating")


def version(aid):
    s, j = call("GET", f"/v1/apps/{aid}/appStoreVersions?filter[platform]=IOS")
    v = next(x for x in j["data"] if x["attributes"]["appStoreState"] in ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED"))
    return v["id"]


def fill_version(aid):
    vid = version(aid)
    s, j = call("PATCH", f"/v1/appStoreVersions/{vid}", {"data": {"type": "appStoreVersions", "id": vid, "attributes": {
        "copyright": M["copyright"], "releaseType": "AFTER_APPROVAL"}}})
    ok(s, j, "copyright and release type")

    s, j = call("GET", f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations")
    loc = next(x for x in j["data"] if x["attributes"]["locale"] == "en-US")
    s, j = call("PATCH", f"/v1/appStoreVersionLocalizations/{loc['id']}", {"data": {"type": "appStoreVersionLocalizations", "id": loc["id"],
        "attributes": {"description": M["description"], "keywords": M["keywords"], "promotionalText": M["promotionalText"],
                       "supportUrl": M["supportUrl"], "marketingUrl": M["marketingUrl"]}}})
    ok(s, j, "description, keywords, urls")

    c = M["reviewContact"]
    attrs = {"contactFirstName": c["firstName"], "contactLastName": c["lastName"], "contactPhone": c["phone"],
             "contactEmail": c["email"], "demoAccountRequired": False, "notes": M["reviewNotes"]}
    s, j = call("GET", f"/v1/appStoreVersions/{vid}/appStoreReviewDetail")
    if j.get("data"):
        rid = j["data"]["id"]
        s, j = call("PATCH", f"/v1/appStoreReviewDetails/{rid}", {"data": {"type": "appStoreReviewDetails", "id": rid, "attributes": attrs}})
    else:
        s, j = call("POST", "/v1/appStoreReviewDetails", {"data": {"type": "appStoreReviewDetails", "attributes": attrs,
            "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}})
    ok(s, j, "review details")
    return vid


def fill_pricing(aid):
    s, j = call("GET", f"/v1/apps/{aid}/appPricePoints?filter[territory]=USA&limit=200")
    free = next(x for x in j["data"] if float(x["attributes"]["customerPrice"]) == 0.0)
    s, j = call("POST", "/v1/appPriceSchedules", {
        "data": {"type": "appPriceSchedules", "relationships": {
            "app": {"data": {"type": "apps", "id": aid}},
            "baseTerritory": {"data": {"type": "territories", "id": "USA"}},
            "manualPrices": {"data": [{"type": "appPrices", "id": "${price}"}]}}},
        "included": [{"type": "appPrices", "id": "${price}", "attributes": {"startDate": None},
                      "relationships": {"appPricePoint": {"data": {"type": "appPricePoints", "id": free["id"]}}}}]})
    ok(s, j, "free pricing")

    s, j = call("GET", "/v1/territories?limit=200")
    terrs = [t["id"] for t in j["data"]]
    included = [{"type": "territoryAvailabilities", "id": f"${{{t}}}", "attributes": {"available": True}} for t in terrs]
    s, j = call("POST", "/v2/appAvailabilities", {
        "data": {"type": "appAvailabilities", "attributes": {"availableInNewTerritories": True}, "relationships": {
            "app": {"data": {"type": "apps", "id": aid}},
            "territoryAvailabilities": {"data": [{"type": "territoryAvailabilities", "id": x["id"]} for x in included]}}},
        "included": [{**x, "relationships": {"territory": {"data": {"type": "territories", "id": x["id"][2:-1]}}}} for x in included]})
    ok(s, j, f"availability in {len(terrs)} territories")


def upload_screenshots(aid):
    vid = version(aid)
    s, j = call("GET", f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations")
    lid = next(x for x in j["data"] if x["attributes"]["locale"] == "en-US")["id"]
    s, j = call("GET", f"/v1/appStoreVersionLocalizations/{lid}/appScreenshotSets")
    sset = next((x for x in j["data"] if x["attributes"]["screenshotDisplayType"] == "APP_IPHONE_65"), None)
    if sset:
        s, j = call("GET", f"/v1/appScreenshotSets/{sset['id']}/appScreenshots")
        for shot in j.get("data", []):
            call("DELETE", f"/v1/appScreenshots/{shot['id']}")
        sid = sset["id"]
    else:
        s, j = call("POST", "/v1/appScreenshotSets", {"data": {"type": "appScreenshotSets", "attributes": {"screenshotDisplayType": "APP_IPHONE_65"},
            "relationships": {"appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": lid}}}}})
        sid = j["data"]["id"]
    for slide in M["slides"]:
        path = HERE / "slides" / slide["file"]
        data = path.read_bytes()
        s, j = call("POST", "/v1/appScreenshots", {"data": {"type": "appScreenshots", "attributes": {"fileName": slide["file"], "fileSize": len(data)},
            "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": sid}}}}})
        if not ok(s, j, f"reserve {slide['file']}"):
            continue
        shot = j["data"]
        for op in shot["attributes"]["uploadOperations"]:
            chunk = data[op["offset"]:op["offset"] + op["length"]]
            req = urllib.request.Request(op["url"], data=chunk, method=op["method"], headers={h["name"]: h["value"] for h in op["requestHeaders"]})
            urllib.request.urlopen(req).read()
        s, j = call("PATCH", f"/v1/appScreenshots/{shot['id']}", {"data": {"type": "appScreenshots", "id": shot["id"],
            "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})
        ok(s, j, f"upload {slide['file']}")


if __name__ == "__main__":
    aid = app_id()
    print("app", aid)
    if "--screenshots-only" not in sys.argv:
        fill_info(aid)
        fill_version(aid)
        fill_pricing(aid)
    if "--text-only" not in sys.argv:
        upload_screenshots(aid)
