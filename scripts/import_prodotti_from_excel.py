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

PRODUCTS_FILE = "/Users/riccardosacchetto/Downloads/Products-2026-04-24-16-30-23.xlsx"


def http_json(method, url, data=None, headers=None, params=None):
    if params:
        q = parse.urlencode(params, doseq=True)
        url = f"{url}?{q}"

    req_headers = {"Content-Type": "application/json"}
    if headers:
        req_headers.update(headers)

    body = None
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
    return re.sub(r"\s+", " ", s)


def clean_html(text):
    s = clean(text)
    if not s:
        return ""
    s = re.sub(r"<br\s*/?>", "\n", s, flags=re.IGNORECASE)
    s = re.sub(r"</p>", "\n", s, flags=re.IGNORECASE)
    s = re.sub(r"<[^>]+>", "", s)
    s = s.replace("&nbsp;", " ")
    return re.sub(r"\s+", " ", s).strip()


def as_float(v, default=0.0):
    if v is None:
        return default
    if isinstance(v, (int, float)):
        return float(v)
    s = clean(v).replace("€", "").replace(" ", "")
    s = s.replace(".", "").replace(",", ".") if s.count(",") == 1 and s.count(".") > 1 else s.replace(",", ".")
    try:
        return float(s)
    except Exception:
        return default


def fs_string(v):
    return {"stringValue": clean(v)}


def fs_double(v):
    return {"doubleValue": float(v)}


def fs_timestamp_now():
    return {"timestampValue": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")}


def normalize_name(name):
    s = clean(name).lower()
    s = re.sub(r"[^a-z0-9 ]+", "", s)
    return re.sub(r"\s+", " ", s).strip()


def build_product_id(name, tl_id):
    tid = clean(tl_id)
    if tid:
        safe = re.sub(r"[^a-zA-Z0-9_-]+", "-", tid).strip("-").lower()
        if safe:
            return f"prod-tl-{safe}"
    key = normalize_name(name)
    h = hashlib.sha1(key.encode("utf-8")).hexdigest()[:12]
    return f"prod-auto-{h}"


def login(email, password):
    status, data = http_json(
        "POST",
        f"https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key={API_KEY}",
        data={"email": email, "password": password, "returnSecureToken": True},
    )
    if status != 200:
        raise RuntimeError(f"Login fallito {email}: {data}")
    return data["idToken"], data["localId"]


def fs_get(path, token, params=None):
    url = f"https://firestore.googleapis.com/v1/projects/{PROJECT_ID}/databases/(default)/documents/{path}"
    return http_json("GET", url, headers={"Authorization": f"Bearer {token}"}, params=params)


def fs_patch(path, token, fields):
    url = f"https://firestore.googleapis.com/v1/projects/{PROJECT_ID}/databases/(default)/documents/{path}"
    return http_json("PATCH", url, data={"fields": fields}, headers={"Authorization": f"Bearer {token}"})


def load_rows(path):
    wb = load_workbook(path, read_only=True, data_only=True)
    ws = wb["Products"]
    rows = ws.iter_rows(values_only=True)
    header = [clean(h) for h in next(rows)]
    idx = {h: i for i, h in enumerate(header)}
    return idx, list(rows)


def category_from_row(supplier, name):
    sup = clean(supplier).lower()
    nm = clean(name).lower()
    if "hosting" in nm or "dominio" in nm or "iubenda" in nm:
        return "infrastruttura"
    if "campagna" in nm or "ads" in nm:
        return "marketing"
    if "sviluppo" in nm or "progettazione" in nm or "assistenza" in nm:
        return "servizi"
    if sup:
        return sup[:40]
    return "catalogo_import"


def main():
    print(f"Products file: {PRODUCTS_FILE}")

    token, owner_uid = login(OWNER_EMAIL, OWNER_PASSWORD)
    print(f"Owner login OK uid={owner_uid}")

    status, existing_payload = fs_get(f"users/{owner_uid}/products", token, params={"pageSize": 5000})
    if status != 200:
        raise RuntimeError(f"Impossibile leggere products esistenti status={status}")

    existing_ids = set()
    for d in existing_payload.get("documents", []) or []:
        existing_ids.add(d.get("name", "").split("/")[-1])

    idx, rows = load_rows(PRODUCTS_FILE)

    created = 0
    updated = 0
    skipped = 0

    for r in rows:
        name = clean(r[idx["Nome"]]) if "Nome" in idx else ""
        if not name:
            skipped += 1
            continue

        tl_id = clean(r[idx["ID"]]) if "ID" in idx else ""
        iva = as_float(r[idx["IVA"]] if "IVA" in idx else None, default=22.0)
        supplier = clean(r[idx["Fornitore principale"]]) if "Fornitore principale" in idx else ""
        purchase_price = as_float(r[idx["Prezzo d'acquisto"]] if "Prezzo d'acquisto" in idx else None, default=0.0)
        unit = clean(r[idx["Unità"]]) if "Unità" in idx else ""
        sell_price = as_float(r[idx["Prezzo"]] if "Prezzo" in idx else None, default=0.0)
        qty = clean(r[idx["Quantità"]]) if "Quantità" in idx else ""
        desc = clean_html(r[idx["Descrizione"]]) if "Descrizione" in idx else ""

        if sell_price <= 0 and purchase_price > 0:
            sell_price = purchase_price

        if not unit:
            unit = "pz"

        sku = tl_id
        if not sku:
            sku = ""

        notes = []
        if supplier:
            notes.append(f"Fornitore: {supplier}")
        if qty:
            notes.append(f"Qta: {qty}")
        if purchase_price > 0:
            notes.append(f"Costo acquisto: {purchase_price}")
        extra_desc = " | ".join(notes)
        final_desc = desc if desc else extra_desc
        if desc and extra_desc:
            final_desc = f"{desc} | {extra_desc}"

        pid = build_product_id(name, tl_id)

        fields = {
            "name": fs_string(name),
            "sku": fs_string(sku),
            "description": fs_string(final_desc),
            "price": fs_double(sell_price),
            "currency": fs_string("EUR"),
            "unit": fs_string(unit),
            "category": fs_string(category_from_row(supplier, name)),
            "vatRate": fs_double(iva if iva > 0 else 22.0),
            "createdAt": fs_timestamp_now(),
        }

        s_upd, _ = fs_patch(f"users/{owner_uid}/products/{pid}", token, fields)
        if s_upd >= 300:
            skipped += 1
            continue

        if pid in existing_ids:
            updated += 1
        else:
            created += 1
            existing_ids.add(pid)

    print("\nImport prodotti completato")
    print(json.dumps({
        "ownerUid": owner_uid,
        "products": {
            "created": created,
            "updated": updated,
            "skipped": skipped,
        },
        "source": PRODUCTS_FILE,
    }, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
