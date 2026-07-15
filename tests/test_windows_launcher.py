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

    def test_login_failure_offers_retry_and_credential_change(self):
        content = (ROOT / "windows-launcher.ps1").read_text(
            encoding="utf-8-sig"
        )

        self.assertIn('$retryButton.Text = "重新输入验证码"', content)
        self.assertIn('$changeButton.Text = "更改账号密码"', content)
        self.assertIn('$showPassword.Text = "显示密码"', content)
        self.assertIn('"-e", "ZF_FORCE_LOGIN=1"', content)
        self.assertIn("Write-Utf8NoBom $usernamePath $credentials.Username", content)
        self.assertIn("Write-Utf8NoBom $passwordPath $credentials.Password", content)
        self.assertNotIn(
            "正方登录验证失败。请查看上方日志后重新运行",
            content,
        )


if __name__ == "__main__":
    unittest.main()
