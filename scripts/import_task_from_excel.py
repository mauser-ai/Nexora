#!/usr/bin/env python3
import hashlib
import json
import re
import time
import unicodedata
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from urllib import error, parse, request

from openpyxl import load_workbook

PROJECT_ID = "mbworkflow-8b9f6"
API_KEY = "AIzaSyClZrKGod5wEMJwFD__ZeZglbid1ywyO_M"
OWNER_EMAIL = "claudia.gottardello@gweb.agency"
OWNER_PASSWORD = "Gweb123450"
TASK_FILE = "/Users/riccardosacchetto/Downloads/Task-2026-04-24-17-04-54.xlsx"
DEFAULT_ROLE = "Default"

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
            with request.urlopen(req, timeout=45) as resp:
                raw = resp.read().decode("utf-8")
                return resp.status, (json.loads(raw) if raw else {})
        except error.HTTPError as e:
            raw = e.read().decode("utf-8") if e.fp else ""
            try:
                parsed = json.loads(raw) if raw else {}
            except Exception:
                parsed = {"raw": raw}
            if e.code in (429, 500, 502, 503, 504) and attempt < retries - 1:
                time.sleep(0.5 * (2 ** attempt))
                continue
            return e.code, parsed
        except Exception as e:
            if attempt < retries - 1:
                time.sleep(0.5 * (2 ** attempt))
                continue
            return 599, {"error": str(e)}


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


def fs_bool(v):
    return {"booleanValue": bool(v)}


def fs_double(v):
    return {"doubleValue": float(v)}


def fs_int(v):
    return {"integerValue": int(v)}


def fs_ts(dt):
    if not isinstance(dt, datetime):
        dt = datetime.now(timezone.utc)
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    else:
        dt = dt.astimezone(timezone.utc)
    return {"timestampValue": dt.isoformat().replace("+00:00", "Z")}


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


def login(email, password):
    st, data = http_json(
        "POST",
        f"https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key={API_KEY}",
        data={"email": email, "password": password, "returnSecureToken": True},
    )
    if st != 200:
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


def fs_list_all(path, token, page_size=500):
    docs = []
    page_token = None
    while True:
        params = {"pageSize": page_size}
        if page_token:
            params["pageToken"] = page_token
        st, payload = fs_get(path, token, params=params)
        if st != 200:
            if st == 404:
                return docs
            raise RuntimeError(f"Errore lista {path}: status={st} payload={payload}")
        docs.extend(payload.get("documents", []) or [])
        page_token = payload.get("nextPageToken")
        if not page_token:
            return docs


def ensure_known_users(owner_token, team_id):
    resolved = {}
    now_ts = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
    for u in KNOWN_USERS:
        email = u["email"]
        password = u["password"]
        name = u["name"]

        uid = None
        st_login, d_login = http_json(
            "POST",
            f"https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key={API_KEY}",
            data={"email": email, "password": password, "returnSecureToken": True},
        )
        if st_login == 200:
            uid = d_login["localId"]
        else:
            st_signup, d_signup = signup(email, password)
            if st_signup == 200:
                uid = d_signup["localId"]
            elif d_signup.get("error", {}).get("message") == "EMAIL_EXISTS":
                continue
            else:
                continue

        fs_patch(f"users/{uid}", owner_token, {
            "teamId": fs_string(team_id),
            "displayName": fs_string(name),
            "role": fs_string(DEFAULT_ROLE),
            "email": fs_string(email),
        })
        fs_patch(f"teams/{team_id}/members/{uid}", owner_token, {
            "userId": fs_string(uid),
            "email": fs_string(email),
            "displayName": fs_string(name),
            "role": fs_string(DEFAULT_ROLE),
            "status": fs_string("active"),
            "joinedAt": {"timestampValue": now_ts},
        })
        resolved[norm(name)] = uid
    return resolved


def read_sheet(path):
    wb = load_workbook(path, read_only=True, data_only=True)
    ws = wb["Task"] if "Task" in wb.sheetnames else wb[wb.sheetnames[0]]
    rows = ws.iter_rows(values_only=True)
    header = [clean(h) for h in next(rows)]
    idx = {h: i for i, h in enumerate(header)}
    data = []
    row_no = 1
    for r in rows:
        row_no += 1
        data.append((row_no, r))
    return idx, data, ws.title


def get_value(row, idx, key):
    i = idx.get(key)
    if i is None or i < 0 or i >= len(row):
        return None
    return row[i]


def parse_dt(v):
    if isinstance(v, datetime):
        return v
    s = clean(v)
    if not s:
        return None
    for fmt in ("%Y-%m-%d", "%d/%m/%Y", "%Y-%m-%dT%H:%M:%S"):
        try:
            return datetime.strptime(s[:19], fmt)
        except Exception:
            pass
    return None


def parse_minutes(v):
    s = clean(v).replace(",", ".")
    if not s:
        return 0.0
    try:
        return float(s)
    except Exception:
        return 0.0


def map_status(raw_status, planned_flag, spent_h, est_h):
    s = norm(raw_status)
    pf = clean(planned_flag)
    if any(k in s for k in ["fatto", "chiuso", "completato", "closed", "done"]):
        return "done"
    if pf == "1" and spent_h <= 0:
        return "planned"
    if spent_h > 0:
        if est_h > 0 and spent_h >= est_h and pf == "0" and not s:
            return "done"
        return "inProgress"
    if s:
        return "inProgress"
    return "backlog"


def sanitize_id_piece(s):
    return re.sub(r"[^a-zA-Z0-9_-]+", "-", clean(s)).strip("-").lower()[:48]


def project_id_from_number_or_name(project_nr, name):
    nr = clean(project_nr)
    if nr:
        safe = sanitize_id_piece(nr)
        if safe:
            return f"prj-tl-{safe}"
    return f"prj-auto-{hashlib.sha1(norm(name).encode('utf-8')).hexdigest()[:12]}"


def phase_id(project_id, phase_name):
    key = f"{project_id}|{norm(phase_name)}"
    return f"phs-{hashlib.sha1(key.encode('utf-8')).hexdigest()[:12]}"


def task_id(row_no, old_id, title, project_nr, project_name, client, due, assignee):
    old = sanitize_id_piece(old_id)
    sig = "|".join([
        str(row_no), clean(old_id), norm(title), clean(project_nr), norm(project_name), norm(client), clean(due), norm(assignee)
    ])
    h = hashlib.sha1(sig.encode("utf-8")).hexdigest()[:12]
    return f"tsk-tl-{old}-{h}" if old else f"tsk-auto-{h}"


def main():
    print(f"Task file: {TASK_FILE}")
    token, owner_uid = login(OWNER_EMAIL, OWNER_PASSWORD)
    print(f"Owner login OK uid={owner_uid}")

    st_u, udoc = fs_get(f"users/{owner_uid}", token)
    if st_u != 200:
        raise RuntimeError(f"Impossibile leggere owner profile status={st_u}")
    team_id = clean(fs_doc_to_plain(udoc.get("fields", {})).get("teamId"))
    if not team_id:
        raise RuntimeError("teamId mancante su owner")
    print(f"Owner teamId={team_id}")

    known_user_ids = ensure_known_users(token, team_id)

    companies_docs = fs_list_all(f"users/{owner_uid}/companies", token)
    company_by_norm = {}
    company_ids = set()
    for d in companies_docs:
        cid = d.get("name", "").split("/")[-1]
        p = fs_doc_to_plain(d.get("fields", {}))
        company_ids.add(cid)
        n = norm(p.get("name", ""))
        if n:
            company_by_norm[n] = cid

    if "cmp-auto-orfani" not in company_ids:
        fs_patch(f"users/{owner_uid}/companies/cmp-auto-orfani", token, {
            "name": fs_string("Azienda non associata"),
            "status": fs_string("active"),
        })

    members_docs = fs_list_all(f"teams/{team_id}/members", token)
    member_by_name = {}
    for d in members_docs:
        p = fs_doc_to_plain(d.get("fields", {}))
        n = norm(p.get("displayName", ""))
        uid = clean(p.get("userId", ""))
        if n and uid:
            member_by_name[n] = uid
    member_by_name.update(known_user_ids)

    projects_docs = fs_list_all(f"users/{owner_uid}/projects", token)
    project_existing_ids = set()
    project_by_code = {}
    project_by_name = {}
    project_company = {}
    for d in projects_docs:
        pid = d.get("name", "").split("/")[-1]
        p = fs_doc_to_plain(d.get("fields", {}))
        project_existing_ids.add(pid)
        if clean(p.get("code", "")):
            project_by_code[clean(p.get("code"))] = pid
        if clean(p.get("name", "")):
            project_by_name[norm(p.get("name"))] = pid
        project_company[pid] = clean(p.get("companyId", ""))

    phases_docs = fs_list_all(f"users/{owner_uid}/phases", token)
    phase_existing_ids = set()
    phase_by_project_name = {}
    phase_order_max = {}
    for d in phases_docs:
        phid = d.get("name", "").split("/")[-1]
        p = fs_doc_to_plain(d.get("fields", {}))
        pid = clean(p.get("projectId", ""))
        pname = clean(p.get("name", ""))
        ord_raw = clean(p.get("order", "0"))
        ord_n = int(ord_raw) if ord_raw.isdigit() else 0
        phase_existing_ids.add(phid)
        if pid and pname:
            phase_by_project_name[(pid, norm(pname))] = phid
            phase_order_max[pid] = max(phase_order_max.get(pid, 0), ord_n)

    tasks_docs = fs_list_all(f"users/{owner_uid}/tasks", token)
    existing_task_ids = {d.get("name", "").split("/")[-1] for d in tasks_docs}
    print(f"Existing docs: companies={len(companies_docs)} projects={len(projects_docs)} phases={len(phases_docs)} tasks={len(tasks_docs)}")

    idx, rows, sheet_name = read_sheet(TASK_FILE)
    print(f"Using sheet: {sheet_name}, rows={len(rows)}")

    # Pre-pass: determine project refs required
    project_seed = {}
    task_rows = []
    for i, (row_no, row) in enumerate(rows, start=1):
        title = clean(get_value(row, idx, "Titolo"))
        if not title:
            continue
        project_nr = clean(get_value(row, idx, "Progetto nr"))
        project_name = clean(get_value(row, idx, "Progetto"))
        client = clean(get_value(row, idx, "Cliente"))

        key = project_nr if project_nr else f"name::{norm(project_name)}"
        task_rows.append((row_no, row))
        if key not in project_seed:
            project_seed[key] = {
                "project_nr": project_nr,
                "project_name": project_name,
                "client": client,
            }

        if i % 4000 == 0:
            print(f"Prep rows: {i}/{len(rows)}")

    # Ensure projects
    created_projects = 0
    updated_projects = 0
    project_id_by_key = {}

    for key, seed in project_seed.items():
        project_nr = seed["project_nr"]
        project_name = seed["project_name"]
        client = seed["client"]

        pid = ""
        if project_nr and project_nr in project_by_code:
            pid = project_by_code[project_nr]
        elif project_name and norm(project_name) in project_by_name:
            pid = project_by_name[norm(project_name)]
        else:
            pid = project_id_from_number_or_name(project_nr, project_name or "Progetto")
            company_id = company_by_norm.get(norm(client), "") if client else ""
            if not company_id:
                company_id = "cmp-auto-orfani"
            pname = project_name or (f"Progetto {project_nr}" if project_nr else "Progetto da task")
            st, payload = fs_patch(f"users/{owner_uid}/projects/{pid}", token, {
                "companyId": fs_string(company_id),
                "name": fs_string(pname),
                "code": fs_string(project_nr),
                "status": fs_string("active"),
            })
            if st >= 300:
                raise RuntimeError(f"Errore creazione progetto {pid}: status={st} payload={payload}")
            if pid in project_existing_ids:
                updated_projects += 1
            else:
                created_projects += 1
                project_existing_ids.add(pid)
            if project_nr:
                project_by_code[project_nr] = pid
            if project_name:
                project_by_name[norm(project_name)] = pid
            project_company[pid] = company_id

        project_id_by_key[key] = pid

    # Ensure phases and build task payloads
    created_phases = 0
    updated_phases = 0
    task_payloads = []

    for i, (row_no, row) in enumerate(task_rows, start=1):
        title = clean(get_value(row, idx, "Titolo"))
        project_nr = clean(get_value(row, idx, "Progetto nr"))
        project_name = clean(get_value(row, idx, "Progetto"))
        phase_name = clean(get_value(row, idx, "Fase")) or "Fase 0"
        assignee_name = clean(get_value(row, idx, "Assegnato a"))
        creator_name = clean(get_value(row, idx, "Creatore"))
        client = clean(get_value(row, idx, "Cliente"))
        old_id = clean(get_value(row, idx, "old_id"))

        key = project_nr if project_nr else f"name::{norm(project_name)}"
        pid = project_id_by_key.get(key)
        if not pid:
            continue

        company_id = company_by_norm.get(norm(client), "") if client else ""
        if not company_id:
            company_id = project_company.get(pid, "") or "cmp-auto-orfani"

        ph_key = (pid, norm(phase_name))
        phid = phase_by_project_name.get(ph_key, "")
        if not phid:
            phid = phase_id(pid, phase_name)
            order_n = phase_order_max.get(pid, 0) + 1
            phase_fields = {
                "projectId": fs_string(pid),
                "name": fs_string(phase_name),
                "order": fs_int(order_n),
            }
            ass_uid = member_by_name.get(norm(assignee_name), "") if assignee_name else ""
            if ass_uid:
                phase_fields["assignedUserId"] = fs_string(ass_uid)
            st, payload = fs_patch(f"users/{owner_uid}/phases/{phid}", token, phase_fields)
            if st >= 300:
                raise RuntimeError(f"Errore creazione fase {phid}: status={st} payload={payload}")
            if phid in phase_existing_ids:
                updated_phases += 1
            else:
                created_phases += 1
                phase_existing_ids.add(phid)
            phase_by_project_name[ph_key] = phid
            phase_order_max[pid] = order_n

        assignee_id = ""
        if assignee_name:
            assignee_id = member_by_name.get(norm(assignee_name), "")
        if not assignee_id and creator_name:
            assignee_id = member_by_name.get(norm(creator_name), "")
        if not assignee_id:
            assignee_id = owner_uid

        due_dt = parse_dt(get_value(row, idx, "Data di scadenza"))
        exec_dt = parse_dt(get_value(row, idx, "Data esecuzione"))
        added_dt = parse_dt(get_value(row, idx, "Data aggiunta"))
        deadline = due_dt or exec_dt or added_dt or datetime.now()
        start_date = added_dt or exec_dt or deadline

        est_h = round(parse_minutes(get_value(row, idx, "Durata (in minuti)")) / 60.0, 2)
        spent_h = round(parse_minutes(get_value(row, idx, "Tempo speso")) / 60.0, 2)

        status = map_status(get_value(row, idx, "Stato"), get_value(row, idx, "Pianificato"), spent_h, est_h)

        tid = task_id(row_no, old_id, title, project_nr, project_name, client, deadline, assignee_name)
        fields = {
            "companyId": fs_string(company_id),
            "projectId": fs_string(pid),
            "phaseId": fs_string(phid),
            "assigneeId": fs_string(assignee_id),
            "name": fs_string(title),
            "estimatedHours": fs_double(est_h),
            "loggedHours": fs_double(spent_h),
            "startDate": fs_ts(start_date),
            "deadline": fs_ts(deadline),
            "status": fs_string(status),
            "billable": fs_bool(True),
        }
        task_payloads.append((tid, fields))

        if i % 4000 == 0:
            print(f"Prepared tasks: {i}/{len(task_rows)}")

    created_tasks = 0
    updated_tasks = 0
    skipped_tasks = 0

    def upsert_task(item):
        tid, fields = item
        st, _ = fs_patch(f"users/{owner_uid}/tasks/{tid}", token, fields)
        return tid, st

    with ThreadPoolExecutor(max_workers=18) as ex:
        futures = [ex.submit(upsert_task, item) for item in task_payloads]
        for i, fut in enumerate(as_completed(futures), start=1):
            tid, st = fut.result()
            if st >= 300:
                skipped_tasks += 1
            elif tid in existing_task_ids:
                updated_tasks += 1
            else:
                created_tasks += 1
                existing_task_ids.add(tid)
            if i % 2000 == 0:
                print(f"Upsert progress: {i}/{len(task_payloads)}")

    print("\nImport task completato")
    print(json.dumps({
        "ownerUid": owner_uid,
        "teamId": team_id,
        "projects": {"created": created_projects, "updated": updated_projects},
        "phases": {"created": created_phases, "updated": updated_phases},
        "tasks": {
            "created": created_tasks,
            "updated": updated_tasks,
            "skipped": skipped_tasks,
            "totalProcessed": len(task_payloads),
        },
        "notes": [
            "Link task -> project/phase/company/assignee risolti con fallback coerenti.",
            "Progetti/fasi mancanti creati automaticamente.",
            "Stato task mappato su backlog/planned/inProgress/done.",
        ],
    }, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
