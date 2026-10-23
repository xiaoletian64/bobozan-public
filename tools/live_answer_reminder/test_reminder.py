import copy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from reminder import Reminder, Speaker, classify, poll_once
from proxy_addon import schema


def answer(room="12", active=True):
    return {"url": f"https://api.qianguolive.cn/qg/app/live/getLiveAnswerList/{room}",
            "body": {"code": 0, "data": {"isCanAnswer": active, "newLiveQuestionVO": [{"questionNo": 1, "title": "fixture"}]}}}


class FakeSpeaker:
    def __init__(self):
        self.messages = []
        self.fail = False

    def speak(self, text):
        if self.fail:
            raise RuntimeError("fixture failure")
        self.messages.append(text)


class Tests(unittest.TestCase):
    def setUp(self):
        self.config = {"state_file": ":memory:", "cooldown_seconds": 120, "repeat_after_seconds": 21600}
        self.speaker = FakeSpeaker()
        self.clock = 100000
        self.reminder = Reminder(self.config, self.speaker, now=lambda: self.clock)

    def test_available_and_duplicates(self):
        self.assertTrue(self.reminder.process(answer()))
        self.assertFalse(self.reminder.process(answer()))
        self.assertEqual(len(self.speaker.messages), 1)

    def test_inactive_string_false_and_empty_questions(self):
        for value in [False, "false", "0", None, {}, []]:
            self.assertIsNone(classify(answer(active=value), self.config))
        record = answer()
        record["body"]["data"]["newLiveQuestionVO"] = []
        self.assertIsNone(classify(record, self.config))

    def test_error_and_untrusted_host(self):
        record = answer()
        record["body"]["code"] = 401
        self.assertIsNone(classify(record, self.config))
        record["body"]["code"] = False
        self.assertIsNone(classify(record, self.config))
        record = answer()
        record["url"] = record["url"].replace("api.qianguolive.cn", "api.qianguolive.cn.attacker.test")
        self.assertIsNone(classify(record, self.config))

    def test_endpoint_is_exact(self):
        record = answer()
        record["url"] += "/other"
        self.assertIsNone(classify(record, self.config))

    def test_cross_signal_cooldown(self):
        self.assertTrue(self.reminder.process(answer()))
        jump = {"url": "https://api.qianguolive.cn/qg/app/live/jumpPage", "request": {"liveId": "12"}, "body": {"code": 0, "data": {"liveJumpPageEnum": "ANSWER_POPUP"}}}
        self.assertFalse(self.reminder.process(jump))

    def test_rooms_are_independent(self):
        self.assertTrue(self.reminder.process(answer("12")))
        self.assertTrue(self.reminder.process(answer("13")))

    def test_failure_retries(self):
        self.speaker.fail = True
        with self.assertRaises(RuntimeError):
            self.reminder.process(answer())
        self.speaker.fail = False
        self.assertTrue(self.reminder.process(answer()))

    def test_persistent_state(self):
        with tempfile.TemporaryDirectory() as directory:
            cfg = dict(self.config, state_file=str(Path(directory) / "state.sqlite3"))
            first = Reminder(cfg, self.speaker, now=lambda: self.clock)
            self.assertTrue(first.process(answer()))
            second = Reminder(cfg, self.speaker, now=lambda: self.clock)
            self.assertFalse(second.process(answer()))
            self.assertEqual(Path(cfg["state_file"]).stat().st_mode & 0o777, 0o600)

    def test_next_session(self):
        self.assertTrue(self.reminder.process(answer()))
        self.clock += 21601
        self.assertTrue(self.reminder.process(answer()))

    def test_im_exact_marker_and_group(self):
        record = {"url": "wss://ims.qianguolive.cn/ws", "kind": "im", "body": {"payload": {"text": "hcj_im_token_ANSWER"}, "to": "im_shop_group12"}}
        self.assertTrue(self.reminder.process(record))
        record["body"]["payload"]["text"] += " fake"
        self.assertIsNone(classify(record, self.config))
        record["body"]["payload"]["text"] = "hcj_im_token_ANSWER"
        record["body"]["to"] = "unrelated"
        self.assertIsNone(classify(record, self.config))

    def test_first_app_unknown_is_not_invented(self):
        record = {"url": "https://liveapi.njyqkj0ksyz.com/unknown", "body": {"answer": True, "message": "开始答题"}}
        self.assertIsNone(classify(record, self.config))

    def test_lebogou_active_activity_and_end(self):
        record = {"url": "https://live-gw.njyqkj0ksyz.com/generic/v1/h5/answer/get_question_list", "request": {"topicId": "9"}, "body": {"code": 0, "isok": True, "dataObj": {"answerReward": {"id": 7, "state": 1}, "answered": False}}}
        self.assertTrue(self.reminder.process(record))
        self.assertIn("答题条件", self.speaker.messages[-1])
        self.assertFalse(self.reminder.process(record))
        record["body"]["dataObj"]["answerReward"]["state"] = 2
        self.assertIsNone(classify(record, self.config))

    def test_lebogou_already_answered_and_wrong_endpoint(self):
        record = {"url": "https://live-gw.njyqkj0ksyz.com/generic/v1/h5/answer/get_question_list", "request": {"topicId": "9"}, "body": {"code": 0, "isok": True, "dataObj": {"answerReward": {"id": 7, "state": 1}, "answered": True}}}
        self.assertIsNone(classify(record, self.config))
        record["body"]["dataObj"]["answered"] = False
        record["url"] = record["url"].replace("get_question_list", "submit_answer")
        self.assertIsNone(classify(record, self.config))

    def test_lebogou_im_start_end_and_invalid_message(self):
        record = {"kind": "im", "url": "wss://wx.7948.cn/fixture", "body": {"Types": "正常消息", "Msg": {"TopicId": "1", "msgtype": 511, "content": json.dumps({"answerReward": {"id": 8, "state": 1}})}}}
        self.assertEqual(classify(record, self.config)["signal"], "activity_started")
        record["body"]["Msg"]["content"] = json.dumps({"answerReward": {"id": 8, "state": 2}})
        self.assertIsNone(classify(record, self.config))
        record["body"]["Msg"]["msgtype"] = 790
        self.assertEqual(classify(record, self.config)["signal"], "question_shown")
        record["body"]["Msg"]["msgtype"] = 791
        self.assertIsNone(classify(record, self.config))

    def test_first_app_rule_is_strict_and_host_scoped(self):
        cfg = copy.deepcopy(self.config)
        cfg["lebogou_rules"] = [{"host": "liveapi.njyqkj0ksyz.com", "path": "/fixture", "status_field": "data.active", "status_value": True, "room_field": "data.room"}]
        record = {"url": "https://liveapi.njyqkj0ksyz.com/fixture", "body": {"data": {"active": True, "room": "1"}}}
        self.assertEqual(classify(record, cfg)["room"], "1")
        record["body"]["data"]["active"] = "true"
        self.assertIsNone(classify(record, cfg))

    def test_schema_does_not_store_values(self):
        encoded = json.dumps(schema({"token": "SECRET", "data": [{"phone": "13800000000"}]}))
        self.assertNotIn("SECRET", encoded)
        self.assertNotIn("13800000000", encoded)

    def test_speaker_requires_explicit_device(self):
        with self.assertRaises(ValueError):
            Speaker({"type": "miservice"}).speak("test")

    def test_both_pollers_use_only_status_endpoints(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "headers.json"
            path.write_text(json.dumps({"memberToken": "fixture", "buid": "fixture"}))
            cfg = dict(self.config,
                       qianguo={"live_id": "12", "headers_file": str(path)},
                       lebogou={"topic_id": "9", "headers_file": str(path)})
            with patch("reminder.urlopen") as opener:
                response = opener.return_value.__enter__.return_value
                response.read.return_value = json.dumps(answer()["body"]).encode()
                self.assertTrue(poll_once(cfg, self.reminder, "qianguo"))
                self.assertEqual(opener.call_args.args[0].get_method(), "GET")
                self.assertTrue(opener.call_args.args[0].full_url.endswith("getLiveAnswerList/12"))
                response.read.return_value = json.dumps({"code": 0, "isok": True, "dataObj": {"answerReward": {"id": 7, "state": 1}, "answered": False}}).encode()
                self.assertTrue(poll_once(cfg, self.reminder, "lebogou"))
                request = opener.call_args.args[0]
                self.assertEqual(request.get_method(), "POST")
                self.assertTrue(request.full_url.endswith("get_question_list"))
                self.assertEqual(request.data, b"topicId=9")

    def test_failed_login_is_not_treated_as_inactive(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "headers.json"
            path.write_text(json.dumps({"memberToken": "fixture"}))
            cfg = dict(self.config, qianguo={"live_id": "12", "headers_file": str(path)})
            with patch("reminder.urlopen") as opener:
                opener.return_value.__enter__.return_value.read.return_value = b'{"code":401}'
                with self.assertRaises(RuntimeError):
                    poll_once(cfg, self.reminder)

    def test_speaker_uses_single_device_helper_and_checks_failure(self):
        with patch("reminder.subprocess.run") as run:
            run.return_value.returncode = 0
            Speaker({"type": "miservice", "device_id": "fixture-speaker"}).speak("test")
            args, kwargs = run.call_args
            self.assertTrue(args[0][1].endswith("speaker.py"))
            self.assertEqual(json.loads(kwargs["input"])["device_id"], "fixture-speaker")
            run.return_value.returncode = 1
            with self.assertRaises(RuntimeError):
                Speaker({"type": "miservice", "device_id": "fixture-speaker"}).speak("test")


if __name__ == "__main__":
    unittest.main()
