"""RB02 direct Google Drive transport. Windows Owner only; no Desktop sync.

OAuth scope drive.file; the app creates its own private Brain Inbox.
No credentials, paths or report bytes in public receipts.
Run enroll interactively once, then publish unattended from the Owner task.
"""
import argparse
import json
import os
from pathlib import Path
import re
import sys
import tempfile
import uuid

import report_bridge as rb

SCOPE = "https://www.googleapis.com/auth/drive.file"
BASE = "https://www.googleapis.com/drive/v3"
UPLOAD = "https://www.googleapis.com/upload/drive/v3/files"
FOLDER = "Torrent TV Vietsub - Brain Inbox API"
FOLDER_MIME = "application/vnd.google-apps.folder"
FIELDS = "id,name,mimeType,parents,trashed,shared,size,sha256Checksum"
MAX_UPLOAD = 5 * 1024 * 1024  # bounded multipart; larger bundles stay local pending resumable support

class Hold(Exception):
    pass

def ensure(ok, code):
    if not ok:
        raise Hold(code)

def atomic(path, obj):
    fd, tmp = tempfile.mkstemp(prefix=".state-", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(rb.json_bytes(obj))
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)

def state_dir():
    ensure(os.name == "nt" and os.environ.get("GITHUB_ACTIONS") != "true", "OWNER_CONTEXT_REQUIRED")
    p = Path(os.environ["LOCALAPPDATA"]) / "TorrentTVVietsub" / "ReportBridgeApi"
    p.mkdir(parents=True, exist_ok=True)
    rb.plain(p)
    return p

def load(path):
    return rb.read_json(path)

class Drive:
    def __init__(self, session):
        self.s = session

    def request(self, method, url, *, missing=False, **kwargs):
        try:
            response = self.s.request(method, url, timeout=(10, 90), **kwargs)
        except Exception:
            raise Hold("DRIVE_REQUEST_UNKNOWN_EFFECT") from None
        if response.status_code == 404 and missing:
            return None
        if response.status_code == 409:
            raise Hold("DRIVE_ID_CONFLICT")
        if response.status_code == 401:
            raise Hold("OAUTH_REAUTH_REQUIRED")
        if not 200 <= response.status_code < 300:
            raise Hold("DRIVE_HTTP_" + str(response.status_code))
        return response

    def account(self):
        r = self.request("GET", BASE + "/about", params={"fields": "user(emailAddress)"}).json()
        return r.get("user", {}).get("emailAddress", "").casefold()

    def ids(self, count):
        r = self.request("GET", BASE + "/files/generateIds",
                         params={"count": count, "space": "drive", "type": "files"}).json()
        ids = r.get("ids", [])
        ensure(len(ids) == len(set(ids)) == count and all(re.fullmatch(r"[A-Za-z0-9_-]+", i) for i in ids),
               "DRIVE_GENERATE_IDS")
        return ids

    def metadata(self, id):
        ensure(re.fullmatch(r"[A-Za-z0-9_-]+", id), "DRIVE_ID_INVALID")
        r = self.request("GET", BASE + "/files/" + id, missing=True, params={"fields": FIELDS})
        return r.json() if r is not None else None

    def create_folder(self, id):
        try:
            self.request("POST", BASE + "/files", json={"id": id, "name": FOLDER, "mimeType": FOLDER_MIME},
                         params={"fields": FIELDS})
        except Hold as e:
            if str(e) != "DRIVE_ID_CONFLICT":
                raise

    def folder(self, id):
        m = self.metadata(id)
        if m is None:
            self.create_folder(id)
            m = self.metadata(id)
        ensure(m and m.get("id") == id and m.get("name") == FOLDER
               and m.get("mimeType") == FOLDER_MIME and m.get("trashed") is False
               and m.get("shared") is False, "DRIVE_FOLDER_UNVERIFIED")

    def check_folder(self, id):
        m = self.metadata(id)
        ensure(m and m.get("id") == id and m.get("name") == FOLDER
               and m.get("mimeType") == FOLDER_MIME and m.get("trashed") is False
               and m.get("shared") is False, "DRIVE_FOLDER_UNVERIFIED")

    def create_bytes(self, id, folder, name, mime, data):
        boundary = "ttv_" + uuid.uuid4().hex
        meta = json.dumps({"id": id, "parents": [folder], "name": name, "mimeType": mime}).encode()
        body = (("--" + boundary + "\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n").encode()
                + meta + ("\r\n--" + boundary + "\r\nContent-Type: " + mime + "\r\n\r\n").encode()
                + data + ("\r\n--" + boundary + "--\r\n").encode())
        try:
            self.request("POST", UPLOAD, params={"uploadType": "multipart", "fields": FIELDS},
                         headers={"Content-Type": "multipart/related; boundary=" + boundary}, data=body)
        except Hold as e:
            if str(e) != "DRIVE_ID_CONFLICT":
                raise

    def checked_bytes(self, id, folder, name, mime, data):
        m = self.metadata(id)
        if m is None:
            self.create_bytes(id, folder, name, mime, data)
            m = self.metadata(id)
        ensure(m and m.get("id") == id and m.get("name") == name and m.get("parents") == [folder]
               and m.get("mimeType") == mime and m.get("trashed") is False and m.get("shared") is False
               and str(m.get("size")) == str(len(data)), "DRIVE_METADATA_CONFLICT")
        r = self.request("GET", BASE + "/files/" + id, params={"alt": "media"}, stream=True)
        import hashlib
        h = hashlib.sha256()
        size = 0
        try:
            for chunk in r.iter_content(65536):
                size += len(chunk)
                ensure(size <= len(data), "DRIVE_BYTES_CONFLICT")
                h.update(chunk)
        finally:
            r.close()
        ensure(size == len(data) and h.hexdigest() == rb.digest(data), "DRIVE_BYTES_CONFLICT")

def session_from_credentials(credentials):
    from google.auth.transport.requests import AuthorizedSession
    return Drive(AuthorizedSession(credentials))

def enroll(p, client, expected_account):
    from google_auth_oauthlib.flow import InstalledAppFlow
    ensure(not (p / "oauth.json").exists(), "OAUTH_ALREADY_ENROLLED")
    flow = InstalledAppFlow.from_client_secrets_file(str(client), [SCOPE], autogenerate_code_verifier=True)
    credentials = flow.run_local_server(host="127.0.0.1", port=0, access_type="offline",
                                        prompt="consent", login_hint=expected_account,
                                        authorization_prompt_message="")
    ensure(credentials.refresh_token and credentials.has_scopes([SCOPE]), "OAUTH_SCOPE_OR_REFRESH_MISSING")
    drive = session_from_credentials(credentials)
    ensure(drive.account() == expected_account.casefold(), "OAUTH_WRONG_ACCOUNT")
    config = p / "folder.json"
    if config.exists():
        state = load(config)
        ensure(state["account"] == expected_account.casefold(), "OAUTH_WRONG_ACCOUNT")
    else:
        state = {"account": expected_account.casefold(), "folder": drive.ids(1)[0]}
        atomic(config, state)
    drive.folder(state["folder"])
    # Owner-private LocalAppData; never copy credentials into the HostOps spool or Git.
    atomic(p / "oauth.json", json.loads(credentials.to_json()))
    return {"state": "API_ENROLLED", "folder_id": state["folder"]}

def publish(drive, p, folder, bundle, ready, source, nonce):
    evidence = rb.verify(bundle, ready, source, nonce)
    z = rb.read(bundle, rb.TOTAL + rb.CAP)
    r = rb.read(ready)
    ensure(rb.digest(z) == evidence["sha256"], "LOCAL_BYTES_CHANGED")
    ensure(len(z) <= MAX_UPLOAD and len(r) <= MAX_UPLOAD, "API_MULTIPART_LIMIT")
    drive.check_folder(folder)
    journal = p / ("upload-" + source + "-" + nonce + ".json")
    identity = {"folder": folder, "source": source, "nonce": nonce, "zip_sha256": rb.digest(z),
                "ready_sha256": rb.digest(r)}
    if journal.exists():
        j = load(journal)
        ensure(j.get("identity") == identity, "LOCAL_JOURNAL_CONFLICT")
    else:
        ids = drive.ids(2)
        j = {"identity": identity, "zip_id": ids[0], "ready_id": ids[1]}
        atomic(journal, j)  # stable IDs persisted before the first remote side effect
    ensure(j["zip_id"] != j["ready_id"], "DRIVE_ID_CONFLICT")
    drive.checked_bytes(j["zip_id"], folder, bundle.name, "application/zip", z)
    drive.checked_bytes(j["ready_id"], folder, ready.name, "application/json", r)
    return {"state": "API_UPLOAD_VERIFIED", "folder_id": folder, "zip_id": j["zip_id"],
            "ready_id": j["ready_id"], "source": source, "nonce": nonce,
            "sha256": evidence["sha256"], "bytes": len(z), "file_count": evidence["file_count"]}

def run_publish(p, source, nonce):
    from google.oauth2.credentials import Credentials
    ensure((p / "oauth.json").is_file() and (p / "folder.json").is_file(), "OAUTH_ENROLLMENT_REQUIRED")
    credentials = Credentials.from_authorized_user_info(load(p / "oauth.json"), scopes=[SCOPE])
    drive = session_from_credentials(credentials)
    state = load(p / "folder.json")
    ensure(drive.account() == state["account"], "OAUTH_WRONG_ACCOUNT")
    staging = p / "staging"
    staging.mkdir(exist_ok=True)
    root = Path(os.environ["LOCALAPPDATA"]) / "TorrentTVVietsub" / "NativeBrowserTest"
    spool = Path(os.environ["ProgramData"]) / "TorrentTVVietsub" / "LaptopHostOps"
    result = rb.export(root, spool, staging, source, nonce)
    bundle = staging / result["zip"]
    ready = staging / (bundle.stem + ".ready.json")
    result = publish(drive, p, state["folder"], bundle, ready, source, nonce)
    return result

def main():
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="mode", required=True)
    e = sub.add_parser("enroll")
    e.add_argument("--client", required=True, type=Path)
    e.add_argument("--account", required=True)
    u = sub.add_parser("publish")
    u.add_argument("--source", required=True)
    u.add_argument("--nonce", required=True)
    a = p.parse_args()
    try:
        root = state_dir()
        if a.mode == "enroll":
            result = enroll(root, a.client, a.account)
        else:
            rb.valid_id(a.source, a.nonce)
            result = run_publish(root, a.source, a.nonce)
        print(json.dumps(result, sort_keys=True))
        return 0
    except Hold as e:
        print(json.dumps({"state": "HOLD", "reason": str(e)}))
        return 2
    except Exception:
        print(json.dumps({"state": "HOLD", "reason": "API_LOCAL_OR_AUTH_ERROR"}))
        return 2

if __name__ == "__main__":
    sys.exit(main())
