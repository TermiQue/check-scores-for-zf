# 配置参考

首次启动时，`windows-setup.ps1` 会从 `.env.example` 复制生成本地 `.env`。该文件已被 Git 忽略，修改后重新运行 `windows-launcher.cmd` 即可生效。

## 默认配置

```dotenv
ZF_URL=http://jwxt.cumt.edu.cn/jwglxt/
ZF_CAPTCHA_PASSWORD_MODE=plain
ZF_CAPTCHA_MAX_ATTEMPTS=5
EC_VNC_PASSWORD=zfcheck
PUSH_PROVIDER=showdoc
CHECK_INTERVAL_SECONDS=1800
HEARTBEAT_INTERVAL_SECONDS=300
CHECK_JITTER_SECONDS=120
FAILURE_ALERT_COOLDOWN_SECONDS=21600
REQUEST_TIMEOUT_SECONDS=20
```

## Docker 构建与镜像源

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `PYTHON_BASE_IMAGE` | 固定摘要的 `python:3.12-slim` | 可选的 Python 基础镜像地址；通常无需设置 |

启动器默认使用 Docker Hub 官方 Python 镜像并自动尝试 3 次。如果错误明确来自基础镜像的网络请求，则自动切换到 DaoCloud 公共镜像加速，再尝试 2 次。官方源和备用源都固定为同一个 SHA-256 摘要，因此切换仓库地址不会改变基础镜像内容。

如果所在网络有自己的可信镜像仓库，可以在 `.env` 中设置：

```dotenv
PYTHON_BASE_IMAGE=你的镜像仓库/library/python:3.12-slim@sha256:423ed6ab25b1921a477529254bfeeabf5855151dc2c3141699a1bfc852199fbf
```

自定义源会优先尝试；网络失败时仍会依次回退到 Docker Hub 和 DaoCloud。依赖安装、代码错误或其他非基础镜像下载问题不会触发重复构建。

## 教务与验证码

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `ZF_URL` | `http://jwxt.cumt.edu.cn/jwglxt/` | 正方教务系统根地址 |
| `ZF_CAPTCHA_PASSWORD_MODE` | `plain` | 验证码登录密码提交方式；矿大当前兼容模式为 `plain`，其他环境可尝试 `encrypted` |
| `ZF_CAPTCHA_MAX_ATTEMPTS` | `5` | 单次交互式登录允许刷新并输入验证码的最大次数 |
| `REQUEST_TIMEOUT_SECONDS` | `20` | 单次 HTTP 请求超时时间（秒） |

## 成绩检查与心跳

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `CHECK_INTERVAL_SECONDS` | `1800` | 成绩检查间隔（秒），默认 30 分钟 |
| `HEARTBEAT_INTERVAL_SECONDS` | `300` | 正方登录会话心跳间隔（秒），默认 5 分钟 |
| `CHECK_JITTER_SECONDS` | `120` | 成绩检查随机抖动上限（秒），避免每次严格固定在同一时刻请求 |
| `FAILURE_ALERT_COOLDOWN_SECONDS` | `21600` | 同类故障微信通知冷却时间（秒），默认 6 小时 |

## VPN 与推送

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `EC_VNC_PASSWORD` | `zfcheck` | 本机 noVNC 页面访问密码；noVNC 只监听 `127.0.0.1` |
| `PUSH_PROVIDER` | `showdoc` | `showdoc` 发送微信通知；`stdout` 只在日志中预览通知 |

ShowDoc 的专属地址或 Token 不写入 `.env`，而是保存在 `secrets/push_token.txt`。需要更新账号、密码或 Token 时运行：

```powershell
.\windows-setup.ps1
```

## 启动器参数

普通使用者直接双击 `windows-launcher.cmd`。自动化或诊断时可以调用 PowerShell 入口：

```powershell
.\windows-launcher.ps1 -Action Start
.\windows-launcher.ps1 -Action Stop
.\windows-launcher.ps1 -Action Logs
.\windows-launcher.ps1 -Action FollowLogs
.\windows-launcher.ps1 -Action Erase
```

`Erase` 默认要求输入 `ERASE`。只有明确用于自动化隐私擦除时，才可以附加 `-Force` 跳过确认。

## 诊断变量

以下变量不在 `.env.example` 中，一般无需设置：

| 变量 | 说明 |
| --- | --- |
| `ZF_LOGIN_DEBUG=1` | 将登录诊断写入 `runtime-data/login-debug.log`；不记录明文密码 |
| `ZF_NETWORK_MODE` | 启动器自动设置为 `direct` 或 `vpn`；手动运行 checker 时可覆盖 |
| `ZF_PROXY` | checker 使用的 HTTP 代理；VPN 模式不应设置 |
| `PUSH_RELAY_URL` | VPN 模式由 Compose 自动设置；使 ShowDoc 推送绕过校园 VPN |
| `DATA_DIR` | 容器内持久化目录，默认 `/data` |
| `ZF_CAPTCHA_INPUT_FILE` | 交互式探测使用的验证码答案文件，启动器自动设置 |
| `ZF_CAPTCHA_INPUT_TIMEOUT_SECONDS` | 等待 Windows 验证码窗口输入的最长时间 |

有关三个 Compose 网络组合的关系，请阅读[技术架构](ARCHITECTURE.md#compose-文件叠加)。
