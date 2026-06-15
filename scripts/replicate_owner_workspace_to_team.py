#!/usr/bin/env python3
import json
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from urllib import error, parse, request

PROJECT_ID = "mbworkflow-8b9f6"
API_KEY = "AIzaSyClZrKGod5wEMJwFD__ZeZglbid1ywyO_M"

OWNER_EMAIL = "claudia.gottardello@gweb.agency"
OWNER_PASSWORD = "Gweb123450"
OWNER_UID = "mzw8lZMbRoV1OraKuKA4nZJXF4k2"
TEAM_ID = "team-mzw8lZMb"

COLLECTIONS = [
    "companies",
    "companyContacts",
    "crmContacts",
    "products",
    "projects",
    "phases",
    "tasks",
]

KNOWN_USERS = [
    {"name": "Claudia Gottardello", "email": "claudia.gottardello@gweb.agency", "password": "Gweb123450"},
    {"name": "Riccardo Sacchetto", "email": "sacchetto.riccardo@gmail.com", "password": "Milanista99"},
    {"name": "Jonathan Scarafile", "email": "jonathan.scarafile@gweb.agency", "password": "Gweb123450"},
    {"name": "Nicolo Schenato", "email": "nicolo.schenato@gweb.agency", "password": "Gweb123450"},
    {"name": "Giuseppe Grasso", "email": "giuseppe.grasso@gweb.agency", "password": "Gweb123450"},
]


def http_json(method, url, data=None, headers=None, params=None, retries=5):
    if params:
        url = f"{url}?{parse.urlencode(params, doseq=True)}"

    req_headers = {"Content-Type": "application/json"}
    if headers:
        req_headers.update(headers)

    body = json.dumps(data).encode("utf-8") if data is not None else None

    for attempt in range(retries):
        req = request.Request(url=url, data=body, headers=req_headers, method=method)
        try:
            with request.urlopen(req, timeout=60) as resp:
                raw = resp.read().decode("utf-8")
                return resp.status, (json.loads(raw) if raw else {})
        except error.HTTPError as e:
            raw = e.read().decode("utf-8") if e.fp else ""
            try:
                parsed = json.loads(raw) if raw else {}
            except Exception:
                parsed = {"raw": raw}
            if e.code in (429, 500, 502, 503, 504) and attempt < retries - 1:
                time.sleep(0.4 * (2 ** attempt))
                continue
            return e.code, parsed
        except Exception as ex:
            if attempt < retries - 1:
                time.sleep(0.4 * (2 ** attempt))
                continue
            return 599, {"error": str(ex)}


def login(email, password):
    st, data = http_json(
        "POST",
        f"https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key={API_KEY}",
        data={"email": email, "password": password, "returnSecureToken": True},
    )
    if st != 200:
        raise RuntimeError(f"Login fallito {email}: {data}")
    return data["idToken"], data["localId"]


def fs_get(path, token, params=None):
    url = f"https://firestore.googleapis.com/v1/projects/{PROJECT_ID}/databases/(default)/documents/{path}"
    return http_json("GET", url, headers={"Authorization": f"Bearer {token}"}, params=params)


def fs_patch_raw(path, token, fields):
    url = f"https://firestore.googleapis.com/v1/projects/{PROJECT_ID}/databases/(default)/documents/{path}"
    return http_json("PATCH", url, data={"fields": fields}, headers={"Authorization": f"Bearer {token}"})


def list_all_docs(path, token, page_size=400):
    out = []
    page_token = None
    while True:
        params = {"pageSize": page_size}
        if page_token:
            params["pageToken"] = page_token
        st, payload = fs_get(path, token, params=params)
        if st != 200:
            if st == 404:
                return out
            raise RuntimeError(f"Errore lettura {path}: status={st} payload={payload}")
        docs = payload.get("documents", []) or []
        out.extend(docs)
        page_token = payload.get("nextPageToken")
        if not page_token:
            return out


def read_team_members(owner_token):
    docs = list_all_docs(f"teams/{TEAM_ID}/members", owner_token, page_size=200)
    members = []
    for d in docs:
        f = d.get("fields", {})
        uid = f.get("userId", {}).get("stringValue", "")
        email = f.get("email", {}).get("stringValue", "")
        display = f.get("displayName", {}).get("stringValue", "")
        if uid:
            members.append({"uid": uid, "email": email, "displayName": display})
    by_uid = {m["uid"]: m for m in members}
    return [by_uid[k] for k in sorted(by_uid)]


def resolve_target_tokens(team_members):
    pwd_by_email = {u["email"].lower(): u["password"] for u in KNOWN_USERS}
    out = []
    for m in team_members:
        uid = m["uid"]
        email = (m.get("email") or "").strip().lower()
        if uid == OWNER_UID:
            continue
        password = pwd_by_email.get(email)
        if not password:
            out.append({"uid": uid, "email": email, "token": None, "status": "missing_password"})
            continue
        try:
            token, local_uid = login(email, password)
            if local_uid != uid:
                out.append({"uid": uid, "email": email, "token": None, "status": f"uid_mismatch:{local_uid}"})
                continue
            out.append({"uid": uid, "email": email, "token": token, "status": "ok"})
        except Exception as ex:
            out.append({"uid": uid, "email": email, "token": None, "status": f"login_error:{ex}"})
    return out


def replicate_to_target(target, collection_docs, collection_name):
    uid = target["uid"]
    token = target["token"]
    if not token:
        return {"uid": uid, "collection": collection_name, "ok": 0, "err": len(collection_docs), "status": target["status"]}

    jobs = []
    for d in collection_docs:
        doc_id = d.get("name", "").split("/")[-1]
        fields = d.get("fields", {})
        jobs.append((doc_id, fields))

    ok = 0
    err = 0

    def worker(job):
        doc_id, fields = job
        path = f"users/{uid}/{collection_name}/{doc_id}"
        st, _ = fs_patch_raw(path, token, fields)
        return st

    with ThreadPoolExecutor(max_workers=18) as ex:
        futures = [ex.submit(worker, j) for j in jobs]
        for fut in as_completed(futures):
            st = fut.result()
            if st < 300:
                ok += 1
            else:
                err += 1

    return {"uid": uid, "collection": collection_name, "ok": ok, "err": err, "status": "ok"}


def main():
    owner_token, owner_uid = login(OWNER_EMAIL, OWNER_PASSWORD)
    print(f"Login owner OK uid={owner_uid}")
    if owner_uid != OWNER_UID:
        raise RuntimeError(f"Owner UID inatteso: {owner_uid} != {OWNER_UID}")

    team_members = read_team_members(owner_token)
    print(f"Team members trovati: {len(team_members)}")

    targets = resolve_target_tokens(team_members)
    print("Target auth:")
    for t in targets:
        print(f"- {t['uid']} {t['email']} => {t['status']}")

    active_targets = [t for t in targets if t.get("token")]
    print(f"Target attivi replica: {len(active_targets)}")

    summary = {
        "teamId": TEAM_ID,
        "ownerUid": OWNER_UID,
        "targets": [{"uid": t["uid"], "email": t["email"], "status": t["status"]} for t in targets],
        "collections": [],
    }

    for cname in COLLECTIONS:
        docs = list_all_docs(f"users/{OWNER_UID}/{cname}", owner_token, page_size=400)
        print(f"\n[{cname}] docs sorgente={len(docs)}")

        cres = {"collection": cname, "sourceDocs": len(docs), "targets": []}
        for t in targets:
            if t.get("token"):
                res = replicate_to_target(t, docs, cname)
            else:
                res = {"uid": t["uid"], "collection": cname, "ok": 0, "err": len(docs), "status": t["status"]}
            cres["targets"].append(res)
            print(f"[{cname}] -> {t['email']} ok={res['ok']} err={res['err']} status={res['status']}")

        summary["collections"].append(cres)

    print("\nReplica completata")
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
