from __future__ import annotations

import json
import logging
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import requests


LOGGER = logging.getLogger(__name__)


class Notifier:
    def send(self, title: str, content: str) -> None:
        raise NotImplementedError


class NotificationError(RuntimeError):
    """A delivery failure that must not be classified as a Zhengfang failure."""


class StdoutNotifier(Notifier):
    def send(self, title: str, content: str) -> None:
        LOGGER.info("通知预览 | %s\n%s", title, content)


class ShowdocNotifier(Notifier):
    def __init__(self, token: str, timeout: int):
        value = token.strip().rstrip("/")
        prefix = "https://push.showdoc.com.cn/server/api/push/"
        self.url = value if value.startswith(prefix) else f"{prefix}{value}"
        self.timeout = timeout
        self.session = requests.Session()
        self.session.trust_env = False

    def send(self, title: str, content: str) -> None:
        try:
            response = self.session.post(
                self.url,
                # ShowDoc Push reads these values from form fields. Sending JSON can
                # make the API report that title/content is missing.
                data={"title": title, "content": content},
                timeout=self.timeout,
            )
            response.raise_for_status()
        except requests.RequestException as exc:
            raise NotificationError(f"ShowDoc 推送连接失败：{exc}") from exc
        try:
            payload = response.json()
        except ValueError as exc:
            raise NotificationError("ShowDoc 返回的不是 JSON") from exc
        if isinstance(payload, dict):
            error_code = payload.get("error_code", payload.get("code"))
            if error_code not in (None, 0, "0", 200, "200"):
                raise NotificationError(f"ShowDoc 推送失败：{payload}")


class RelayNotifier(Notifier):
    """Send notification payloads to the non-VPN sidecar relay."""

    def __init__(self, url: str, timeout: int):
        self.url = url.strip()
        self.timeout = timeout
        self.session = requests.Session()
        self.session.trust_env = False

    def send(self, title: str, content: str) -> None:
        try:
            response = self.session.post(
                self.url,
                json={"title": title, "content": content},
                timeout=self.timeout + 5,
            )
            response.raise_for_status()
        except requests.RequestException as exc:
            raise NotificationError(f"微信推送中继不可用：{exc}") from exc


def serve_showdoc_relay(
    token: str, timeout: int, *, host: str = "0.0.0.0", port: int = 8765
) -> None:
    """Run an internal-only relay whose outbound traffic bypasses EasyConnect."""

    showdoc = ShowdocNotifier(token, timeout)

    class Handler(BaseHTTPRequestHandler):
        def do_POST(self) -> None:  # noqa: N802
            if self.path != "/notify":
                self.send_error(404)
                return
            try:
                length = int(self.headers.get("Content-Length", "0"))
                if length <= 0 or length > 131072:
                    raise ValueError("invalid payload length")
                payload = json.loads(self.rfile.read(length).decode("utf-8"))
                if not isinstance(payload, dict):
                    raise ValueError("payload must be an object")
                title = payload.get("title")
                content = payload.get("content")
                if not isinstance(title, str) or not isinstance(content, str):
                    raise ValueError("title and content must be strings")
            except (ValueError, UnicodeDecodeError, json.JSONDecodeError):
                self.send_error(400, "invalid notification payload")
                return

            try:
                showdoc.send(title, content)
            except NotificationError as exc:
                LOGGER.warning("ShowDoc 推送失败：%s", exc)
                self.send_error(502, "ShowDoc delivery failed")
                return
            self.send_response(204)
            self.end_headers()

        def log_message(self, format: str, *args: object) -> None:
            return

    server = ThreadingHTTPServer((host, port), Handler)
    LOGGER.info("微信推送中继已启动，监听 %s:%d", host, port)
    server.serve_forever()


def build_notifier(
    provider: str, token: str, timeout: int, relay_url: str | None = None
) -> Notifier:
    if provider == "stdout":
        return StdoutNotifier()
    if relay_url:
        return RelayNotifier(relay_url, timeout)
    return ShowdocNotifier(token, timeout)
