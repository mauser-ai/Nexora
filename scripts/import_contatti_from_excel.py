#!/usr/bin/env python3
import hashlib
import json
import re
from datetime import datetime, timezone
from urllib import parse, request, error

from openpyxl import load_workbook

PROJECT_ID = "mbworkflow-8b9f6"
API_KEY = "AIzaSyClZrKGod5wEMJwFD__ZeZglbid1ywyO_M"

OWNER_EMAIL = "claudia.gottardello@gweb.agency"
OWNER_PASSWORD = "Gweb123450"

CONTACTS_FILE = "/Users/riccardosacchetto/Downloads/Contacts-2026-04-24-16-28-04.xlsx"
DEFAULT_ROLE = "Default"

KNOWN_USERS = [
    {"name": "Claudia Gottardello", "email": "claudia.gottardello@gweb.agency", "password": "Gweb123450"},
    {"name": "Riccardo Sacchetto", "email": "sacchetto.riccardo@gmail.com", "password": "Milanista99"},
    {"name": "Jonathan Scarafile", "email": "jonathan.scarafile@gweb.agency", "password": "Gweb123450"},
    {"name": "Nicolo Schenato", "email": "nicolo.schenato@gweb.agency", "password": "Gweb123450"},
    {"name": "Giuseppe Grasso", "email": "giuseppe.grasso@gweb.agency", "password": "Gweb123450"},
]


def http_json(method, url, data=None, headers=None, params=None):
    if params:
        q = parse.urlencode(params, doseq=True)
        url = f"{url}?{q}"
    body = None
    req_headers = {"Content-Type": "application/json"}
    if headers:
        req_headers.update(headers)
    if data is not None:
        body = json.dumps(data).encode("utf-8")

    req = request.Request(url=url, data=body, headers=req_headers, method=method)
    try:
        with request.urlopen(req, timeout=30) as resp:
            raw = resp.read().decode("utf-8")
            return resp.status, json.loads(raw) if raw else {}
    except error.HTTPError as e:
        raw = e.read().decode("utf-8") if e.fp else ""
        try:
            parsed = json.loads(raw) if raw else {}
        except Exception:
            parsed = {"raw": raw}
        return e.code, parsed


def clean(v):
    if v is None:
        return ""
    if isinstance(v, datetime):
        return v.isoformat()
    if isinstance(v, (int, float)):
        if isinstance(v, float) and v.is_integer():
            return str(int(v))
        return str(v)
    s = str(v).strip().strip('"').strip("'")
    s = re.sub(r"\s+", " ", s)
    return s


def normalize_name(name):
    s = clean(name).lower()
    s = s.replace("s.r.l.", "srl").replace("s.r.l", "srl")
    s = s.replace("s.p.a.", "spa").replace("s.p.a", "spa")
    s = re.sub(r"[^a-z0-9 ]+", "", s)
    return re.sub(r"\s+", " ", s).strip()


def is_emptyish(v):
    return clean(v).lower() in {"", "-", "n/a", "na", "none", "null"}


def login(email, password):
    status, data = http_json(
        "POST",
        f"https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key={API_KEY}",
        data={"email": email, "password": password, "returnSecureToken": True},
    )
    if status != 200:
        raise RuntimeError(f"Login fallito {email}: {data}")
    return data["idToken"], data["localId"]


def signup(email, password):
    return http_json(
        "POST",
        f"https://identitytoolkit.googleapis.com/v1/accounts:signUp?key={API_KEY}",
        data={"email": email, "password": password, "returnSecureToken": True},
    )


def fs_get(path, token, params=None):
    url = f"https://firestore.googleapis.com/v1/projects/{PROJECT_ID}/databases/(default)/documents/{path}"
    return http_json("GET", url, headers={"Authorization": f"Bearer {token}"}, params=params)


def fs_patch(path, token, fields):
    url = f"https://firestore.googleapis.com/v1/projects/{PROJECT_ID}/databases/(default)/documents/{path}"
    return http_json("PATCH", url, data={"fields": fields}, headers={"Authorization": f"Bearer {token}"})


def fs_doc_to_plain(fields):
    out = {}
    for k, v in (fields or {}).items():
        if "stringValue" in v:
            out[k] = v["stringValue"]
        elif "integerValue" in v:
            out[k] = str(v["integerValue"])
        elif "doubleValue" in v:
            out[k] = str(v["doubleValue"])
        elif "booleanValue" in v:
            out[k] = bool(v["booleanValue"])
        elif "timestampValue" in v:
            out[k] = v["timestampValue"]
        elif "arrayValue" in v:
            arr = []
            for item in v.get("arrayValue", {}).get("values", []) or []:
                if "stringValue" in item:
                    arr.append(item["stringValue"])
            out[k] = arr
        else:
            out[k] = ""
    return out


def timestamp_field(dt):
    if isinstance(dt, datetime):
        return {"timestampValue": dt.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")}
    return {"timestampValue": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")}


def string_field(v):
    return {"stringValue": clean(v)}


def array_string_field(values):
    cleaned = [clean(v) for v in values if clean(v)]
    return {"arrayValue": {"values": [{"stringValue": v} for v in cleaned]}} if cleaned else {"arrayValue": {}}


def parse_tags(raw):
    s = clean(raw)
    if not s:
        return []
    return [t.strip() for t in re.split(r"[,;|]", s) if t.strip()]


def split_name(nome, cognome):
    fn = clean(nome)
    ln = clean(cognome)
    if is_emptyish(fn):
        fn = ""
    if is_emptyish(ln):
        ln = ""

    if fn and not ln and " " in fn:
        parts = fn.split(" ")
        fn = parts[0]
        ln = " ".join(parts[1:]).strip()

    if not fn and ln:
        fn = ln
        ln = ""

    if not fn:
        fn = "Contatto"
    return fn, ln


def ensure_known_users(owner_token, team_id):
    results = []
    now_ts = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")

    for u in KNOWN_USERS:
        email = u["email"]
        password = u["password"]
        name = u["name"]

        uid = None
        state = ""

        st_login, d_login = http_json(
            "POST",
            f"https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key={API_KEY}",
            data={"email": email, "password": password, "returnSecureToken": True},
        )

        if st_login == 200:
            uid = d_login["localId"]
            state = "ok"
        else:
            st_signup, d_signup = signup(email, password)
            if st_signup == 200:
                uid = d_signup["localId"]
                state = "created"
            else:
                err = d_signup.get("error", {}).get("message", "")
                if err == "EMAIL_EXISTS":
                    state = "exists_password_unknown"
                    results.append({"email": email, "status": state})
                    continue
                state = f"error:{err}"
                results.append({"email": email, "status": state})
                continue

        user_fields = {
            "teamId": string_field(team_id),
            "displayName": string_field(name),
            "role": string_field(DEFAULT_ROLE),
            "email": string_field(email),
        }
        s1, _ = fs_patch(f"users/{uid}", owner_token, user_fields)

        member_fields = {
            "userId": string_field(uid),
            "email": string_field(email),
            "displayName": string_field(name),
            "role": string_field(DEFAULT_ROLE),
            "status": string_field("active"),
            "joinedAt": {"timestampValue": now_ts},
        }
        s2, _ = fs_patch(f"teams/{team_id}/members/{uid}", owner_token, member_fields)

        if s1 >= 300 or s2 >= 300:
            state = f"partial_error users:{s1} members:{s2}"
        results.append({"email": email, "uid": uid, "status": state})

    return results


def load_sheet_contacts(path):
    wb = load_workbook(path, read_only=True, data_only=True)
    ws = wb["Contacts"]
    rows = ws.iter_rows(values_only=True)
    header = [clean(h) for h in next(rows)]
    idx = {h: i for i, h in enumerate(header)}
    return idx, list(rows)


def main():
    print(f"Contacts file: {CONTACTS_FILE}")
    owner_token, owner_uid = login(OWNER_EMAIL, OWNER_PASSWORD)
    print(f"Owner login OK uid={owner_uid}")

    s, profile = fs_get(f"users/{owner_uid}", owner_token)
    if s != 200:
        raise RuntimeError(f"Impossibile leggere profilo owner status={s}")
    team_id = clean(fs_doc_to_plain(profile.get("fields", {})).get("teamId"))
    if not team_id:
        raise RuntimeError("teamId mancante")
    print(f"Owner teamId={team_id}")

    user_sync = ensure_known_users(owner_token, team_id)
    print("Known users sync:")
    for r in user_sync:
        print(" -", r)

    # Companies map by normalized name
    s_cmp, payload_cmp = fs_get(f"users/{owner_uid}/companies", owner_token, params={"pageSize": 3000})
    if s_cmp != 200:
        raise RuntimeError(f"Impossibile leggere companies status={s_cmp}")
    company_by_norm = {}
    for d in payload_cmp.get("documents", []) or []:
        doc_path = d.get("name", "")
        cid = doc_path.split("/")[-1]
        plain = fs_doc_to_plain(d.get("fields", {}))
        n = normalize_name(plain.get("name", ""))
        if n:
            company_by_norm[n] = cid

    idx, rows = load_sheet_contacts(CONTACTS_FILE)

    # Existing contacts for create/update stats
    s_cc, p_cc = fs_get(f"users/{owner_uid}/crmContacts", owner_token, params={"pageSize": 5000})
    existing_crm_ids = set()
    if s_cc == 200:
        for d in p_cc.get("documents", []) or []:
            existing_crm_ids.add(d.get("name", "").split("/")[-1])

    s_wc, p_wc = fs_get(f"users/{owner_uid}/companyContacts", owner_token, params={"pageSize": 5000})
    existing_workspace_ids = set()
    if s_wc == 200:
        for d in p_wc.get("documents", []) or []:
            existing_workspace_ids.add(d.get("name", "").split("/")[-1])

    created_crm = 0
    updated_crm = 0
    created_ws = 0
    updated_ws = 0
    skipped = 0

    for r in rows:
        nome = r[idx["Nome"]] if "Nome" in idx else None
        cognome = r[idx["Cognome"]] if "Cognome" in idx else None
        email = clean(r[idx["Indirizzo e-mail"]]) if "Indirizzo e-mail" in idx else ""
        telefono = clean(r[idx["Telefono"]]) if "Telefono" in idx else ""
        cellulare = clean(r[idx["Cellulare"]]) if "Cellulare" in idx else ""
        company_name = clean(r[idx["Società"]]) if "Società" in idx else ""

        first_name, last_name = split_name(nome, cognome)

        if not clean(first_name) and not clean(last_name) and not email:
            skipped += 1
            continue

        # Contact id (stable)
        tl_id = clean(r[idx["Teamleader ID"]]) if "Teamleader ID" in idx else ""
        if tl_id:
            contact_id = f"cnt-tl-{tl_id}"
        else:
            key = f"{first_name}|{last_name}|{email}|{company_name}".lower()
            contact_id = "cnt-auto-" + hashlib.sha1(key.encode("utf-8")).hexdigest()[:12]

        role = clean(r[idx["Funzione"]]) if "Funzione" in idx else ""
        if not role and "Sotto-funzione" in idx:
            role = clean(r[idx["Sotto-funzione"]])

        tags = parse_tags(r[idx["Tag"]]) if "Tag" in idx else []

        company_id = None
        if company_name:
            company_id = company_by_norm.get(normalize_name(company_name))

        phone = telefono or cellulare

        created_at = r[idx["Data aggiunta"]] if "Data aggiunta" in idx else None
        updated_at = r[idx["Ultime modifiche"]] if "Ultime modifiche" in idx else None

        notes_parts = []
        source = clean(r[idx["Fonte"]]) if "Fonte" in idx else ""
        if source:
            notes_parts.append(f"Fonte: {source}")
        cf = clean(r[idx["Codice Fiscale"]]) if "Codice Fiscale" in idx else ""
        if cf:
            notes_parts.append(f"CF: {cf}")
        notes = " | ".join(notes_parts)

        # CRM contacts (primary contact section)
        crm_fields = {
            "firstName": string_field(first_name),
            "lastName": string_field(last_name),
            "email": string_field(email),
            "phone": string_field(phone),
            "role": string_field(role),
            "tags": array_string_field(tags),
            "notes": string_field(notes),
            "createdAt": timestamp_field(created_at if isinstance(created_at, datetime) else datetime.now(timezone.utc)),
            "updatedAt": timestamp_field(updated_at if isinstance(updated_at, datetime) else datetime.now(timezone.utc)),
        }
        if company_id:
            crm_fields["companyId"] = string_field(company_id)

        s_upd, _ = fs_patch(f"users/{owner_uid}/crmContacts/{contact_id}", owner_token, crm_fields)
        if s_upd >= 300:
            skipped += 1
            continue
        if contact_id in existing_crm_ids:
            updated_crm += 1
        else:
            created_crm += 1
            existing_crm_ids.add(contact_id)

        # Workspace companyContacts (for legacy/summary counters)
        if company_id:
            ws_fields = {
                "companyId": string_field(company_id),
                "name": string_field((first_name + " " + last_name).strip()),
                "email": string_field(email),
                "phone": string_field(phone),
                "role": string_field(role),
            }
            s_ws, _ = fs_patch(f"users/{owner_uid}/companyContacts/{contact_id}", owner_token, ws_fields)
            if s_ws < 300:
                if contact_id in existing_workspace_ids:
                    updated_ws += 1
                else:
                    created_ws += 1
                    existing_workspace_ids.add(contact_id)

    print("\nImport contatti completato")
    print(json.dumps({
        "ownerUid": owner_uid,
        "teamId": team_id,
        "crmContacts": {"created": created_crm, "updated": updated_crm},
        "companyContacts": {"created": created_ws, "updated": updated_ws},
        "skipped": skipped,
        "usersSync": user_sync,
        "note": "Riccardo gestito con password Milanista99.",
    }, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
