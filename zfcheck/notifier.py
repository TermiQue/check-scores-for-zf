from __future__ import annotations

import logging

import requests


LOGGER = logging.getLogger(__name__)


class Notifier:
    def send(self, title: str, content: str) -> None:
        raise NotImplementedError


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
        response = self.session.post(
            self.url,
            json={"title": title, "content": content},
            timeout=self.timeout,
        )
        response.raise_for_status()
        try:
            payload = response.json()
        except ValueError as exc:
            raise RuntimeError("ShowDoc 返回的不是 JSON") from exc
        if isinstance(payload, dict):
            error_code = payload.get("error_code", payload.get("code"))
            if error_code not in (None, 0, "0", 200, "200"):
                raise RuntimeError(f"ShowDoc 推送失败: {payload}")


def build_notifier(provider: str, token: str, timeout: int) -> Notifier:
    if provider == "stdout":
        return StdoutNotifier()
    return ShowdocNotifier(token, timeout)
