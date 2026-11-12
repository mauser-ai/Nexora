#!/usr/bin/env python3
"""Allowlisted Teamleader API proxy for the private n8n node."""

from __future__ import annotations

import json
import time
import urllib.error
import urllib.request
from pathlib import Path

from teamleader_api_rate_limit import defer_for, request_slot
from teamleader_oauth import paths, post_form, read_json, save_token

API_URL = "https://api.focus.teamleader.eu"
CATALOG_PATH = Path(__file__).with_name("teamleader-api-catalog.json")
MAX_RETRIES = 3
MAX_AUTOMATIC_WAIT = 120
_operations: dict[str, dict] | None = None


class TeamleaderAPIError(RuntimeError):
    def __init__(self, status: int, detail: str):
        super().__init__(detail)
        self.status = status
        self.detail = detail


def operations() -> dict[str, dict]:
    global _operations
    if _operations is None:
        catalog = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
        _operations = {operation["id"]: operation for operation in catalog["operations"]}
    return _operations


def _refresh_token(config: dict, token_path: Path, token: dict) -> dict:
    refreshed = post_form({
        "client_id": config["client_id"],
        "client_secret": config["client_secret"],
        "refresh_token": token["refresh_token"],
        "grant_type": "refresh_token",
    })
    save_token(refreshed, token_path)
    return refreshed


def _valid_body(operation: dict, body: object) -> dict:
    if not isinstance(body, dict):
        raise TeamleaderAPIError(400, "Il body dell’operazione deve essere un oggetto JSON.")
    if operation.get("id") in ("timeTracking.add", "timeTracking.update"):
        missing = []
        if operation["id"] == "timeTracking.update" and "id" not in body:
            missing.append("id")
        has_clock = "started_at" in body
        has_duration_day = "started_on" in body and "duration" in body
        if not has_clock and not has_duration_day:
            missing.append("started_at+ended_at oppure started_on+duration")
        if has_clock and "ended_at" not in body and "duration" not in body:
            missing.append("ended_at oppure duration")
        if missing:
            raise TeamleaderAPIError(400, "Parametri obbligatori mancanti: " + ", ".join(missing))
        return body
    missing = [parameter["name"] for parameter in operation["parameters"]
               if parameter.get("required") and parameter["name"] not in body]
    if missing:
        raise TeamleaderAPIError(400, "Parametri obbligatori mancanti: " + ", ".join(missing))
    return body


def execute(operation_id: str, body: object) -> tuple[int, object]:
    operation = operations().get(operation_id)
    if operation is None:
        raise TeamleaderAPIError(400, "Operazione non presente nel catalogo ufficiale Teamleader.")
    if operation.get("method") != "POST" or not str(operation.get("path", "")).startswith("/"):
        raise TeamleaderAPIError(400, "Metodo o percorso API non consentito.")
    request_body = _valid_body(operation, body)
    config_path, token_path = paths()
    config = read_json(config_path)
    token = read_json(token_path)
    now = int(time.time())
    if int(token.get("saved_at", 0)) + int(token.get("expires_in", 0)) < now + 60:
        token = _refresh_token(config, token_path, token)

    payload = json.dumps(request_body, ensure_ascii=False).encode("utf-8")
    refreshed = False
    for attempt in range(MAX_RETRIES):
        request = urllib.request.Request(
            f"{API_URL}{operation['path']}",
            data=payload,
            headers={
                "Authorization": f"Bearer {token['access_token']}",
                "Content-Type": "application/json",
                "Accept": "application/json",
            },
            method="POST",
        )
        try:
            with request_slot():
                with urllib.request.urlopen(request, timeout=90) as response:
                    raw = response.read(8 * 1024 * 1024 + 1)
                    if len(raw) > 8 * 1024 * 1024:
                        raise TeamleaderAPIError(502, "Risposta Teamleader oltre il limite di 8 MB.")
                    if not raw:
                        return response.status, {"ok": True, "status": response.status}
                    try:
                        return response.status, json.loads(raw)
                    except json.JSONDecodeError:
                        return response.status, {"raw": raw.decode("utf-8", "replace")}
        except urllib.error.HTTPError as error:
            detail = error.read(1024 * 1024).decode("utf-8", "replace")
            if error.code == 401 and not refreshed:
                token = _refresh_token(config, token_path, token)
                refreshed = True
                continue
            if error.code == 429 and attempt < MAX_RETRIES - 1:
                raw_retry = error.headers.get("Retry-After", "30")
                try:
                    delay = max(1, int(float(raw_retry)))
                except ValueError:
                    delay = 30
                if delay <= MAX_AUTOMATIC_WAIT:
                    defer_for(delay)
                    continue
                raise TeamleaderAPIError(429, f"Rate limit Teamleader: riprova tra {delay} secondi. {detail[:1500]}")
            raise TeamleaderAPIError(error.code, detail[:4000] or f"HTTP {error.code}") from error
        except urllib.error.URLError as error:
            raise TeamleaderAPIError(502, f"Errore di rete verso Teamleader: {error.reason}") from error
    raise TeamleaderAPIError(429, "Troppi tentativi consecutivi per il rate limit Teamleader.")
