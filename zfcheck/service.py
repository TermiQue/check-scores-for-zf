from __future__ import annotations

import base64
import json
import logging
import os
import random
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from scripts.zfn_api import Client

from .config import Config
from .model import (
    diff_snapshots,
    course_key,
    format_full_snapshot,
    format_initial_snapshot,
    normalize_courses,
    snapshot_hash,
)
from .notifier import Notifier, build_notifier
from .state import StateStore


LOGGER = logging.getLogger(__name__)


class CheckError(RuntimeError):
    pass


def vpn_tunnel_connected() -> bool:
    """Detect the EasyConnect tunnel from the shared network namespace."""
    if not Path("/sys/class/net/tun0").exists():
        return False
    try:
        lines = Path("/proc/net/route").read_text(encoding="ascii").splitlines()[1:]
    except OSError:
        return False
    return any(line.split()[0] == "tun0" for line in lines if line.split())


def format_monitoring_duration(elapsed_seconds: int) -> str:
    """Format an incident duration for the compact WeChat alert title."""
    elapsed_seconds = max(0, elapsed_seconds)
    if elapsed_seconds < 60:
        return "不足 1 分钟"

    total_minutes = elapsed_seconds // 60
    days, remaining_minutes = divmod(total_minutes, 24 * 60)
    hours, minutes = divmod(remaining_minutes, 60)
    if days:
        return f"{days} 天 {hours} 小时" if hours else f"{days} 天"
    if hours:
        return f"{hours} 小时 {minutes} 分钟" if minutes else f"{hours} 小时"
    return f"{minutes} 分钟"


class ScoreChecker:
    def __init__(self, config: Config, *, notifier: Notifier | None = None):
        self.config = config
        self.store = StateStore(config.data_dir)
        self.notifier = notifier or build_notifier(
            config.push_provider, config.push_token, config.request_timeout_seconds
        )
        saved_cookies = self._load_cookies()
        self.client = self._new_client(cookies=saved_cookies)
        self.logged_in = bool(saved_cookies)

    def _load_cookies(self) -> dict[str, str]:
        raw = self.store.get("login_cookies")
        if not raw:
            return {}
        try:
            value = json.loads(raw)
        except (TypeError, ValueError):
            self.store.delete("login_cookies")
            return {}
        return value if isinstance(value, dict) else {}

    def _save_cookies(self) -> None:
        self.store.set(
            "login_cookies",
            json.dumps(self.client.cookies, ensure_ascii=True, sort_keys=True),
        )

    def _new_client(self, *, cookies: dict[str, str] | None = None) -> Client:
        client = Client(
            cookies=cookies or {},
            base_url=self.config.url,
            timeout=self.config.request_timeout_seconds,
        )
        if self.config.proxy:
            client.sess.proxies.update(
                {"http": self.config.proxy, "https": self.config.proxy}
            )
        return client

    def close(self) -> None:
        self.store.close()

    def _save_captcha(self, login_result: dict[str, Any]) -> None:
        encoded = login_result.get("data", {}).get("kaptcha_pic")
        if not encoded:
            return
        path = self.config.data_dir / "kaptcha.png"
        path.write_bytes(base64.b64decode(encoded))
        LOGGER.warning("教务系统要求图片验证码，已保存到 %s", path)

    def _captcha_input_path(self) -> Path | None:
        value = os.getenv("ZF_CAPTCHA_INPUT_FILE", "").strip()
        return Path(value) if value else None

    def _read_captcha_answer(self, attempt: int, max_attempts: int) -> str:
        input_path = self._captcha_input_path()
        if input_path is None:
            return input(
                f"请输入验证码（第 {attempt}/{max_attempts} 次）："
            ).strip()

        try:
            timeout = int(os.getenv("ZF_CAPTCHA_INPUT_TIMEOUT_SECONDS", "300"))
        except ValueError as exc:
            raise CheckError("ZF_CAPTCHA_INPUT_TIMEOUT_SECONDS 必须是整数") from exc
        LOGGER.info("等待 Windows 验证码窗口输入，最长等待 %d 秒", timeout)
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            try:
                answer = input_path.read_text(encoding="utf-8").strip()
            except FileNotFoundError:
                time.sleep(0.2)
                continue
            except OSError as exc:
                raise CheckError(f"读取验证码输入文件失败：{exc}") from exc
            try:
                input_path.unlink(missing_ok=True)
            except OSError:
                LOGGER.warning("无法删除验证码输入文件 %s", input_path)
            if answer == "__CANCEL__":
                raise CheckError("用户取消了验证码输入")
            return answer
        raise CheckError("等待验证码输入超时，请重新运行 windows-launcher.cmd")

    def _login(self, *, interactive: bool = False) -> None:
        result = self.client.login(self.config.username, self.config.password)
        attempt = 0
        try:
            max_attempts = int(os.getenv("ZF_CAPTCHA_MAX_ATTEMPTS", "5"))
        except ValueError as exc:
            raise CheckError("ZF_CAPTCHA_MAX_ATTEMPTS 必须是整数") from exc
        if max_attempts <= 0:
            raise CheckError("ZF_CAPTCHA_MAX_ATTEMPTS 必须大于 0")

        while result.get("code") == 1001:
            input_path = self._captcha_input_path()
            if input_path is not None:
                input_path.unlink(missing_ok=True)
            self._save_captcha(result)
            if not interactive:
                raise CheckError("教务系统要求图片验证码，请查看 /data/kaptcha.png")

            attempt += 1
            answer = self._read_captcha_answer(attempt, max_attempts)
            if not answer:
                raise CheckError("未输入图片验证码")
            verify_data = dict(result.get("data", {}))
            verify_data.pop("kaptcha_pic", None)
            password_mode = os.getenv("ZF_CAPTCHA_PASSWORD_MODE", "encrypted").strip().lower()
            if password_mode not in {"encrypted", "plain"}:
                raise CheckError("ZF_CAPTCHA_PASSWORD_MODE 仅支持 encrypted 或 plain")
            LOGGER.info("验证码登录密码提交模式：%s", password_mode)
            verified = self.client.login_with_kaptcha(
                kaptcha=answer,
                use_encryption=password_mode == "encrypted",
                **verify_data,
            )
            if isinstance(verified, dict) and verified.get("code") == 1000:
                self.logged_in = True
                self._save_cookies()
                return

            message = (
                verified.get("msg", "未知错误")
                if isinstance(verified, dict)
                else "接口未返回结果"
            )
            if "验证码" not in message or attempt >= max_attempts:
                raise CheckError(f"验证码登录失败：{message}")

            LOGGER.warning(
                "验证码输入错误，正在自动获取一张新验证码"
            )
            result = self.client.login(self.config.username, self.config.password)

        if result.get("code") != 1000:
            raise CheckError(
                f"教务登录失败（{result.get('code')}）：{result.get('msg', '未知错误')}"
            )
        self.logged_in = True
        self._save_cookies()

    def fetch_courses(self, *, interactive: bool = False) -> list[dict[str, Any]]:
        if not self.logged_in:
            self._login(interactive=interactive)
        result = self.client.get_grade()
        if result.get("code") == 1006:
            self.store.delete("login_cookies")
            self.client = self._new_client()
            self.logged_in = False
            self._login(interactive=interactive)
            result = self.client.get_grade()
        if result.get("code") != 1000:
            raise CheckError(
                f"获取成绩失败（{result.get('code')}）：{result.get('msg', '未知错误')}"
            )
        courses = result.get("data", {}).get("courses")
        if not isinstance(courses, list):
            raise CheckError("成绩接口返回格式异常")
        return courses

    def probe(self, *, interactive: bool = False) -> int:
        courses = self.fetch_courses(interactive=interactive)
        LOGGER.info("POC 成功：登录正常，成绩接口返回 %d 门课程", len(courses))
        return len(courses)

    def test_notification(self) -> None:
        self.notifier.send(
            "成绩推送测试",
            "Windows Docker 成绩检查服务的微信推送配置正常。",
        )
        LOGGER.info("测试通知已发送")

    def heartbeat(self) -> None:
        if not self.logged_in:
            LOGGER.warning("会话心跳跳过：当前没有已登录会话")
            return
        result = self.client.get_info()
        if result.get("code") == 1006:
            self.store.delete("login_cookies")
            self.client = self._new_client()
            self.logged_in = False
            raise CheckError("教务登录会话已过期，需要重新输入图片验证码")
        if result.get("code") != 1000:
            raise CheckError(
                f"会话心跳失败（{result.get('code')}）：{result.get('msg', '未知错误')}"
            )
        current_cookies = self.client.sess.cookies.get_dict()
        if current_cookies:
            self.client.cookies.update(current_cookies)
            self._save_cookies()
        LOGGER.info("教务登录会话心跳正常")

    def _notify_failure(self, message: str) -> None:
        if any(text in message for text in ("验证码", "登录会话已过期", "未登录")):
            kind = "session"
            connection_name = "正方系统"
            summary = "正方登录 Cookie 已失效，需要重新完成图片验证码。"
            recovery = (
                "恢复方法：在 Windows 项目目录双击 windows-launcher.cmd，"
                "按提示完成验证码，服务会自动恢复。"
            )
        elif (
            os.getenv("ZF_NETWORK_MODE", "vpn").strip().lower() == "vpn"
            and not vpn_tunnel_connected()
        ):
            kind = "vpn"
            connection_name = "VPN"
            summary = "未检测到 EasyConnect 的 tun0 隧道或 VPN 路由。"
            recovery = (
                "恢复方法：双击 windows-launcher.cmd，在 EasyConnect 页面重新登录并完成短信验证。"
            )
        elif any(text in message for text in ("教务", "成绩", "心跳", "连接", "超时")):
            kind = "zhengfang"
            connection_name = "正方系统"
            summary = "VPN 隧道仍存在，但正方页面或接口未正常响应。"
            recovery = (
                "恢复方法：通常无需重新配置，服务会自动重试；若持续失败，"
                "请双击 windows-launcher.cmd 重新验证连接。"
            )
        else:
            kind = "unknown"
            connection_name = "服务"
            summary = "服务遇到尚未分类的异常。"
            recovery = "恢复方法：查看 checker 日志，并重新运行 windows-launcher.cmd。"

        now = int(time.time())
        previous_kind = self.store.get("failure_kind")
        try:
            previous_started_at = int(self.store.get("failure_started_at") or str(now))
        except ValueError:
            previous_started_at = now
        started_at = previous_started_at if previous_kind == kind else now
        if started_at > now:
            started_at = now
        monitoring_duration = format_monitoring_duration(now - started_at)
        title = (
            "成绩检查出现未知错误"
            if kind == "unknown"
            else (
                f"{connection_name}连接断开，需要手动重启，"
                f"累计监测{monitoring_duration}"
            )
        )
        # Start timing at the first failure of this kind, including failures
        # whose WeChat notification cannot be delivered. The alert timestamp is
        # still written only after a successful push, so delivery is retried.
        self.store.set("failure_kind", kind)
        self.store.set("failure_started_at", str(started_at))
        self.store.delete("failure_detection_count")  # Migrate older state.
        self.store.set("failure_title", title)
        last = int(self.store.get(f"last_failure_alert_at:{kind}") or "0")
        if (
            previous_kind == kind
            and last > 0
            and now - last < self.config.failure_alert_cooldown_seconds
        ):
            return
        self.notifier.send(
            title,
            "\n".join(
                (
                    summary,
                    f"时间：{datetime.now().astimezone().strftime('%Y-%m-%d %H:%M:%S')}",
                    f"错误详情：{message}",
                    recovery,
                    "系统仍会按原计划自动重试。",
                )
            ),
        )
        self.store.set(f"last_failure_alert_at:{kind}", str(now))
        self.store.set("failure_active", "1")

    def _notify_recovery(self) -> None:
        if self.store.get("failure_active") != "1":
            return
        previous = self.store.get("failure_title") or "此前故障"
        try:
            self.notifier.send(
                "成绩检查已恢复",
                f"{previous} 已恢复。成绩检查和会话心跳将继续自动运行。",
            )
        except Exception:
            LOGGER.exception("发送恢复通知失败")
            return
        self.store.delete("failure_active")
        self.store.delete("failure_kind")
        self.store.delete("failure_title")
        self.store.delete("failure_started_at")
        self.store.delete("failure_detection_count")

    def check_once(self) -> None:
        courses = self.fetch_courses()
        snapshot = normalize_courses(courses)
        old_snapshot = self.store.get_snapshot()
        checked_at = datetime.now(timezone.utc).isoformat()

        if old_snapshot is None:
            self.notifier.send(
                "正方教务首次成绩同步",
                format_initial_snapshot(snapshot),
            )
            self.store.set_snapshot(snapshot)
            self.store.set("snapshot_hash", snapshot_hash(snapshot))
            self.store.set("last_success_at", checked_at)
            LOGGER.info("首次运行：已推送并建立 %d 门课程的成绩基线", len(snapshot))
            self._notify_recovery()
            return

        if old_snapshot and not snapshot:
            raise CheckError("本次成绩列表为空，已保留旧状态，避免误报全部成绩被删除")

        changes = diff_snapshots(old_snapshot, snapshot)
        if not changes.has_changes:
            self.store.set("last_success_at", checked_at)
            LOGGER.info("成绩未变化，共 %d 门课程", len(snapshot))
            self._notify_recovery()
            return

        labels = {course_key(course): "新增" for course in changes.added}
        labels.update({course_key(new): "更新" for _, new in changes.changed})
        content = format_full_snapshot(
            snapshot,
            change_types=labels,
            removed=changes.removed,
        )
        self.notifier.send(
            (
                "正方教务成绩有更新"
                f"（新增 {len(changes.added)}，更新 {len(changes.changed)}，"
                f"移除 {len(changes.removed)}）"
            ),
            content,
        )
        self.store.set_snapshot(snapshot)
        self.store.set("snapshot_hash", snapshot_hash(snapshot))
        self.store.set("last_success_at", checked_at)
        self.store.delete("failure_active")
        self.store.delete("failure_kind")
        self.store.delete("failure_title")
        self.store.delete("failure_started_at")
        self.store.delete("failure_detection_count")
        LOGGER.info(
            "更新通知已发送：新增 %d，变更 %d，消失 %d",
            len(changes.added),
            len(changes.changed),
            len(changes.removed),
        )

    def run_forever(self) -> None:
        LOGGER.info(
            "服务启动：每 %d 秒检查一次成绩，每 %d 秒保持一次会话心跳，检查抖动范围 0-%d 秒",
            self.config.interval_seconds,
            self.config.heartbeat_interval_seconds,
            self.config.jitter_seconds,
        )
        next_check = 0.0
        next_heartbeat = time.monotonic() + self.config.heartbeat_interval_seconds
        while True:
            now = time.monotonic()
            operation = None
            if now >= next_check:
                operation = ("成绩检查", self.check_once)
            elif now >= next_heartbeat:
                operation = ("会话心跳", self.heartbeat)

            if operation is not None:
                try:
                    operation[1]()
                except KeyboardInterrupt:
                    raise
                except Exception as exc:
                    LOGGER.exception("%s失败", operation[0])
                    try:
                        self._notify_failure(str(exc))
                    except Exception:
                        LOGGER.exception("发送失败告警失败")

                now = time.monotonic()
                if operation[0] == "成绩检查":
                    next_check = now + self.config.interval_seconds + random.randint(
                        0, self.config.jitter_seconds
                    )
                    next_heartbeat = now + self.config.heartbeat_interval_seconds
                else:
                    next_heartbeat = now + self.config.heartbeat_interval_seconds

            delay = max(0.1, min(next_check, next_heartbeat) - time.monotonic())
            time.sleep(delay)
