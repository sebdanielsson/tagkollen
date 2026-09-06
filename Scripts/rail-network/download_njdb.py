"""Download the NJDB GeoPackage ("Järnvägsnät med grundegenskaper") from Lastkajen.

Lastkajen has no anonymous access, but its REST API (see
https://lastkajen.trafikverket.se/assets/Lastkajen2_API_Information.pdf) lets an account holder
fetch published data packages with a bearer token. Register once at
https://lastkajen.trafikverket.se, then run:

    LASTKAJEN_USER=... LASTKAJEN_PASSWORD=... python3 download_njdb.py

The archive is unpacked into railnet/ next to this script, where build_graph.py expects it.
"""

import io
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
import zipfile

BASE = "https://lastkajen.trafikverket.se/api"
PACKAGE_NAME = "Järnvägsnät med grundegenskaper"
OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "railnet")


def send(request):
    """Performs a request, turning an HTTP error into the server's own message. Lastkajen answers
    400 with a human-readable Swedish string for anything it doesn't like, credentials included."""
    try:
        with urllib.request.urlopen(request) as response:
            return response.read()
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", "replace").strip()
        sys.exit(f"{request.get_full_url()} failed: HTTP {error.code} {error.reason}\n{detail}")


def call(path, bearer=None, **params):
    url = f"{BASE}/{path}"
    if params:
        url += "?" + urllib.parse.urlencode(params)
    request = urllib.request.Request(url)
    if bearer:
        request.add_header("Authorization", f"Bearer {bearer}")
    return send(request)


def version_of(name):
    """Sort key from a file name like `..._grundegenskaper3_0_GeoPackage.zip` -> (3, 0)."""
    numbers = [int(n) for n in re.findall(r"\d+", name)]
    return tuple(numbers) if numbers else (0,)


def login(user, password):
    # JSON, not form encoding: the API rejects a form body with a bare 400.
    body = json.dumps({"UserName": user, "Password": password}).encode()
    request = urllib.request.Request(f"{BASE}/Identity/Login", data=body, method="POST")
    request.add_header("Content-Type", "application/json")
    return json.loads(send(request))["access_token"]


def main():
    user, password = os.environ.get("LASTKAJEN_USER"), os.environ.get("LASTKAJEN_PASSWORD")
    if not user or not password:
        sys.exit("Set LASTKAJEN_USER and LASTKAJEN_PASSWORD (a free Lastkajen account)")
    token = login(user, password)

    packages = json.loads(call("DataPackage/GetPublishedDataPackages", token))
    matches = [p for p in packages if PACKAGE_NAME.casefold() in (p.get("name") or "").casefold()]
    if not matches:
        names = sorted(p.get("name") or "" for p in packages)
        sys.exit(f"No published package matching '{PACKAGE_NAME}'. Available: {names}")
    if len(matches) > 1:
        print("Matching packages:", [(p["id"], p["name"]) for p in matches])

    # Collect every GeoPackage across the matching packages and take the newest version, so a new
    # NJDB release is picked up without editing anything here.
    candidates = []
    for package in matches:
        files = json.loads(call("DataPackage/GetDataPackageFiles", token, id=package["id"]))
        for entry in files:
            if not entry.get("isFolder") and "geopackage" in entry["name"].casefold():
                candidates.append((version_of(entry["name"]), package, entry))
    if not candidates:
        sys.exit(f"No GeoPackage file in {[p['name'] for p in matches]}")
    _, package, newest = max(candidates, key=lambda c: c[0])
    file_name = newest["name"]
    print(f"Package {package['id']}: {package['name']}")
    print(f"Downloading {file_name} ({newest.get('size')})")

    # The download token is single-use and valid for 60 s; the file itself needs no auth.
    download_token = json.loads(call("file/GetDataPackageDownloadToken", token, id=package["id"], fileName=file_name))
    data = call("File/GetDataPackageFile", token=download_token)

    os.makedirs(OUT_DIR, exist_ok=True)
    if file_name.casefold().endswith(".zip"):
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            archive.extractall(OUT_DIR)
            print(f"Unpacked into {OUT_DIR}:")
            for name in archive.namelist():
                print("   ", name)
    else:
        with open(os.path.join(OUT_DIR, file_name), "wb") as f:
            f.write(data)
        print(f"Saved {os.path.join(OUT_DIR, file_name)}")


if __name__ == "__main__":
    main()
