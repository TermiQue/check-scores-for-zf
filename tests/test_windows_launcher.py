import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class WindowsLauncherContractTests(unittest.TestCase):
    def test_vpn_address_is_copyable_and_printed_in_terminal(self):
        content = (ROOT / "windows-launcher.ps1").read_text(encoding="utf-8-sig")

        self.assertIn(
            '$VpnServerAddress = "https://newvpn.cumt.edu.cn"', content
        )
        self.assertIn("$addressBox.ReadOnly = $true", content)
        self.assertIn('$copyButton.Text = "复制地址"', content)
        self.assertIn("$addressBox.Copy()", content)
        self.assertIn('Write-Host "校园 VPN 地址：$VpnServerAddress"', content)
        self.assertIn(
            "Confirm-VpnLoginInstructions -VpnAddress $VpnServerAddress",
            content,
        )

    def test_error_text_is_normalized_before_showing_a_dialog(self):
        launcher = (ROOT / "windows-launcher.ps1").read_text(
            encoding="utf-8-sig"
        )
        ui = (ROOT / "windows-ui.ps1").read_text(encoding="utf-8-sig")

        self.assertIn("ConvertTo-ReadableText $Text", launcher)
        self.assertIn("function ConvertTo-ReadableText", ui)
        self.assertIn("[Console]::OutputEncoding", ui)
        self.assertIn("Get-Content -LiteralPath $stdoutPath -Raw -Encoding UTF8", ui)
        self.assertIn("Get-Content -LiteralPath $stderrPath -Raw -Encoding UTF8", ui)


if __name__ == "__main__":
    unittest.main()
