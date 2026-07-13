import base64
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

from zfcheck.service import ScoreChecker
from zfcheck.state import StateStore
from zfcheck.model import normalize_courses


class CaptchaClient:
    def __init__(self):
        self.submitted = None
        self.cookies = {}

    def login(self, username, password):
        return {
            "code": 1001,
            "data": {
                "sid": username,
                "csrf_token": "csrf",
                "cookies": {"route": "route"},
                "password": password,
                "modulus": "modulus",
                "exponent": "exponent",
                "kaptcha_pic": base64.b64encode(b"png-data").decode(),
                "timestamp": 1,
            },
        }

    def login_with_kaptcha(self, **kwargs):
        self.submitted = kwargs
        self.cookies = {"JSESSIONID": "session", "route": "route"}
        return {"code": 1000, "msg": "ok"}


class RetryCaptchaClient(CaptchaClient):
    def __init__(self):
        super().__init__()
        self.login_count = 0
        self.submit_count = 0

    def login(self, username, password):
        self.login_count += 1
        return super().login(username, password)

    def login_with_kaptcha(self, **kwargs):
        self.submit_count += 1
        self.submitted = kwargs
        if self.submit_count == 1:
            return {"code": 1002, "msg": "验证码输入错误"}
        self.cookies = {"JSESSIONID": "session", "route": "route"}
        return {"code": 1000, "msg": "ok"}


class InteractiveLoginTests(unittest.TestCase):
    def test_gui_captcha_answer_file_is_consumed(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            answer_path = Path(temp_dir) / "captcha-answer.txt"
            answer_path.write_text("AB12CD\n", encoding="utf-8")
            checker = object.__new__(ScoreChecker)

            with patch.dict(
                "os.environ",
                {
                    "ZF_CAPTCHA_INPUT_FILE": str(answer_path),
                    "ZF_CAPTCHA_INPUT_TIMEOUT_SECONDS": "1",
                },
            ):
                answer = checker._read_captcha_answer(1, 5)

            self.assertEqual("AB12CD", answer)
            self.assertFalse(answer_path.exists())

    def test_captcha_is_submitted_on_the_same_client(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            checker = object.__new__(ScoreChecker)
            checker.config = SimpleNamespace(
                username="student",
                password="password",
                data_dir=Path(temp_dir),
            )
            checker.client = CaptchaClient()
            checker.logged_in = False
            checker.store = SimpleNamespace(set=lambda key, value: None)

            with patch("builtins.input", return_value="AB12"):
                checker._login(interactive=True)

            self.assertTrue(checker.logged_in)
            self.assertEqual("AB12", checker.client.submitted["kaptcha"])
            self.assertEqual("csrf", checker.client.submitted["csrf_token"])
            self.assertTrue(checker.client.submitted["use_encryption"])
            self.assertTrue((Path(temp_dir) / "kaptcha.png").exists())

    def test_plain_password_compatibility_mode(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            checker = object.__new__(ScoreChecker)
            checker.config = SimpleNamespace(
                username="student",
                password="password",
                data_dir=Path(temp_dir),
            )
            checker.client = CaptchaClient()
            checker.logged_in = False
            checker.store = SimpleNamespace(set=lambda key, value: None)

            with patch("builtins.input", return_value="AB12"), patch.dict(
                "os.environ", {"ZF_CAPTCHA_PASSWORD_MODE": "plain"}
            ):
                checker._login(interactive=True)

            self.assertFalse(checker.client.submitted["use_encryption"])

    def test_wrong_captcha_fetches_a_new_image_and_retries(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            checker = object.__new__(ScoreChecker)
            checker.config = SimpleNamespace(
                username="student",
                password="password",
                data_dir=Path(temp_dir),
            )
            checker.client = RetryCaptchaClient()
            checker.logged_in = False
            checker.store = SimpleNamespace(set=lambda key, value: None)

            with patch("builtins.input", side_effect=["WRONG", "RIGHT"]):
                checker._login(interactive=True)

            self.assertTrue(checker.logged_in)
            self.assertEqual(2, checker.client.login_count)
            self.assertEqual(2, checker.client.submit_count)
            self.assertEqual("RIGHT", checker.client.submitted["kaptcha"])


class NullNotifier:
    def send(self, title, content):
        pass


class CaptureNotifier:
    def __init__(self):
        self.messages = []

    def send(self, title, content):
        self.messages.append((title, content))


class InitialCheckTests(unittest.TestCase):
    def test_first_check_pushes_all_courses_before_saving_baseline(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            checker = object.__new__(ScoreChecker)
            checker.config = SimpleNamespace(data_dir=Path(temp_dir))
            checker.store = StateStore(Path(temp_dir))
            checker.notifier = CaptureNotifier()
            checker.fetch_courses = lambda: [
                {"class_id": "1", "title": "高等数学", "grade": "85"},
                {"class_id": "2", "title": "大学英语", "grade": "90"},
            ]

            try:
                checker.check_once()
                snapshot = checker.store.get_snapshot()
            finally:
                checker.store.close()

            self.assertEqual(1, len(checker.notifier.messages))
            title, content = checker.notifier.messages[0]
            self.assertEqual("正方教务首次成绩同步", title)
            self.assertIn("高等数学", content)
            self.assertIn("大学英语", content)
            self.assertEqual(2, len(snapshot))

    def test_changed_check_pushes_full_snapshot_with_labels(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            checker = object.__new__(ScoreChecker)
            checker.config = SimpleNamespace(data_dir=Path(temp_dir))
            checker.store = StateStore(Path(temp_dir))
            checker.notifier = CaptureNotifier()
            checker.store.set_snapshot(
                normalize_courses(
                    [
                    {
                        "class_id": "1",
                        "title": "高等数学",
                        "grade": "80",
                        "submission_time": "2026-01-01 10:00:00",
                    },
                    {
                        "class_id": "3",
                        "title": "历史课程",
                        "grade": "70",
                        "submission_time": "2025-01-01 10:00:00",
                    },
                    ]
                )
            )
            checker.fetch_courses = lambda: [
                {
                    "class_id": "1",
                    "title": "高等数学",
                    "grade": "85",
                    "submission_time": "2026-07-01 10:00:00",
                },
                {
                    "class_id": "2",
                    "title": "大学英语",
                    "grade": "90",
                    "submission_time": "2026-07-02 10:00:00",
                },
                {
                    "class_id": "3",
                    "title": "历史课程",
                    "grade": "70",
                    "submission_time": "2025-01-01 10:00:00",
                },
            ]

            try:
                checker.check_once()
            finally:
                checker.store.close()

            self.assertEqual(1, len(checker.notifier.messages))
            title, content = checker.notifier.messages[0]
            self.assertIn("新增 1", title)
            self.assertIn("更新 1", title)
            self.assertIn("类型：新增\n课程：大学英语", content)
            self.assertIn("类型：更新\n课程：高等数学", content)
            self.assertIn("课程：历史课程", content)
            self.assertLess(content.index("大学英语"), content.index("高等数学"))

    def test_unchanged_check_does_not_push(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            checker = object.__new__(ScoreChecker)
            checker.config = SimpleNamespace(data_dir=Path(temp_dir))
            checker.store = StateStore(Path(temp_dir))
            checker.notifier = CaptureNotifier()
            courses = [{"class_id": "1", "title": "高等数学", "grade": "85"}]
            checker.store.set_snapshot(normalize_courses(courses))
            checker.fetch_courses = lambda: courses
            try:
                checker.check_once()
            finally:
                checker.store.close()
            self.assertEqual([], checker.notifier.messages)


class FailureNotificationTests(unittest.TestCase):
    def _checker(self, temp_dir):
        checker = object.__new__(ScoreChecker)
        checker.config = SimpleNamespace(
            data_dir=Path(temp_dir),
            failure_alert_cooldown_seconds=21600,
        )
        checker.store = StateStore(Path(temp_dir))
        checker.notifier = CaptureNotifier()
        return checker

    def test_session_expiry_has_actionable_recovery(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            checker = self._checker(temp_dir)
            try:
                checker._notify_failure("教务登录会话已过期，需要重新输入图片验证码")
            finally:
                checker.store.close()
            title, content = checker.notifier.messages[0]
            self.assertIn("正方登录已过期", title)
            self.assertIn("windows-start.cmd", content)

    @patch("zfcheck.service.vpn_tunnel_connected", return_value=False)
    def test_missing_tunnel_is_reported_as_vpn_failure(self, _mock_tunnel):
        with tempfile.TemporaryDirectory() as temp_dir:
            checker = self._checker(temp_dir)
            try:
                checker._notify_failure("获取成绩失败（2333）：连接超时")
            finally:
                checker.store.close()
            title, content = checker.notifier.messages[0]
            self.assertIn("VPN 已断开", title)
            self.assertIn("短信验证", content)

    @patch("zfcheck.service.vpn_tunnel_connected", return_value=True)
    def test_live_tunnel_is_reported_as_zhengfang_failure(self, _mock_tunnel):
        with tempfile.TemporaryDirectory() as temp_dir:
            checker = self._checker(temp_dir)
            try:
                checker._notify_failure("获取成绩失败（2333）：连接超时")
            finally:
                checker.store.close()
            title, content = checker.notifier.messages[0]
            self.assertIn("正方教务不可用", title)
            self.assertIn("自动重试", content)


class SessionPersistenceTests(unittest.TestCase):
    def test_saved_cookies_are_loaded_by_a_new_checker(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            config = SimpleNamespace(
                username="student",
                password="password",
                data_dir=Path(temp_dir),
                url="http://example.invalid/",
                request_timeout_seconds=20,
                proxy=None,
                push_provider="stdout",
                push_token="",
            )
            first = ScoreChecker(config, notifier=NullNotifier())
            first.client.cookies = {"JSESSIONID": "session", "route": "route"}
            first._save_cookies()
            first.close()

            second = ScoreChecker(config, notifier=NullNotifier())
            try:
                self.assertTrue(second.logged_in)
                self.assertEqual("session", second.client.cookies["JSESSIONID"])
            finally:
                second.close()


if __name__ == "__main__":
    unittest.main()
