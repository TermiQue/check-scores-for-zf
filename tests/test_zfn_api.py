import unittest

import requests

from scripts.zfn_api import Client


class FakeResponse:
    def __init__(self, *, text="", content=b"", payload=None, status_code=200):
        self.text = text
        self.content = content
        self._payload = payload
        self.status_code = status_code

    def json(self):
        return self._payload


class RotatingCaptchaSession:
    def __init__(self, client):
        self.client = client
        self.cookies = requests.cookies.RequestsCookieJar()
        self.keep_alive = False
        self.post_cookie_snapshot = None
        self.post_cookie_entries = None
        self.post_received_explicit_cookies = None
        self.post_data = None
        self.logout_called = False

    def _rotate_session(self, value):
        self.cookies.clear()
        self.cookies.set(
            "JSESSIONID",
            value,
            domain="example.invalid",
            path="/jwglxt",
        )

    def get(self, url, **kwargs):
        if url == self.client.login_url:
            self._rotate_session("login-session")
            return FakeResponse(
                text=(
                    '<html><input id="csrftoken" value="csrf">'
                    '<input id="yzm" value=""></html>'
                )
            )
        if url == self.client.key_url:
            self._rotate_session("key-session")
            return FakeResponse(payload={"modulus": "modulus", "exponent": "exponent"})
        if url == self.client.kaptcha_url:
            self._rotate_session("captcha-session")
            return FakeResponse(content=b"captcha-image")
        raise AssertionError(f"unexpected GET {url}")

    def post(self, url, **kwargs):
        if url == self.client.logout_url:
            self.logout_called = True
            raise AssertionError("captcha login must not rotate the session via logout")
        self.post_cookie_snapshot = self.cookies.get_dict()
        self.post_cookie_entries = list(self.cookies)
        self.post_received_explicit_cookies = kwargs.get("cookies")
        self.post_data = kwargs.get("data")
        self._rotate_session("authenticated-session")
        return FakeResponse(text="<html><body>ok</body></html>")


class CaptchaCookieRotationTests(unittest.TestCase):
    def test_captcha_uses_cookie_created_by_the_image_request(self):
        client = Client(cookies={}, base_url="http://example.invalid/jwglxt/")
        session = RotatingCaptchaSession(client)
        client.sess = session

        result = client.login("student", "password")

        self.assertEqual(1001, result["code"])
        self.assertEqual("captcha-session", result["data"]["cookies"]["JSESSIONID"])

        verify_data = dict(result["data"])
        verify_data.pop("kaptcha_pic")
        verified = client.login_with_kaptcha(
            kaptcha="AB12",
            use_encryption=False,
            **verify_data,
        )

        self.assertEqual(1000, verified["code"])
        self.assertEqual("captcha-session", session.post_cookie_snapshot["JSESSIONID"])
        self.assertEqual(1, len(session.post_cookie_entries))
        self.assertEqual("example.invalid", session.post_cookie_entries[0].domain)
        self.assertIsNone(session.post_received_explicit_cookies)
        self.assertFalse(session.logout_called)
        field_names = [name for name, _ in session.post_data]
        self.assertEqual(2, field_names.count("mm"))
        self.assertEqual(
            ["password", "password"],
            [value for name, value in session.post_data if name == "mm"],
        )


if __name__ == "__main__":
    unittest.main()
