import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

from zfcheck import __main__


class SuccessfulChecker:
    def __init__(self, config):
        self.config = config

    def probe(self, *, interactive=False):
        if not interactive:
            raise AssertionError("interactive probe was not requested")
        return 49

    def close(self):
        pass


class InteractiveProbeCommandTests(unittest.TestCase):
    def test_success_writes_host_visible_marker(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            config = SimpleNamespace(data_dir=Path(temp_dir))
            with patch.object(
                __main__, "parse_args", return_value=SimpleNamespace(command="interactive-probe")
            ), patch.object(
                __main__.Config, "from_env", return_value=config
            ), patch.object(
                __main__, "ScoreChecker", SuccessfulChecker
            ):
                exit_code = __main__.main()

            self.assertEqual(0, exit_code)
            marker = Path(temp_dir) / "interactive-probe-success"
            self.assertEqual("ok\n", marker.read_text(encoding="ascii"))


if __name__ == "__main__":
    unittest.main()
