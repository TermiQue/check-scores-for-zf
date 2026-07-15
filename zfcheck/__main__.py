from __future__ import annotations

import argparse
import logging
import os
import sys
from pathlib import Path

from scripts.zfn_api import Client
from .config import Config, _positive_int, _read_secret
from .notifier import serve_showdoc_relay
from .service import ScoreChecker


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="正方教务成绩检查器")
    parser.add_argument(
        "command",
        choices=(
            "network-probe",
            "probe",
            "interactive-probe",
            "notify-test",
            "notify-relay",
            "once",
            "run",
        ),
        nargs="?",
        default="run",
    )
    return parser.parse_args()


def network_probe() -> None:
    base_url = os.getenv("ZF_URL", "http://jwxt.cumt.edu.cn/jwglxt/").strip()
    if not base_url.endswith("/"):
        base_url += "/"
    timeout = int(os.getenv("REQUEST_TIMEOUT_SECONDS", "20"))
    client = Client(cookies={}, base_url=base_url, timeout=timeout)
    proxy = os.getenv("ZF_PROXY", "").strip()
    if proxy:
        client.sess.proxies.update({"http": proxy, "https": proxy})
    response = client.sess.get(
        client.login_url,
        headers=client.headers,
        timeout=timeout,
    )
    response.raise_for_status()
    logging.getLogger(__name__).info(
        "Network POC passed: HTTP %s, final URL %s",
        response.status_code,
        response.url,
    )


def main() -> int:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s | %(message)s",
    )
    if os.getenv("ZF_LOGIN_DEBUG", "0").strip().lower() in {
        "1",
        "true",
        "yes",
        "on",
    }:
        debug_path = Path(os.getenv("DATA_DIR", "/data")) / "login-debug.log"
        debug_path.parent.mkdir(parents=True, exist_ok=True)
        handler = logging.FileHandler(debug_path, mode="w", encoding="utf-8")
        handler.setFormatter(
            logging.Formatter("%(asctime)s %(levelname)s %(name)s | %(message)s")
        )
        logging.getLogger().addHandler(handler)
        logging.getLogger(__name__).info(
            "Safe login diagnostics are being written to %s", debug_path
        )
    args = parse_args()
    config = None
    try:
        if args.command == "network-probe":
            network_probe()
            return 0

        if args.command == "notify-relay":
            serve_showdoc_relay(
                _read_secret("PUSH_TOKEN"),
                _positive_int("REQUEST_TIMEOUT_SECONDS", 20),
                port=_positive_int("PUSH_RELAY_PORT", 8765),
            )
            return 0

        config = Config.from_env(
            require_push=args.command not in {"probe", "interactive-probe"}
        )
        if args.command == "interactive-probe":
            for marker_name in (
                "interactive-probe-success",
                "interactive-probe-error.txt",
            ):
                (config.data_dir / marker_name).unlink(missing_ok=True)
        checker = ScoreChecker(config)
        try:
            if args.command == "probe":
                checker.probe()
            elif args.command == "interactive-probe":
                checker.probe(interactive=True)
                success_marker = config.data_dir / "interactive-probe-success"
                success_marker.write_text("ok\n", encoding="ascii")
            elif args.command == "notify-test":
                checker.test_notification()
            elif args.command == "once":
                checker.check_once()
            else:
                checker.run_forever()
        finally:
            checker.close()
        return 0
    except KeyboardInterrupt:
        return 130
    except Exception as exc:
        if args.command == "interactive-probe" and config is not None:
            try:
                error_marker = config.data_dir / "interactive-probe-error.txt"
                error_marker.write_text(f"{exc}\n", encoding="utf-8")
            except OSError:
                logging.getLogger(__name__).exception("无法写入交互登录错误标记")
        logging.getLogger(__name__).error("%s", exc)
        return 1


if __name__ == "__main__":
    sys.exit(main())
