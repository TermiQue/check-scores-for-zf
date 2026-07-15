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


if __name__ == "__main__":
    unittest.main()
