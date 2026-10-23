import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from session_store import ReauthenticationRequired, load_private, renew, save_private


class SessionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        directory = Path(self.temp.name)
        self.settings = {"headers_file": str(directory / "headers.json"), "session_file": str(directory / "session.json"), "merchant_id": "m", "live_id": "l"}
        save_private(self.settings["headers_file"], {"memberToken": "old", "buid": "encrypted"})
        save_private(self.settings["session_file"], {"encryptUserId": "encrypted", "openIdType": "fixture"})

    def test_permissions_and_atomic_save(self):
        self.assertEqual(Path(self.settings["headers_file"]).stat().st_mode & 0o777, 0o600)
        self.assertEqual(load_private(self.settings["headers_file"])["memberToken"], "old")

    def test_lebogou_renewal_and_hourly_throttle(self):
        with patch("session_store.urlopen") as call:
            call.return_value.__enter__.return_value.read.return_value = b'{"isok":true,"dataObj":{"token":"new","tokenExpires":"fixture"}}'
            self.assertTrue(renew("lebogou", self.settings))
            self.assertEqual(load_private(self.settings["headers_file"])["Authorization"], "Bearer new")
            self.assertFalse(renew("lebogou", self.settings))
            self.assertEqual(call.call_count, 1)

    def test_qianguo_silent_login_rotates_token(self):
        with patch("session_store.urlopen") as call:
            call.return_value.__enter__.return_value.read.return_value = b'{"code":0,"data":{"memberToken":"rotated"}}'
            self.assertTrue(renew("qianguo", self.settings))
            request = call.call_args.args[0]
            self.assertEqual(json.loads(request.data)["memberToken"], "old")
            self.assertEqual(load_private(self.settings["headers_file"])["memberToken"], "rotated")

    def test_rejection_preserves_token(self):
        with patch("session_store.urlopen") as call:
            call.return_value.__enter__.return_value.read.return_value = b'{"code":401}'
            with self.assertRaises(ReauthenticationRequired):
                renew("qianguo", self.settings)
            self.assertEqual(load_private(self.settings["headers_file"])["memberToken"], "old")

    def test_no_session_does_not_make_requests(self):
        with patch("session_store.urlopen") as call:
            self.assertFalse(renew("lebogou", {}))
            call.assert_not_called()
