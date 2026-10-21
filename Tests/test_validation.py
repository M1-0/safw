import importlib.util
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

from cryptography.fernet import Fernet

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("safw_validation", ROOT / "Validation/service.py")
service = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = service
spec.loader.exec_module(service)
NOW = 1792200000
START, END = NOW - 12 * 3600, NOW - 4 * 3600


def iso(ts):
    return service.datetime.fromtimestamp(ts, service.timezone.utc).isoformat()


def observation(**changes):
    row = dict(device="a" * 64, algorithm="noop-12.0.0-fixture-v1", start=START, end=END,
               captured_at=NOW, recovery=60, hrv=40, rhr=55, light=240, deep=90, rem=90, awake=60,
               sparse=False, user_edited=False, local_recovery_input=True)
    row.update(changes)
    return row


def sleep(**changes):
    row = dict(id="night-1", start=iso(START), end=iso(END), nap=False, score_state="SCORED",
               score=dict(stage_summary=dict(total_light_sleep_time_milli=250 * 60000,
                   total_slow_wave_sleep_time_milli=80 * 60000, total_rem_sleep_time_milli=90 * 60000,
                   total_awake_time_milli=60 * 60000, total_no_data_time_milli=0)))
    row.update(changes)
    return row


def recovery(**changes):
    row = dict(sleep_id="night-1", score_state="SCORED", score=dict(user_calibrating=False,
                   recovery_score=50, hrv_rmssd_milli=35, resting_heart_rate=57))
    row.update(changes)
    return row


class ComparisonTests(unittest.TestCase):
    def report(self, rows=None, sleeps=None, recoveries=None):
        return service.compare(rows or [observation()], sleeps or [sleep()], recoveries or [recovery()])[0]

    def test_units_bias_and_missing_values(self):
        result = self.report()
        self.assertEqual(result["metrics"]["recovery"], dict(n=1, mae=10, bias=10))
        self.assertEqual(result["metrics"]["light"], dict(n=1, mae=10, bias=-10))
        self.assertEqual(result["metrics"]["rhr"]["bias"], -2)
        self.assertEqual(self.report([observation(recovery=None)])["metrics"]["recovery"]["n"], 0)

    def test_no_recovery_when_provenance_unknown_or_reference_calibrating(self):
        for row in [observation(local_recovery_input=False), observation(sparse=True), observation(user_edited=True)]:
            self.assertEqual(self.report([row])["metrics"]["recovery"]["n"], 0)
        result = self.report(recoveries=[recovery(score=dict(user_calibrating=True, recovery_score=50))])
        self.assertEqual(result["metrics"]["recovery"]["n"], 0)

    def test_sleep_reference_not_available_does_not_become_zero(self):
        result = self.report(sleeps=[sleep(score_state="PENDING_SCORE", score=None)])
        self.assertEqual(result["unmatched"], 1)
        self.assertEqual(result["metrics"]["deep"], dict(n=0, mae=None, bias=None))

    def test_no_epoch_accuracy_field(self):
        self.assertNotIn("accuracy", json.dumps(self.report()))

    def test_naps_and_wrong_intervals_not_matched(self):
        self.assertEqual(self.report(sleeps=[sleep(nap=True)])["unmatched"], 1)
        self.assertEqual(self.report(sleeps=[sleep(start=iso(START - 86400), end=iso(END - 86400))])["unmatched"], 1)

    def test_reference_missing_signal_is_excluded(self):
        reference = sleep()
        reference['score']['stage_summary']['total_no_data_time_milli'] = 60000
        result = self.report(sleeps=[reference])
        self.assertEqual(result['quality_excluded'], 1)
        self.assertEqual(result['metrics']['recovery']['n'], 0)

    def test_equal_overlap_and_duplicate_night_are_ambiguous(self):
        result = self.report(sleeps=[sleep(), sleep(id="night-2")])
        self.assertEqual(result["ambiguous"], 1)
        result = self.report(rows=[observation(), observation(start=START + 60)])
        self.assertEqual(result["ambiguous"], 2)
        self.assertEqual(result["metrics"]["recovery"]["n"], 0)

    def test_versions_devices_and_revisions_never_pool(self):
        result = service.compare([observation(), observation(algorithm="v2"), observation(device="b" * 64),
                                  observation(recovery=65, captured_at=NOW + 1)], [sleep()], [recovery()])
        self.assertEqual(len(result), 3)
        original = next(x for x in result if x["device"] == "a" * 64 and x["algorithm"] != "v2")
        self.assertEqual(original["observations"], 1)
        self.assertEqual(original["metrics"]["recovery"]["mae"], 15)


class ReceiverTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.config = service.Config("client-id", "client-secret", "https://owner.example", "s" * 48,
                                     Fernet.generate_key().decode(), Path(self.temp.name) / "data.sqlite")
        self.calls, self.responses = [], []
        self.app = service.Service(self.config, http=self.http, clock=lambda: NOW)

    def tearDown(self):
        self.temp.cleanup()

    def http(self, method, path, **kwargs):
        self.calls.append((method, path, kwargs))
        response = self.responses.pop(0)
        if isinstance(response, Exception):
            raise response
        return response

    def tokens(self):
        return dict(access_token="upstream-access", refresh_token="upstream-refresh", expires_in=3600)

    def wsgi(self, method, path, body=None, authorized=True, **extra):
        data = service.encoded(body) if body is not None else b""
        env = {"REQUEST_METHOD": method, "PATH_INFO": path, "CONTENT_LENGTH": str(len(data)),
               "CONTENT_TYPE": "application/json", "wsgi.input": io.BytesIO(data),
               "HTTP_AUTHORIZATION": "Bearer " + self.config.owner_token if authorized else ""}
        env.update(extra)
        statuses = []
        payload = b"".join(self.app(env, lambda status, headers: statuses.append((status, headers))))
        return statuses[0], json.loads(payload) if payload else None

    def test_pairing_auth_required_for_every_private_endpoint(self):
        for method, path in [("POST", "/v1/connect"), ("GET", "/v1/report"),
                             ("POST", "/v1/observations"), ("DELETE", "/v1/data")]:
            (status, _), body = self.wsgi(method, path, authorized=False)
            self.assertTrue(status.startswith("401"))
            self.assertEqual(body, {"error": "unauthorized"})

    def test_oauth_state_expiry_wrong_state_and_replay(self):
        auth = self.app.start_connect()["authorization_url"]
        query = parse_qs(urlsplit(auth).query)
        self.assertEqual(query["scope"], ["read:recovery read:sleep offline"])
        self.assertNotIn("client-secret", auth)
        with self.assertRaises(service.ServiceError):
            self.app.callback(dict(state="wrong", code="x"))
        self.responses = [self.tokens()]
        params = dict(state=query["state"][0], code="authorization-code")
        self.app.callback(params)
        with self.assertRaises(service.ServiceError):
            self.app.callback(params)
        self.assertEqual(self.app.vault.get("tokens")["access"], "upstream-access")
        self.assertEqual(len(self.calls), 1)

    def test_expired_state_rejected(self):
        auth = self.app.start_connect()["authorization_url"]
        self.app.clock = lambda: NOW + 601
        with self.assertRaises(service.ServiceError):
            self.app.callback(dict(state=parse_qs(urlsplit(auth).query)["state"][0], code="x"))

    def test_rotating_refresh_token_is_persisted(self):
        self.app.vault.put("tokens", dict(access="expired", refresh="old-refresh", expires=NOW - 1))
        self.responses = [dict(access_token="new-access", refresh_token="new-refresh", expires_in=3600)]
        self.assertEqual(self.app.access(), "new-access")
        self.assertEqual(self.app.vault.get("tokens")["refresh"], "new-refresh")
        self.assertEqual(self.calls[0][2]["form"]["refresh_token"], "old-refresh")

    def test_paginated_reference_sync_is_atomic_and_throttled(self):
        self.app.save_tokens(self.tokens())
        self.responses = [dict(records=[sleep()], next_token="page2"), dict(records=[], next_token=None),
                          dict(records=[recovery()], next_token=None)]
        self.app.sync()
        self.app.sync()
        self.assertEqual(len(self.calls), 3)
        self.assertIn("nextToken=page2", self.calls[1][1])
        self.assertEqual(self.app.vault.get("sync")["last_success"], NOW)
        before = self.app.vault.get("references")
        self.app.clock = lambda: NOW + 7 * 3600
        self.responses = [dict(records=[sleep(id="new")]), service.ServiceError("whoop_rate_limited", 503)]
        with self.assertRaises(service.ServiceError):
            self.app.sync()
        self.assertEqual(self.app.vault.get("references"), before)

    def test_repeated_next_token_cannot_loop(self):
        self.responses = [dict(records=[], next_token="x"), dict(records=[], next_token="x")]
        with self.assertRaises(service.ServiceError):
            self.app.collection("/developer/v2/recovery", "access")
        self.assertEqual(len(self.calls), 2)

    def test_encryption_and_idempotent_observations(self):
        self.app.receive(dict(observations=[observation()]))
        self.app.receive(dict(observations=[observation(captured_at=NOW + 1)]))
        self.assertEqual(len(self.app.vault.values("observation:")), 1)
        self.app.save_tokens(self.tokens())
        raw = self.config.database.read_bytes()
        self.assertNotIn(b"upstream-access", raw)
        self.assertNotIn(b"noop-12.0.0-fixture-v1", raw)
        self.assertEqual(self.config.database.stat().st_mode & 0o777, 0o600)

    def test_reverting_to_an_earlier_prediction_uses_latest_seen_revision(self):
        self.app.receive(dict(observations=[observation()]))
        self.app.receive(dict(observations=[observation(recovery=70, captured_at=NOW + 1)]))
        self.app.receive(dict(observations=[observation(captured_at=NOW + 2)]))
        rows = self.app.vault.values('observation:')
        result = service.compare(rows, [sleep()], [recovery()])[0]
        self.assertEqual(len(rows), 2)
        self.assertEqual(result['metrics']['recovery']['mae'], 10)

    def test_upstream_failure_backoff_prevents_repeated_requests(self):
        self.app.save_tokens(self.tokens())
        self.responses = [service.ServiceError('whoop_rate_limited', 503)]
        with self.assertRaises(service.ServiceError):
            self.app.sync()
        self.app.sync()
        self.assertEqual(len(self.calls), 1)

    def test_reports_do_not_claim_baseline_independence(self):
        self.assertFalse(self.app.report()['baseline_independence_verified'])

    def test_first_timely_result_is_frozen_before_reference_fetch(self):
        self.app.vault.put("references", dict(sleeps=[sleep()], recoveries=[recovery()]))
        first = self.app.receive(dict(observations=[observation()]))
        self.app.clock = lambda: NOW + 1
        changed = self.app.receive(dict(observations=[observation(recovery=50, captured_at=NOW + 1)]))
        self.assertEqual(first['groups'][0]['metrics']['recovery']['mae'], 10)
        self.assertEqual(changed['groups'][0]['metrics']['recovery']['mae'], 10)
        self.assertEqual(changed['retrospective_groups'][0]['metrics']['recovery']['mae'], 0)
        self.assertEqual(len(self.app.vault.values('prospective:')), 1)

    def test_retrospective_or_backdated_upload_is_not_prospective(self):
        self.app.clock = lambda: END + service.PROSPECTIVE_WINDOW + 1
        self.app.receive(dict(observations=[observation()]))
        self.assertEqual(self.app.report()['groups'], [])
        self.assertEqual(len(self.app.vault.values('observation:')), 1)
        self.assertEqual(self.app.vault.values('prospective:'), [])

    def test_first_sparse_or_missing_result_cannot_be_replaced_by_better_revision(self):
        self.app.vault.put("references", dict(sleeps=[sleep()], recoveries=[recovery()]))
        self.app.receive(dict(observations=[observation(sparse=True, recovery=None)]))
        self.app.clock = lambda: NOW + 1
        result = self.app.receive(dict(observations=[observation(recovery=50, captured_at=NOW + 1)]))
        self.assertEqual(result['groups'][0]['quality_excluded'], 1)
        self.assertEqual(result['groups'][0]['metrics']['recovery']['n'], 0)
        self.assertEqual(result['retrospective_groups'][0]['metrics']['recovery']['n'], 1)

    def test_prospective_versions_and_devices_stay_separate(self):
        self.app.receive(dict(observations=[observation(), observation(algorithm='v2'),
                                             observation(device='b' * 64)]))
        self.assertEqual(len(self.app.vault.values('prospective:')), 3)

    def test_legacy_observations_do_not_become_prospective_on_late_reupload(self):
        self.app.vault.put('observation:legacy', observation())
        self.app.clock = lambda: NOW + 2 * 86400
        self.app.receive(dict(observations=[observation(captured_at=NOW + 2 * 86400)]))
        self.assertEqual(self.app.report()['groups'], [])

    def test_prospective_window_end_and_capture_delay(self):
        self.app.clock = lambda: END + service.PROSPECTIVE_WINDOW
        self.app.receive(dict(observations=[observation(captured_at=END + 3600)]))
        self.assertEqual(len(self.app.vault.values('prospective:')), 1)
        self.app.vault.clear()
        self.app.receive(dict(observations=[observation(captured_at=END + 3599)]))
        self.assertEqual(self.app.vault.values('prospective:'), [])

    def test_all_rows_validated_before_any_write(self):
        with self.assertRaises(service.ServiceError):
            self.app.receive(dict(observations=[observation(), observation(recovery=101)]))
        self.assertEqual(self.app.vault.values("observation:"), [])

    def test_malformed_intervals_and_metrics_are_rejected(self):
        for change in [dict(recovery=float("nan")), dict(recovery=True), dict(end=NOW),
                       dict(start=END + 1), dict(sparse=None), dict(deep=None), dict(deep=999)]:
            with self.subTest(change=change), self.assertRaises(service.ServiceError):
                service.validate_observation(observation(**change), NOW)

    def test_body_limit_and_delete(self):
        (status, _), _ = self.wsgi("POST", "/v1/observations", CONTENT_LENGTH="9999999")
        self.assertTrue(status.startswith("413"))
        self.app.receive(dict(observations=[observation()]))
        (status, _), body = self.wsgi("DELETE", "/v1/data")
        self.assertTrue(status.startswith("200"))
        self.assertTrue(body["deleted"])
        self.assertEqual(self.app.vault.values("observation:"), [])

    def test_non_https_origin_disallowed(self):
        with self.assertRaises(ValueError):
            service.Config("id", "secret", "http://owner.example", "s" * 48,
                           self.config.data_key, self.config.database)


if __name__ == "__main__":
    unittest.main()
