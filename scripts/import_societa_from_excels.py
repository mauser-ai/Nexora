#!/usr/bin/env python3
import hashlib
import json
import re
from collections import defaultdict
from datetime import datetime, timezone
from urllib import parse, request, error

from openpyxl import load_workbook

PROJECT_ID = "mbworkflow-8b9f6"
API_KEY = "AIzaSyClZrKGod5wEMJwFD__ZeZglbid1ywyO_M"

OWNER_EMAIL = "claudia.gottardello@gweb.agency"
OWNER_PASSWORD = "Gweb123450"

DEALS_FILE = "/Users/riccardosacchetto/Downloads/Deals.xlsx"
PROJECTS_FILE = "/Users/riccardosacchetto/Downloads/Projects-2026-04-24-16-29-33.xlsx"
CONTACTS_FILE = "/Users/riccardosacchetto/Downloads/Contacts-2026-04-24-16-28-04.xlsx"
COMPANIES_FILE = "/Users/riccardosacchetto/Downloads/Companies-2026-04-24-16-25-37.xlsx"
COMPANIES_LOCK_FILE = "/Users/riccardosacchetto/Downloads/~$Companies-2026-04-24-16-25-37.xlsx"

KNOWN_USERS = [
    ("Claudia Gottardello", "claudia.gottardello@gweb.agency"),
    ("Riccardo Sacchetto", "sacchetto.riccardo@gmail.com"),
    ("Jonathan Scarafile", "jonathan.scarafile@gweb.agency"),
    ("Nicolo Schenato", "nicolo.schenato@gweb.agency"),
    ("Giuseppe Grasso", "giuseppe.grasso@gweb.agency"),
]
DEFAULT_PASSWORD = "Gweb123450"
DEFAULT_ROLE = "Default"


def http_json(method, url, data=None, headers=None, params=None):
    if params:
        q = parse.urlencode(params, doseq=True)
        url = f"{url}?{q}"
    body = None
    h = {"Content-Type": "application/json"}
    if headers:
        h.update(headers)
    if data is not None:
        body = json.dumps(data).encode("utf-8")
    req = request.Request(url=url, data=body, headers=h, method=method)
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
    s = s.replace("  ", " ")
    s = re.sub(r"[^a-z0-9 ]+", "", s)
    return re.sub(r"\s+", " ", s).strip()


def is_valid_company_name(name):
    s = clean(name)
    if not s:
        return False
    bad = {"-", "n/a", "na", "nessuno", "none", "null", "nd", "n.d."}
    if s.lower() in bad:
        return False
    if "@" in s:
        return False
    if len(s) < 2:
        return False
    return True


def login(email, password):
    status, data = http_json(
        "POST",
        f"https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key={API_KEY}",
        data={"email": email, "password": password, "returnSecureToken": True},
    )
    if status != 200:
        raise RuntimeError(f"Login fallito per {email}: {data}")
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


def fs_patch(path, token, fields, update_mask=None):
    url = f"https://firestore.googleapis.com/v1/projects/{PROJECT_ID}/databases/(default)/documents/{path}"
    params = []
    if update_mask:
        for f in update_mask:
            params.append(("updateMask.fieldPaths", f))
    return http_json(
        "PATCH",
        url,
        data={"fields": fields},
        headers={"Authorization": f"Bearer {token}"},
        params=params,
    )


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
            out[k] = "true" if v["booleanValue"] else "false"
        elif "timestampValue" in v:
            out[k] = v["timestampValue"]
        elif "nullValue" in v:
            out[k] = ""
        elif "mapValue" in v:
            out[k] = "[map]"
        elif "arrayValue" in v:
            out[k] = "[array]"
        else:
            out[k] = ""
    return out


def to_fs_string_map(data):
    fields = {}
    for k, v in data.items():
        if v is None:
            continue
        fields[k] = {"stringValue": clean(v)}
    return fields


def stable_company_id(name):
    base = normalize_name(name)
    h = hashlib.sha1(base.encode("utf-8")).hexdigest()[:10]
    return f"cmp-auto-{h}"


def first_non_empty(current, candidate):
    return current if clean(current) else clean(candidate)


def extract_rows(path, sheet_name):
    wb = load_workbook(path, read_only=True, data_only=True)
    ws = wb[sheet_name]
    rows = ws.iter_rows(values_only=True)
    header = [clean(h) for h in next(rows)]
    idx = {h: i for i, h in enumerate(header)}
    data = list(rows)
    return idx, data


def aggregate_companies():
    companies = defaultdict(lambda: {
        "name": "",
        "email": "",
        "phone": "",
        "website": "",
        "vatNumber": "",
        "taxCode": "",
        "pec": "",
        "sdiCode": "",
        "addressLine": "",
        "city": "",
        "postalCode": "",
        "country": "Italia",
        "contactPerson": "",
        "notes": "Import automatico Excel (Deals/Projects/Contacts) del 2026-04-24",
    })

    # Primary source: Companies export
    xidx, xrows = extract_rows(COMPANIES_FILE, "Companies")
    for r in xrows:
        cname = clean(r[xidx.get("Nome", -1)]) if "Nome" in xidx else ""
        if not is_valid_company_name(cname):
            continue
        nk = normalize_name(cname)
        c = companies[nk]
        c["name"] = clean(cname)

        street = clean(r[xidx.get("Via", -1)]) if "Via" in xidx else ""
        num = clean(r[xidx.get("Numero", -1)]) if "Numero" in xidx else ""
        address_line = f"{street} {num}".strip()

        c["addressLine"] = first_non_empty(c["addressLine"], address_line)
        c["city"] = first_non_empty(c["city"], clean(r[xidx.get("Città", -1)]) if "Città" in xidx else "")
        c["postalCode"] = first_non_empty(c["postalCode"], clean(r[xidx.get("Codice postale", -1)]) if "Codice postale" in xidx else "")
        c["country"] = first_non_empty(c["country"], clean(r[xidx.get("Paese", -1)]) if "Paese" in xidx else "") or "Italia"
        c["email"] = first_non_empty(c["email"], clean(r[xidx.get("Indirizzo e-mail", -1)]) if "Indirizzo e-mail" in xidx else "")
        c["phone"] = first_non_empty(c["phone"], clean(r[xidx.get("Telefono", -1)]) if "Telefono" in xidx else "")
        c["website"] = first_non_empty(c["website"], clean(r[xidx.get("Sito web", -1)]) if "Sito web" in xidx else "")
        c["vatNumber"] = first_non_empty(c["vatNumber"], clean(r[xidx.get("Numero Partita IVA", -1)]) if "Numero Partita IVA" in xidx else "")
        c["taxCode"] = first_non_empty(c["taxCode"], clean(r[xidx.get("Numero di identificazione nazionale Nº", -1)]) if "Numero di identificazione nazionale Nº" in xidx else "")
        c["pec"] = first_non_empty(c["pec"], clean(r[xidx.get("PEC", -1)]) if "PEC" in xidx else "")
        c["contactPerson"] = first_non_empty(c["contactPerson"], clean(r[xidx.get("Gestore account", -1)]) if "Gestore account" in xidx else "")

    didx, drows = extract_rows(DEALS_FILE, "Sales")
    for r in drows:
        cname = clean(r[didx.get("Cliente", -1)]) if "Cliente" in didx else ""
        if not is_valid_company_name(cname):
            continue
        nk = normalize_name(cname)
        c = companies[nk]
        c["name"] = clean(cname)

        street = clean(r[didx.get("Cliente: Via", -1)]) if "Cliente: Via" in didx else ""
        num = clean(r[didx.get("Cliente: Numero", -1)]) if "Cliente: Numero" in didx else ""
        address_line = f"{street} {num}".strip()

        c["addressLine"] = first_non_empty(c["addressLine"], address_line)
        c["city"] = first_non_empty(c["city"], clean(r[didx.get("Cliente: Città", -1)]) if "Cliente: Città" in didx else "")
        c["postalCode"] = first_non_empty(c["postalCode"], clean(r[didx.get("Cliente: Codice postale", -1)]) if "Cliente: Codice postale" in didx else "")
        c["country"] = first_non_empty(c["country"], clean(r[didx.get("Cliente: Paese", -1)]) if "Cliente: Paese" in didx else "") or "Italia"
        c["email"] = first_non_empty(c["email"], clean(r[didx.get("Cliente: E-mail", -1)]) if "Cliente: E-mail" in didx else "")
        c["phone"] = first_non_empty(c["phone"], clean(r[didx.get("Cliente: Telefono", -1)]) if "Cliente: Telefono" in didx else "")
        if not clean(c["phone"]):
            c["phone"] = first_non_empty(c["phone"], clean(r[didx.get("Cliente: Cellulare", -1)]) if "Cliente: Cellulare" in didx else "")
        c["contactPerson"] = first_non_empty(c["contactPerson"], clean(r[didx.get("Contatto", -1)]) if "Contatto" in didx else "")

    pidx, prows = extract_rows(PROJECTS_FILE, "Projects")
    for r in prows:
        cname = clean(r[pidx.get("Cliente", -1)]) if "Cliente" in pidx else ""
        if not is_valid_company_name(cname):
            continue
        nk = normalize_name(cname)
        c = companies[nk]
        c["name"] = clean(cname)
        c["contactPerson"] = first_non_empty(c["contactPerson"], clean(r[pidx.get("Responsabile progetto", -1)]) if "Responsabile progetto" in pidx else "")

    cidx, crows = extract_rows(CONTACTS_FILE, "Contacts")
    for r in crows:
        cname = clean(r[cidx.get("Società", -1)]) if "Società" in cidx else ""
        if not is_valid_company_name(cname):
            continue
        nk = normalize_name(cname)
        c = companies[nk]
        c["name"] = clean(cname)

        street = clean(r[cidx.get("Via", -1)]) if "Via" in cidx else ""
        num = clean(r[cidx.get("Numero", -1)]) if "Numero" in cidx else ""
        address_line = f"{street} {num}".strip()

        c["addressLine"] = first_non_empty(c["addressLine"], address_line)
        c["city"] = first_non_empty(c["city"], clean(r[cidx.get("Città", -1)]) if "Città" in cidx else "")
        c["postalCode"] = first_non_empty(c["postalCode"], clean(r[cidx.get("Codice postale", -1)]) if "Codice postale" in cidx else "")
        c["country"] = first_non_empty(c["country"], clean(r[cidx.get("Paese", -1)]) if "Paese" in cidx else "") or "Italia"
        c["email"] = first_non_empty(c["email"], clean(r[cidx.get("Indirizzo e-mail", -1)]) if "Indirizzo e-mail" in cidx else "")
        c["phone"] = first_non_empty(c["phone"], clean(r[cidx.get("Telefono", -1)]) if "Telefono" in cidx else "")
        if not clean(c["phone"]):
            c["phone"] = first_non_empty(c["phone"], clean(r[cidx.get("Cellulare", -1)]) if "Cellulare" in cidx else "")
        c["website"] = first_non_empty(c["website"], clean(r[cidx.get("Sito web", -1)]) if "Sito web" in cidx else "")
        c["vatNumber"] = first_non_empty(c["vatNumber"], clean(r[cidx.get("Numero di Partita IVA del contatto", -1)]) if "Numero di Partita IVA del contatto" in cidx else "")
        c["taxCode"] = first_non_empty(c["taxCode"], clean(r[cidx.get("Codice Fiscale", -1)]) if "Codice Fiscale" in cidx else "")

        first_name = clean(r[cidx.get("Nome", -1)]) if "Nome" in cidx else ""
        last_name = clean(r[cidx.get("Cognome", -1)]) if "Cognome" in cidx else ""
        person = f"{first_name} {last_name}".strip()
        c["contactPerson"] = first_non_empty(c["contactPerson"], person)

    return companies


def ensure_known_users(owner_token, team_id):
    results = []
    now_ts = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
    for display_name, email in KNOWN_USERS:
        uid = None
        created = False
        login_ok = False

        sign_in_status, sign_in_data = http_json(
            "POST",
            f"https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key={API_KEY}",
            data={"email": email, "password": DEFAULT_PASSWORD, "returnSecureToken": True},
        )

        if sign_in_status == 200:
            uid = sign_in_data["localId"]
            login_ok = True
        else:
            code, body = signup(email, DEFAULT_PASSWORD)
            if code == 200:
                uid = body["localId"]
                created = True
            else:
                err = body.get("error", {}).get("message", "")
                if err == "EMAIL_EXISTS":
                    results.append({"email": email, "status": "exists_password_unknown"})
                    continue
                results.append({"email": email, "status": f"error:{err}"})
                continue

        user_fields = to_fs_string_map({
            "teamId": team_id,
            "displayName": display_name,
            "role": DEFAULT_ROLE,
            "email": email,
        })
        s1, _ = fs_patch(f"users/{uid}", owner_token, user_fields)

        member_fields = {
            "userId": {"stringValue": uid},
            "email": {"stringValue": email},
            "displayName": {"stringValue": display_name},
            "role": {"stringValue": DEFAULT_ROLE},
            "status": {"stringValue": "active"},
            "joinedAt": {"timestampValue": now_ts},
        }
        s2, _ = fs_patch(f"teams/{team_id}/members/{uid}", owner_token, member_fields)

        state = "created" if created else ("ok" if login_ok else "updated")
        if s1 >= 300 or s2 >= 300:
            state = f"partial_error users:{s1} members:{s2}"
        results.append({"email": email, "uid": uid, "status": state})
    return results


def main():
    print(f"Deals file: {DEALS_FILE}")
    print(f"Projects file: {PROJECTS_FILE}")
    print(f"Contacts file: {CONTACTS_FILE}")
    print(f"Companies file: {COMPANIES_FILE}")
    print(f"Companies lock file (non importabile): {COMPANIES_LOCK_FILE}")

    owner_token, owner_uid = login(OWNER_EMAIL, OWNER_PASSWORD)
    print(f"Owner login OK uid={owner_uid}")

    s, profile = fs_get(f"users/{owner_uid}", owner_token)
    if s != 200:
        raise RuntimeError(f"Impossibile leggere profilo owner (status={s}): {profile}")
    profile_plain = fs_doc_to_plain(profile.get("fields", {}))
    team_id = clean(profile_plain.get("teamId"))
    if not team_id:
        raise RuntimeError("teamId mancante sul profilo owner, impossibile collegare i membri team.")
    print(f"Owner teamId={team_id}")

    user_results = ensure_known_users(owner_token, team_id)
    print("Known users sync:")
    for r in user_results:
        print(" -", r)

    aggregated = aggregate_companies()
    print(f"Aziende aggregate dai file disponibili: {len(aggregated)}")

    status, existing_payload = fs_get(f"users/{owner_uid}/companies", owner_token, params={"pageSize": 2000})
    if status != 200:
        raise RuntimeError(f"Impossibile leggere companies esistenti (status={status}): {existing_payload}")

    existing_docs = existing_payload.get("documents", [])
    by_norm = {}
    existing_count = 0
    for d in existing_docs:
        existing_count += 1
        path = d.get("name", "")
        doc_id = path.split("/")[-1]
        plain = fs_doc_to_plain(d.get("fields", {}))
        n = normalize_name(plain.get("name", ""))
        if n:
            by_norm[n] = (doc_id, plain)
    print(f"Companies esistenti: {existing_count}")

    created = 0
    updated = 0
    skipped = 0

    for nkey, data in sorted(aggregated.items(), key=lambda kv: kv[1]["name"].lower()):
        if not is_valid_company_name(data["name"]):
            skipped += 1
            continue

        if nkey in by_norm:
            doc_id, current = by_norm[nkey]
            merged = dict(current)
            for k, v in data.items():
                if not clean(merged.get(k)) and clean(v):
                    merged[k] = clean(v)
            for k in ["name", "vatNumber", "taxCode", "pec", "sdiCode", "email", "phone", "website", "addressLine", "city", "postalCode", "country", "contactPerson", "notes"]:
                merged[k] = clean(merged.get(k))

            s, _ = fs_patch(f"users/{owner_uid}/companies/{doc_id}", owner_token, to_fs_string_map(merged))
            if s >= 300:
                print(f"[WARN] update fail {doc_id} {data['name']} status={s}")
                continue
            updated += 1
        else:
            doc_id = stable_company_id(data["name"])
            full = {
                "name": clean(data.get("name")),
                "vatNumber": clean(data.get("vatNumber")),
                "taxCode": clean(data.get("taxCode")),
                "pec": clean(data.get("pec")),
                "sdiCode": clean(data.get("sdiCode")),
                "email": clean(data.get("email")),
                "phone": clean(data.get("phone")),
                "website": clean(data.get("website")),
                "addressLine": clean(data.get("addressLine")),
                "city": clean(data.get("city")),
                "postalCode": clean(data.get("postalCode")),
                "country": clean(data.get("country")) or "Italia",
                "contactPerson": clean(data.get("contactPerson")),
                "notes": clean(data.get("notes")),
            }
            s, _ = fs_patch(f"users/{owner_uid}/companies/{doc_id}", owner_token, to_fs_string_map(full))
            if s >= 300:
                print(f"[WARN] create fail {doc_id} {data['name']} status={s}")
                continue
            created += 1

    print("\nImport società completato")
    print(json.dumps({
        "ownerUid": owner_uid,
        "teamId": team_id,
        "aggregatedCompanies": len(aggregated),
        "existingCompaniesBefore": existing_count,
        "created": created,
        "updated": updated,
        "skipped": skipped,
        "usersSync": user_results,
        "companiesFileNote": "Import eseguito usando il file Companies reale + merge con Deals/Projects/Contacts.",
    }, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
