import unittest
from unittest.mock import Mock

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

    def test_send_uses_showdoc_form_fields(self):
        notifier = ShowdocNotifier("abc123", 20)
        response = Mock()
        response.json.return_value = {"error_code": 0}
        notifier.session.post = Mock(return_value=response)

        notifier.send("连接断开", "累计检测 3 次")

        notifier.session.post.assert_called_once_with(
            notifier.url,
            data={"title": "连接断开", "content": "累计检测 3 次"},
            timeout=20,
        )
        response.raise_for_status.assert_called_once_with()


if __name__ == "__main__":
    unittest.main()
