"""No-network tests for owner API-key smoke entrypoint."""
import io
import os
from contextlib import redirect_stdout
from unittest import TestCase, mock

import smoke_api


class SmokeTests(TestCase):
    def test_readonly_one_get(self):
        seen = []

        def transport(method, url, headers, body, cap):
            seen.append((method, url, dict(headers), body, cap))
            return b'{"data":[{"language_code":"en"}]}'

        result = smoke_api.check_api_key("dummy-secret", transport=transport)
        self.assertEqual(result, "API_READONLY_SMOKE_PASS")
        self.assertEqual(len(seen), 1)
        self.assertEqual(seen[0][0], "GET")
        self.assertTrue(seen[0][1].endswith("/infos/languages"))
        self.assertIsNone(seen[0][3])
        self.assertNotIn("dummy-secret", result)

    def test_missing_key_does_not_call_transport(self):
        for key in (None, "", " ", "secret\ninjection", "secret\rinjection"):
            self.assertEqual(
                smoke_api.check_api_key(key, transport=lambda *args: self.fail("network called")),
                "API_KEY_NOT_CONFIGURED",
            )

    def test_bad_response_fail_closed(self):
        for payload in (b"<html>not JSON", b"null", b"42", b"\xff"):
            result = smoke_api.check_api_key("key", transport=lambda *args: payload)
            self.assertEqual(result, "API_RESPONSE_INVALID")

    def test_safe_auth_failure_output(self):
        from opensubtitles import SubtitleApiError

        def reject(*args):
            raise SubtitleApiError("API_AUTH_DENIED")

        self.assertEqual(
            smoke_api.check_api_key("private-key-value", transport=reject),
            "API_AUTH_DENIED",
        )

    def test_cli_no_secret_print(self):
        with mock.patch.dict(os.environ, {"OPENSUBTITLES_API_KEY": "private-sample-key"}):
            with mock.patch.object(smoke_api, "check_api_key", return_value="API_READONLY_SMOKE_PASS"):
                printed = io.StringIO()
                with redirect_stdout(printed):
                    self.assertEqual(smoke_api.main(), 0)
                self.assertEqual(printed.getvalue().strip(), "API_READONLY_SMOKE_PASS")
                self.assertNotIn("private-sample-key", printed.getvalue())
