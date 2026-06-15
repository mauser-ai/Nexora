#!/usr/bin/env python3
import hashlib
import json
import re
import unicodedata
from collections import defaultdict
from datetime import datetime
from urllib import parse, request, error

from openpyxl import load_workbook

PROJECT_ID = "mbworkflow-8b9f6"
API_KEY = "AIzaSyClZrKGod5wEMJwFD__ZeZglbid1ywyO_M"

OWNER_EMAIL = "claudia.gottardello@gweb.agency"
OWNER_PASSWORD = "Gweb123450"

PROJECTS_FILE = "/Users/riccardosacchetto/Downloads/Projects-2026-04-24-16-29-33.xlsx"
PHASES_FILE = "/Users/riccardosacchetto/Downloads/Fasi_Progetti.xlsx"


def http_json(method, url, data=None, headers=None, params=None):
    if params:
        q = parse.urlencode(params, doseq=True)
        url = f"{url}?{q}"

    h = {"Content-Type": "application/json"}
    if headers:
        h.update(headers)

    body = None
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
    if isinstance(v, datetime):
        return v.isoformat()
    if isinstance(v, (int, float)):
        if isinstance(v, float) and v.is_integer():
            return str(int(v))
        return str(v)
    return re.sub(r"\s+", " ", str(v).strip().strip('"').strip("'"))


def norm(s):
    s = clean(s).lower()
    s = unicodedata.normalize("NFKD", s)
    s = "".join(ch for ch in s if not unicodedata.combining(ch))
    s = s.replace("s.r.l.", "srl").replace("s.r.l", "srl")
    s = s.replace("s.p.a.", "spa").replace("s.p.a", "spa")
    s = re.sub(r"[^a-z0-9 ]+", " ", s)
    return re.sub(r"\s+", " ", s).strip()


def fs_string(v):
    return {"stringValue": clean(v)}


def fs_int(v):
    return {"integerValue": int(v)}


def map_status(raw_status):
    s = norm(raw_status)
    if s in {"attivi", "in attesa", "active"}:
        return "active"
    if s in {"fatto", "annullato", "archived", "chiuso"}:
        return "archived"
    return "active"


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
        else:
            out[k] = ""
    return out


def read_sheet(path, preferred):
    wb = load_workbook(path, read_only=True, data_only=True)
    sheet = preferred if preferred in wb.sheetnames else wb.sheetnames[0]
    ws = wb[sheet]
    rows = ws.iter_rows(values_only=True)
    header = [clean(h) for h in next(rows)]
    idx = {h: i for i, h in enumerate(header)}
    return idx, list(rows), sheet


def project_id_from_number_or_name(project_nr, name):
    nr = clean(project_nr)
    if nr:
        safe = re.sub(r"[^a-zA-Z0-9_-]+", "-", nr).strip("-").lower()
        if safe:
            return f"prj-tl-{safe}"
    key = norm(name)
    h = hashlib.sha1(key.encode("utf-8")).hexdigest()[:12]
    return f"prj-auto-{h}"


def phase_id(project_id, phase_name):
    key = f"{project_id}|{norm(phase_name)}"
    h = hashlib.sha1(key.encode("utf-8")).hexdigest()[:12]
    return f"phs-{h}"


def main():
    print(f"Projects file: {PROJECTS_FILE}")
    print(f"Phases file: {PHASES_FILE}")

    token, owner_uid = login(OWNER_EMAIL, OWNER_PASSWORD)
    print(f"Owner login OK uid={owner_uid}")

    st_u, udoc = fs_get(f"users/{owner_uid}", token)
    if st_u != 200:
        raise RuntimeError(f"Impossibile leggere owner profile status={st_u}")
    team_id = clean(fs_doc_to_plain(udoc.get("fields", {})).get("teamId"))
    if not team_id:
        raise RuntimeError("teamId mancante su owner")
    print(f"Owner teamId={team_id}")

    # Company lookup
    st_c, cpay = fs_get(f"users/{owner_uid}/companies", token, params={"pageSize": 5000})
    if st_c != 200:
        raise RuntimeError(f"Impossibile leggere companies status={st_c}")
    company_by_norm = {}
    for d in cpay.get("documents", []) or []:
        cid = d.get("name", "").split("/")[-1]
        plain = fs_doc_to_plain(d.get("fields", {}))
        n = norm(plain.get("name", ""))
        if n:
            company_by_norm[n] = cid

    # Team members lookup for phase assignedUserId
    st_m, mpay = fs_get(f"teams/{team_id}/members", token, params={"pageSize": 500})
    member_by_name = {}
    if st_m == 200:
        for d in mpay.get("documents", []) or []:
            plain = fs_doc_to_plain(d.get("fields", {}))
            uname = clean(plain.get("displayName", ""))
            uid = clean(plain.get("userId", ""))
            if uname and uid:
                member_by_name[norm(uname)] = uid

    # Existing sets for counters
    st_ep, epay = fs_get(f"users/{owner_uid}/projects", token, params={"pageSize": 5000})
    existing_projects = set()
    if st_ep == 200:
        for d in epay.get("documents", []) or []:
            existing_projects.add(d.get("name", "").split("/")[-1])

    st_eph, ephay = fs_get(f"users/{owner_uid}/phases", token, params={"pageSize": 10000})
    existing_phases = set()
    if st_eph == 200:
        for d in ephay.get("documents", []) or []:
            existing_phases.add(d.get("name", "").split("/")[-1])

    pidx, prows, psheet = read_sheet(PROJECTS_FILE, "Projects")
    fidx, frows, fsheet = read_sheet(PHASES_FILE, "Fase_Scaduto")
    print(f"Using sheets: projects={psheet}, fasi={fsheet}")

    # Aggregate projects by project number/name
    projects = {}
    project_key_to_id = {}

    for r in prows:
        pname = clean(r[pidx.get("Nome", -1)]) if "Nome" in pidx else ""
        pnr = clean(r[pidx.get("Progetto nr", -1)]) if "Progetto nr" in pidx else ""
        cname = clean(r[pidx.get("Cliente", -1)]) if "Cliente" in pidx else ""
        status_raw = clean(r[pidx.get("Stato", -1)]) if "Stato" in pidx else ""

        if not pname:
            continue

        pid = project_id_from_number_or_name(pnr, pname)
        key = pnr if pnr else norm(pname)
        project_key_to_id[key] = pid

        company_id = company_by_norm.get(norm(cname), "") if cname else ""
        if not company_id:
            # fallback deterministic placeholder to preserve relation non-empty
            company_id = "cmp-auto-orfani"

        rec = projects.get(pid, {
            "id": pid,
            "companyId": company_id,
            "name": pname,
            "code": pnr,
            "status": map_status(status_raw),
        })

        # Fill blanks if present
        if not rec.get("companyId") and company_id:
            rec["companyId"] = company_id
        if not rec.get("code") and pnr:
            rec["code"] = pnr
        if rec.get("status") != "active" and map_status(status_raw) == "active":
            rec["status"] = "active"

        projects[pid] = rec

    # Collect phases from dedicated phases sheet + fallback from Projects column "Fase"
    phases_by_project = defaultdict(dict)

    for r in frows:
        pname = clean(r[fidx.get("Progetto", -1)]) if "Progetto" in fidx else ""
        pnr = clean(r[fidx.get("Progetto numero", -1)]) if "Progetto numero" in fidx else ""
        phname = clean(r[fidx.get("Fase", -1)]) if "Fase" in fidx else ""
        assignee = clean(r[fidx.get("Assegnato a", -1)]) if "Assegnato a" in fidx else ""

        if not phname:
            continue

        key = pnr if pnr else norm(pname)
        pid = project_key_to_id.get(key)
        if not pid:
            # project seen only in phases sheet: create minimal project
            pid = project_id_from_number_or_name(pnr, pname or f"Progetto {pnr}" if pnr else "Progetto")
            project_key_to_id[key] = pid
            if pid not in projects:
                projects[pid] = {
                    "id": pid,
                    "companyId": "cmp-auto-orfani",
                    "name": pname or (f"Progetto {pnr}" if pnr else "Progetto senza nome"),
                    "code": pnr,
                    "status": "active",
                }

        ph_norm = norm(phname)
        if not ph_norm:
            continue

        assigned_uid = member_by_name.get(norm(assignee)) if assignee else None
        phases_by_project[pid][ph_norm] = {
            "name": phname,
            "assignedUserId": assigned_uid,
        }

    for r in prows:
        pname = clean(r[pidx.get("Nome", -1)]) if "Nome" in pidx else ""
        pnr = clean(r[pidx.get("Progetto nr", -1)]) if "Progetto nr" in pidx else ""
        phname = clean(r[pidx.get("Fase", -1)]) if "Fase" in pidx else ""
        assignee = clean(r[pidx.get("Assegnato a", -1)]) if "Assegnato a" in pidx else ""
        if not pname or not phname:
            continue
        key = pnr if pnr else norm(pname)
        pid = project_key_to_id.get(key)
        if not pid:
            continue
        ph_norm = norm(phname)
        if not ph_norm:
            continue
        if ph_norm not in phases_by_project[pid]:
            phases_by_project[pid][ph_norm] = {
                "name": phname,
                "assignedUserId": member_by_name.get(norm(assignee)) if assignee else None,
            }

    # Upsert projects
    created_projects = 0
    updated_projects = 0
    for pid, p in projects.items():
        fields = {
            "companyId": fs_string(p["companyId"]),
            "name": fs_string(p["name"]),
            "code": fs_string(p["code"]),
            "status": fs_string(p["status"]),
        }
        s, _ = fs_patch(f"users/{owner_uid}/projects/{pid}", token, fields)
        if s >= 300:
            continue
        if pid in existing_projects:
            updated_projects += 1
        else:
            created_projects += 1
            existing_projects.add(pid)

    # Upsert phases
    created_phases = 0
    updated_phases = 0
    skipped_phases = 0
    for pid, phmap in phases_by_project.items():
        ordered = sorted(phmap.values(), key=lambda x: norm(x["name"]))
        for i, ph in enumerate(ordered, start=1):
            phid = phase_id(pid, ph["name"])
            fields = {
                "projectId": fs_string(pid),
                "name": fs_string(ph["name"]),
                "order": fs_int(i),
            }
            if ph.get("assignedUserId"):
                fields["assignedUserId"] = fs_string(ph["assignedUserId"])
            s, _ = fs_patch(f"users/{owner_uid}/phases/{phid}", token, fields)
            if s >= 300:
                skipped_phases += 1
                continue
            if phid in existing_phases:
                updated_phases += 1
            else:
                created_phases += 1
                existing_phases.add(phid)

    print("\nImport progetti/fasi completato")
    print(json.dumps({
        "ownerUid": owner_uid,
        "teamId": team_id,
        "projects": {
            "created": created_projects,
            "updated": updated_projects,
            "totalProcessed": len(projects),
        },
        "phases": {
            "created": created_phases,
            "updated": updated_phases,
            "skipped": skipped_phases,
            "totalProcessed": created_phases + updated_phases + skipped_phases,
        },
        "notes": [
            "Join principale fasi/progetti su Progetto nr/Progetto numero.",
            "Status mappato su active/archived.",
            "Progetti senza match azienda assegnati a cmp-auto-orfani (se presenti).",
        ],
    }, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
