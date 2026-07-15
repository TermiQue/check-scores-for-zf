from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path


def _read_secret(name: str, *, required: bool = True) -> str:
    file_name = os.getenv(f"{name}_FILE", "").strip()
    if file_name:
        try:
            value = Path(file_name).read_text(encoding="utf-8").strip()
        except OSError as exc:
            raise ValueError(f"无法读取 {name}_FILE: {exc}") from exc
    else:
        value = os.getenv(name, "").strip()
    if required and not value:
        raise ValueError(f"缺少配置 {name} 或 {name}_FILE")
    return value


def _positive_int(name: str, default: int) -> int:
    raw = os.getenv(name, str(default)).strip()
    try:
        value = int(raw)
    except ValueError as exc:
        raise ValueError(f"{name} 必须是整数") from exc
    if value <= 0:
        raise ValueError(f"{name} 必须大于 0")
    return value


@dataclass(frozen=True)
class Config:
    url: str
    username: str
    password: str
    push_provider: str
    push_token: str
    push_relay_url: str | None
    data_dir: Path
    proxy: str | None
    interval_seconds: int
    heartbeat_interval_seconds: int
    jitter_seconds: int
    failure_alert_cooldown_seconds: int
    request_timeout_seconds: int

    @classmethod
    def from_env(cls, *, require_push: bool = True) -> "Config":
        url = os.getenv("ZF_URL", "http://jwxt.cumt.edu.cn/jwglxt/").strip()
        if not url.endswith("/"):
            url += "/"

        provider = os.getenv("PUSH_PROVIDER", "showdoc").strip().lower()
        if provider not in {"showdoc", "stdout"}:
            raise ValueError("PUSH_PROVIDER 仅支持 showdoc 或 stdout")

        token_required = require_push and provider == "showdoc"
        token = _read_secret("PUSH_TOKEN", required=token_required)
        proxy = os.getenv("ZF_PROXY", "").strip() or None

        return cls(
            url=url,
            username=_read_secret("ZF_USERNAME"),
            password=_read_secret("ZF_PASSWORD"),
            push_provider=provider,
            push_token=token,
            push_relay_url=os.getenv("PUSH_RELAY_URL", "").strip() or None,
            data_dir=Path(os.getenv("DATA_DIR", "/data")),
            proxy=proxy,
            interval_seconds=_positive_int("CHECK_INTERVAL_SECONDS", 1800),
            heartbeat_interval_seconds=_positive_int(
                "HEARTBEAT_INTERVAL_SECONDS", 300
            ),
            jitter_seconds=_positive_int("CHECK_JITTER_SECONDS", 120),
            failure_alert_cooldown_seconds=_positive_int(
                "FAILURE_ALERT_COOLDOWN_SECONDS", 21600
            ),
            request_timeout_seconds=_positive_int("REQUEST_TIMEOUT_SECONDS", 20),
        )
