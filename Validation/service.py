#!/usr/bin/env python3
"""Single-owner, opt-in WHOOP reference receiver. No app credentials belong in an IPA."""
from __future__ import annotations

import argparse
import hashlib
import hmac
import json
import math
import os
import secrets
import sqlite3
import threading
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from urllib import error, parse, request
from wsgiref.simple_server import WSGIRequestHandler, make_server

from cryptography.fernet import Fernet

API = "https://api.prod.whoop.com"
SCOPES = "read:recovery read:sleep offline"
MAX_BODY = 262144
PROSPECTIVE_WINDOW = 24 * 3600


class ServiceError(Exception):
    def __init__(self, code, status=400):
        self.code, self.status = code, status


def stamp(value):
    return datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()


def finite(value, low, high):
    return (not isinstance(value, bool) and isinstance(value, (int, float))
            and math.isfinite(value) and low <= value <= high)


def encoded(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()


@dataclass(frozen=True)
class Config:
    client_id: str
    client_secret: str
    public_url: str
    owner_token: str
    data_key: str
    database: Path

    def __post_init__(self):
        url = parse.urlsplit(self.public_url)
        if (url.scheme != "https" or not url.hostname or url.username or url.password
                or url.query or url.fragment or url.path not in ("", "/")):
            raise ValueError("SAFW_PUBLIC_URL must be a bare HTTPS origin")
        if len(self.owner_token) < 32 or not self.client_id or not self.client_secret:
            raise ValueError("WHOOP credentials and a random owner token are required")
        Fernet(self.data_key.encode())

    @property
    def redirect(self):
        return self.public_url.rstrip("/") + "/oauth/callback"

    @classmethod
    def environment(cls):
        return cls(os.environ["WHOOP_CLIENT_ID"], os.environ["WHOOP_CLIENT_SECRET"],
                   os.environ["SAFW_PUBLIC_URL"], os.environ["SAFW_OWNER_TOKEN"],
                   os.environ["SAFW_DATA_KEY"], Path(os.environ.get("SAFW_DATABASE",
                       str(Path(__file__).resolve().parent / "state/validation.sqlite"))))


class Vault:
    """Only opaque keys and encrypted JSON are persisted. The encryption key stays outside SQLite."""
    def __init__(self, path, key):
        path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.path, self.cipher = path, Fernet(key.encode())
        with self.connection() as db:
            db.execute("CREATE TABLE IF NOT EXISTS item (key TEXT PRIMARY KEY, payload BLOB NOT NULL)")
        os.chmod(path, 0o600)

    def connection(self):
        return sqlite3.connect(self.path, timeout=15)

    def put(self, key, value):
        with self.connection() as db:
            db.execute("INSERT OR REPLACE INTO item VALUES (?, ?)",
                       (key, self.cipher.encrypt(encoded(value))))

    def get(self, key, default=None):
        with self.connection() as db:
            row = db.execute("SELECT payload FROM item WHERE key = ?", (key,)).fetchone()
        return json.loads(self.cipher.decrypt(row[0])) if row else default

    def pop(self, key):
        with self.connection() as db:
            db.execute("BEGIN IMMEDIATE")
            row = db.execute("SELECT payload FROM item WHERE key = ?", (key,)).fetchone()
            db.execute("DELETE FROM item WHERE key = ?", (key,))
        return json.loads(self.cipher.decrypt(row[0])) if row else None

    def values(self, prefix):
        with self.connection() as db:
            rows = db.execute("SELECT payload FROM item WHERE key LIKE ?", (prefix + "%",)).fetchall()
        return [json.loads(self.cipher.decrypt(row[0])) for row in rows]

    def clear(self):
        with self.connection() as db:
            db.execute("DELETE FROM item")


class WhoopHTTP:
    """Fixed upstream origins, bounded responses, finite timeouts, no credential/body logging."""
    def __call__(self, method, path, *, bearer=None, form=None):
        headers = {"Accept": "application/json"}
        data = None
        if bearer:
            headers["Authorization"] = "Bearer " + bearer
        if form is not None:
            headers["Content-Type"] = "application/x-www-form-urlencoded"
            data = parse.urlencode(form).encode()
        req = request.Request(API + path, data=data, headers=headers, method=method)
        try:
            opener = request.build_opener(NoRedirect())
            with opener.open(req, timeout=20) as response:
                body = response.read(4 * 1024 * 1024 + 1)
        except error.HTTPError as exc:
            if exc.code == 401:
                raise ServiceError("whoop_authorization_required", 409) from None
            if exc.code == 429:
                raise ServiceError("whoop_rate_limited", 503) from None
            raise ServiceError("whoop_unavailable", 502) from None
        except (error.URLError, TimeoutError, OSError):
            raise ServiceError("whoop_unavailable", 502) from None
        if len(body) > 4 * 1024 * 1024:
            raise ServiceError("whoop_response_too_large", 502)
        try:
            return json.loads(body)
        except (ValueError, UnicodeError):
            raise ServiceError("whoop_invalid_response", 502) from None


class NoRedirect(request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def validate_observation(row, now):
    fields = {"device", "algorithm", "start", "end", "captured_at", "recovery", "hrv", "rhr",
              "light", "deep", "rem", "awake", "sparse", "user_edited", "local_recovery_input"}
    if not isinstance(row, dict) or set(row) != fields:
        raise ServiceError("invalid_observation")
    if (not isinstance(row["device"], str) or len(row["device"]) != 64
            or any(ch not in "0123456789abcdef" for ch in row["device"])):
        raise ServiceError("invalid_device")
    if not isinstance(row["algorithm"], str) or not 1 <= len(row["algorithm"]) <= 180:
        raise ServiceError("invalid_algorithm")
    if (not finite(row["start"], now - 180 * 86400, now)
            or not finite(row["end"], row["start"] + 1, min(now - 3600, row["start"] + 24 * 3600))
            or not finite(row["captured_at"], row["end"], now + 300)):
        raise ServiceError("invalid_interval")
    for key in ["sparse", "user_edited", "local_recovery_input"]:
        if not isinstance(row[key], bool):
            raise ServiceError("invalid_quality")
    for key, upper in [("recovery", 100), ("hrv", 1000), ("rhr", 250),
                       ("light", 1440), ("deep", 1440), ("rem", 1440), ("awake", 1440)]:
        if row[key] is not None and not finite(row[key], 0, upper):
            raise ServiceError("invalid_metric")
    stages = [row[key] for key in ["light", "deep", "rem", "awake"]]
    if any(v is None for v in stages) and not all(v is None for v in stages):
        raise ServiceError("partial_stages")
    if stages[0] is not None and sum(stages) > (row["end"] - row["start"]) / 60 + 1:
        raise ServiceError("invalid_stage_duration")
    return row


def statistics(pairs):
    if not pairs:
        return {"n": 0, "mae": None, "bias": None}
    deltas = [candidate - reference for candidate, reference in pairs]
    return {"n": len(deltas), "mae": sum(abs(x) for x in deltas) / len(deltas),
            "bias": sum(deltas) / len(deltas)}


def compare(observations, sleeps, recoveries):
    """Match by actual intervals, not calendar dates; keep revisions/algorithms/devices separate."""
    scored = []
    for sleep in sleeps:
        if sleep.get("nap") or sleep.get("score_state") != "SCORED" or not sleep.get("score"):
            continue
        try:
            start, end = stamp(sleep["start"]), stamp(sleep["end"])
            if end <= start:
                continue
        except (KeyError, ValueError, TypeError):
            continue
        scored.append((sleep, start, end))
    by_sleep = {row["sleep_id"]: row for row in recoveries
                if row.get("score_state") == "SCORED" and row.get("score")}
    groups = {}
    latest = {}
    for row in observations:
        key = (row["device"], row["algorithm"], row["start"])
        if key not in latest or row.get("_last_captured", row["captured_at"]) > latest[key].get("_last_captured", latest[key]["captured_at"]):
            latest[key] = row
    for row in latest.values():
        group_key = (row["device"], row["algorithm"])
        group = groups.setdefault(group_key, {"device": row["device"], "algorithm": row["algorithm"],
            "observations": 0, "matched": 0, "unmatched": 0, "ambiguous": 0, "quality_excluded": 0,
            "reference_nights": len(scored), "_rows": [], "_matches": {}})
        group["observations"] += 1
        matches = []
        for sleep, start, end in scored:
            overlap = max(0, min(end, row["end"]) - max(start, row["start"]))
            union = max(end, row["end"]) - min(start, row["start"])
            if overlap and overlap / union >= .5:
                matches.append((overlap / union, sleep))
        matches.sort(key=lambda item: item[0], reverse=True)
        if not matches:
            group["unmatched"] += 1
        elif len(matches) > 1 and matches[0][0] - matches[1][0] < .1:
            group["ambiguous"] += 1
        else:
            sleep = matches[0][1]
            group["_matches"].setdefault(sleep["id"], []).append((row, sleep))
    result = []
    for group in groups.values():
        metrics = {key: [] for key in ["recovery", "hrv", "rhr", "light", "deep", "rem", "awake"]}
        for candidates in group.pop("_matches").values():
            if len(candidates) != 1:
                group["ambiguous"] += len(candidates)  # Never count the same reference twice.
                continue
            row, sleep = candidates[0]
            group["matched"] += 1
            if row["sparse"] or row["user_edited"]:
                group["quality_excluded"] += 1
                continue
            if sleep["score"].get("stage_summary", {}).get("total_no_data_time_milli", 0) > 0:
                group["quality_excluded"] += 1
                continue
            recovery = by_sleep.get(sleep["id"], {}).get("score", {})
            if not recovery.get("user_calibrating", True) and row["local_recovery_input"]:
                for metric, reference_key in [("recovery", "recovery_score"),
                                               ("hrv", "hrv_rmssd_milli"), ("rhr", "resting_heart_rate")]:
                    a, b = row[metric], recovery.get(reference_key)
                    if a is not None and finite(b, 0, 1000):
                        metrics[metric].append((a, b))
            stages = sleep["score"].get("stage_summary", {})
            for metric, reference_key in [("light", "total_light_sleep_time_milli"),
                                           ("deep", "total_slow_wave_sleep_time_milli"),
                                           ("rem", "total_rem_sleep_time_milli"),
                                           ("awake", "total_awake_time_milli")]:
                a, b = row[metric], stages.get(reference_key)
                if a is not None and finite(b, 0, 86400000):
                    metrics[metric].append((a, b / 60000))
        group.pop("_rows")
        group["metrics"] = {key: statistics(value) for key, value in metrics.items()}
        result.append(group)
    return sorted(result, key=lambda row: (row["device"], row["algorithm"]))


class Service:
    def __init__(self, config, http=None, clock=time.time):
        self.config, self.http, self.clock = config, http or WhoopHTTP(), clock
        self.vault = Vault(config.database, config.data_key)
        self.lock = threading.RLock()

    def start_connect(self):
        state = secrets.token_urlsafe(32)
        self.vault.put("oauth_state", {"digest": hashlib.sha256(state.encode()).hexdigest(),
                                       "expires": self.clock() + 600})
        url = API + "/oauth/oauth2/auth?" + parse.urlencode({"client_id": self.config.client_id,
            "redirect_uri": self.config.redirect, "response_type": "code", "scope": SCOPES, "state": state})
        return {"authorization_url": url}

    def callback(self, params):
        state = params.get("state", "")
        current = self.vault.get("oauth_state")
        if (not current or self.clock() > current["expires"] or not hmac.compare_digest(
                hashlib.sha256(state.encode()).hexdigest(), current["digest"])):
            raise ServiceError("invalid_oauth_state")
        self.vault.pop("oauth_state")
        if "error" in params or not params.get("code"):
            raise ServiceError("whoop_connection_denied")
        tokens = self.http("POST", "/oauth/oauth2/token", form={"grant_type": "authorization_code",
            "code": params["code"], "client_id": self.config.client_id,
            "client_secret": self.config.client_secret, "redirect_uri": self.config.redirect})
        self.save_tokens(tokens)
        self.vault.put("sync", {"last_success": 0, "error": None})

    def save_tokens(self, tokens):
        if (not tokens.get("access_token") or not tokens.get("refresh_token")
                or not finite(tokens.get("expires_in"), 1, 30 * 86400)):
            raise ServiceError("whoop_invalid_token_response", 502)
        self.vault.put("tokens", {"access": tokens["access_token"], "refresh": tokens["refresh_token"],
                                  "expires": self.clock() + tokens["expires_in"]})

    def access(self):
        tokens = self.vault.get("tokens")
        if not tokens:
            raise ServiceError("whoop_authorization_required", 409)
        if tokens["expires"] <= self.clock() + 60:
            response = self.http("POST", "/oauth/oauth2/token", form={"grant_type": "refresh_token",
                "refresh_token": tokens["refresh"], "client_id": self.config.client_id,
                "client_secret": self.config.client_secret, "scope": "offline"})
            self.save_tokens(response)  # Persist the rotated refresh token BEFORE any next request.
            tokens = self.vault.get("tokens")
        return tokens["access"]

    def collection(self, path, bearer):
        start = datetime.fromtimestamp(self.clock() - 90 * 86400, timezone.utc).isoformat()
        records, token, seen = [], None, set()
        for _ in range(500):
            query = {"limit": 25, "start": start}
            if token:
                query["nextToken"] = token
            result = self.http("GET", path + "?" + parse.urlencode(query), bearer=bearer)
            if not isinstance(result.get("records"), list):
                raise ServiceError("whoop_invalid_response", 502)
            records.extend(result["records"])
            token = result.get("next_token")
            if not token:
                return records
            if not isinstance(token, str) or token in seen:
                raise ServiceError("whoop_repeated_page", 502)
            seen.add(token)
        raise ServiceError("whoop_page_limit", 502)

    def sync(self):
        with self.lock:
            previous = self.vault.get("sync", {"last_success": 0, "error": None})
            if (self.clock() - previous["last_success"] < 6 * 3600
                    or self.clock() - previous.get("last_attempt", 0) < 15 * 60
                    or not self.vault.get("tokens")):
                return
            self.vault.put("sync", dict(previous, last_attempt=self.clock()))
            try:
                bearer = self.access()
                sleeps = self.collection("/developer/v2/activity/sleep", bearer)
                recoveries = self.collection("/developer/v2/recovery", bearer)
                # Publish one complete reference snapshot; never pair one new and one stale collection.
                self.vault.put("references", {"sleeps": sleeps, "recoveries": recoveries})
                self.vault.put("sync", {"last_success": self.clock(), "last_attempt": self.clock(), "error": None})
            except ServiceError as exc:
                self.vault.put("sync", {"last_success": previous["last_success"],
                                        "last_attempt": self.clock(), "error": exc.code})
                raise

    def receive(self, body):
        if not isinstance(body, dict) or set(body) != {"observations"}:
            raise ServiceError("invalid_payload")
        rows = body["observations"]
        if not isinstance(rows, list) or len(rows) > 200:
            raise ServiceError("invalid_batch")
        checked = [validate_observation(row, self.clock()) for row in rows]
        for row in checked:
            # Freeze the first timely upload before fetching its WHOOP reference. Retrospective
            # recomputation must not improve the primary evaluation by replacing an earlier result.
            # Both server receipt time and phone capture time must be within the declared window.
            received = self.clock()
            if (row["end"] + 3600 <= row["captured_at"] <= received + 300
                    and received <= row["end"] + PROSPECTIVE_WINDOW):
                identity = {k: row[k] for k in ("device", "algorithm", "start")}
                frozen_key = "prospective:" + hashlib.sha256(encoded(identity)).hexdigest()
                if self.vault.get(frozen_key) is None:
                    self.vault.put(frozen_key, dict(row, _first_received=received))
            stable = {k: v for k, v in row.items() if k != "captured_at"}
            key = "observation:" + hashlib.sha256(encoded(stable)).hexdigest()
            # Preserve first observation time and prior revisions; repeated syncs are idempotent.
            existing = self.vault.get(key)
            if existing is None:
                self.vault.put(key, dict(row, _last_captured=row["captured_at"]))
            else:
                existing["_last_captured"] = max(existing.get("_last_captured", existing["captured_at"]), row["captured_at"])
                self.vault.put(key, existing)
        self.sync()
        return self.report()

    def report(self):
        references = self.vault.get("references", {"sleeps": [], "recoveries": []})
        return {"connected": self.vault.get("tokens") is not None,
            "reference_kind": "WHOOP agreement; not clinical accuracy or epoch sleep-stage validation",
            "baseline_independence_verified": False,
            "evaluation_policy": {"kind": "first_timely_upload", "minimum_delay_seconds": 3600,
                "maximum_receipt_delay_seconds": PROSPECTIVE_WINDOW,
                "independent_or_blinded_prediction_verified": False},
            "sync": self.vault.get("sync", {"last_success": 0, "error": None}),
            "groups": compare(self.vault.values("prospective:"), references["sleeps"], references["recoveries"]),
            "retrospective_groups": compare(self.vault.values("observation:"), references["sleeps"], references["recoveries"])}

    def __call__(self, environ, start_response):
        headers = [("Content-Type", "application/json"), ("Cache-Control", "no-store"),
                   ("X-Content-Type-Options", "nosniff"), ("Referrer-Policy", "no-referrer")]
        try:
            method, path = environ["REQUEST_METHOD"], environ.get("PATH_INFO", "")
            if method == "GET" and path == "/health":
                result = {"ok": True}
            elif method == "GET" and path == "/oauth/callback":
                params = parse.parse_qs(environ.get("QUERY_STRING", ""), max_num_fields=10)
                if any(len(value) != 1 for value in params.values()):
                    raise ServiceError("invalid_oauth_callback")
                with self.lock:
                    self.callback({key: value[0] for key, value in params.items()})
                start_response("302 Found", headers + [("Location", "safw-validation://complete")])
                return [b""]
            else:
                supplied = environ.get("HTTP_AUTHORIZATION", "")
                if not hmac.compare_digest(supplied, "Bearer " + self.config.owner_token):
                    raise ServiceError("unauthorized", 401)
                if method == "POST" and path == "/v1/connect":
                    with self.lock:
                        result = self.start_connect()
                elif method == "GET" and path == "/v1/report":
                    with self.lock:
                        result = self.report()
                elif method == "POST" and path == "/v1/observations":
                    try:
                        size = int(environ.get("CONTENT_LENGTH", "0"))
                    except ValueError:
                        raise ServiceError("invalid_content_length") from None
                    if not 0 < size <= MAX_BODY:
                        raise ServiceError("body_too_large", 413)
                    if environ.get("CONTENT_TYPE", "").split(";", 1)[0] != "application/json":
                        raise ServiceError("json_required", 415)
                    try:
                        body = json.loads(environ["wsgi.input"].read(size))
                    except (ValueError, UnicodeError):
                        raise ServiceError("invalid_json") from None
                    with self.lock:
                        result = self.receive(body)
                elif method == "DELETE" and path == "/v1/data":
                    with self.lock:
                        self.vault.clear()
                    result = {"deleted": True}
                else:
                    raise ServiceError("not_found", 404)
            start_response("200 OK", headers)
            return [encoded(result)]
        except ServiceError as exc:
            start_response(str(exc.status) + " Error", headers)
            return [encoded({"error": exc.code})]
        except Exception:
            # Nothing from upstream credentials, callback parameters or health payloads enters a log.
            start_response("500 Error", headers)
            return [b'{"error":"internal_error"}']


class QuietHandler(WSGIRequestHandler):
    def log_message(self, *_args):
        pass


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["serve", "sync"], nargs="?", default="serve")
    parser.add_argument("--port", type=int, default=8769)
    args = parser.parse_args()
    service = Service(Config.environment())
    if args.action == "sync":
        service.sync()
        return
    # A user-owned TLS reverse proxy is required. Never expose wsgiref directly to the Internet.
    with make_server("127.0.0.1", args.port, service, handler_class=QuietHandler) as server:
        server.serve_forever()


if __name__ == "__main__":
    main()
