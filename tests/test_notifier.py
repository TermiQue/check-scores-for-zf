import unittest

from zfcheck.notifier import ShowdocNotifier


class ShowdocNotifierTests(unittest.TestCase):
    def test_accepts_token(self):
        notifier = ShowdocNotifier("abc123", 20)
        self.assertEqual(
            "https://push.showdoc.com.cn/server/api/push/abc123", notifier.url
        )

    def test_accepts_full_url(self):
        url = "https://push.showdoc.com.cn/server/api/push/abc123"
        notifier = ShowdocNotifier(url, 20)
        self.assertEqual(url, notifier.url)


if __name__ == "__main__":
    unittest.main()
