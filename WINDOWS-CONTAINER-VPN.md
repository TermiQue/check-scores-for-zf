# Windows 11 一键部署与使用手册

启动器会自动判断是否需要 EasyConnect：宿主机和 Docker 已经可以访问正方时只运行成绩检查器；无法直连时才运行隔离的 EasyConnect 容器。Windows 原有网络及 Clash TUN 不需要修改，也不需要额外虚拟机。

网络模式通过三个 Compose 文件叠加实现：基础定义 (`compose.easyconnect.yml`)、Host 网络直连叠加 (`compose.host.yml`) 和容器 VPN 叠加 (`compose.vpn.yml`)。启动器根据实测连通性自动选择，详见 [架构说明](docs/ARCHITECTURE.md#请求路径)。

## 准备内容

- Windows 11；
- 用户自行下载安装并启动 Docker Desktop，使用 Linux Containers；
- 矿大 VPN 账号、密码和可接收短信的手机；
- 正方教务账号、密码；
- ShowDoc Push 的专属推送地址或 Token。

## 自行安装 Docker Desktop

本项目只提供容器配置和启动脚本，不会代替用户下载、安装或授权 Docker Desktop。请在运行项目之前自行完成安装。

官方入口：

- [Docker Desktop 官方下载页](https://www.docker.com/products/docker-desktop/)；
- [Docker Desktop for Windows 安装文档](https://docs.docker.com/desktop/setup/install/windows-install/)；
- [Docker Desktop WSL 2 后端文档](https://docs.docker.com/desktop/features/wsl/)；
- [Docker Desktop 许可与产品说明](https://docs.docker.com/desktop/)。

### 安装前检查

- 使用受 Docker 当前版本支持的 64 位 Windows 11；
- 在 BIOS/UEFI 中开启 CPU 硬件虚拟化；
- 启用并更新 WSL 2，Docker 官方当前要求至少 WSL 2.1.5，建议使用最新版本；
- 准备至少 8 GB 内存；
- 如果电脑使用 ARM 处理器，应下载对应的 Windows ARM 版本，而不是 AMD64 版本。

可在管理员 PowerShell 中安装或更新 WSL：

```powershell
wsl --install
wsl --update
wsl --version
```

Windows 提示重启时，请先重启电脑再继续。WSL 的具体启用方式以 Docker 官方 Windows 安装文档为准。

### 安装与配置

1. 从官方下载页获取 `Docker Desktop Installer.exe`；
2. 按照官方安装向导完成安装，推荐使用 WSL 2 后端；
3. 启动 Docker Desktop，并等待界面显示 Running；
4. 在 `Settings > General` 中确认启用 `Use WSL 2 based engine`；
5. 确认 Docker Desktop 当前运行 Linux Containers。本项目不能在 Windows Containers 模式下运行。
6. 如需让 checker 复用 Windows 原生 VPN，可在 Docker Desktop 4.34 或更高版本的 `Settings > Resources > Network` 中开启 `Enable host networking`，然后点击 Apply and restart。普通 Docker 网络已经能访问正方时不必开启。

Docker Desktop 已经包含 Docker Engine、Docker CLI 和 Docker Compose，无需再单独安装 `docker.exe` 或 Compose。也不要求用户另外下载 Ubuntu 等 WSL Linux 发行版。

Host 网络的版本要求、启用步骤和限制见 [Docker Host 网络官方文档](https://docs.docker.com/engine/network/drivers/host/#docker-desktop)。

在 PowerShell 中验证：

```powershell
docker version
docker compose version
docker info --format '{{.OSType}}'
```

前两条命令应正常显示客户端和服务端版本，最后一条命令应输出：

```text
linux
```

如果 `docker version` 只有 Client 信息或提示无法连接 daemon，说明 Docker Desktop 尚未完全启动。如果输出 `windows`，请从 Docker Desktop 菜单切换到 Linux Containers。

## 开通 ShowDoc 微信推送

ShowDoc Push 使用微信公众号完成注册和登录，不需要另外设置用户名与密码。

1. 在电脑浏览器打开 [ShowDoc 推送服务](https://push.showdoc.com.cn/)；
2. 点击右上角“登录”；
3. 使用需要接收成绩通知的微信扫描二维码；
4. 首次使用时，根据页面提示关注公众号后完成开通；已经关注过公众号的用户直接扫码即可；
5. 登录成功后进入右上角“推送”；
6. 复制页面显示的专属推送地址。

专属推送地址类似：

```text
https://push.showdoc.com.cn/server/api/push/你的token
```

本项目接受以下任意一种输入：

- 完整专属推送地址；
- 地址最后一段 `你的token`。

首次运行 `windows-launcher.cmd` 时，将它粘贴到 ShowDoc Push Token 输入提示中。输入内容不会显示在终端，并会保存到已被 Git 忽略的 `secrets/push_token.txt`。

注意：

- 专属推送地址等同于密码，不要截图公开、发送给他人或提交到 GitHub；
- 如果在 ShowDoc 页面重置了推送地址，旧 Token 会立即失效，需要重新运行 `windows-setup.ps1` 更新；
- 微信没有系统弹窗或未读数提醒时，可按 [ShowDoc 官方提醒设置说明](https://www.showdoc.com.cn/p/ba3f342eaff63072eb1976a5e18443c8) 检查公众号通知设置；
- API 和 Token 格式以 [ShowDoc Push 官方文档](https://www.showdoc.com.cn/push) 为准。

## 统一启动器

进入项目目录，双击：

```text
windows-launcher.cmd
```

也可以在 PowerShell 中运行：

```powershell
.\windows-launcher.cmd
```

启动器打开后选择“启动或恢复服务”。启动流程会自动完成：

1. 检查 Docker Desktop；
2. 首次运行时询问正方账号、密码和 ShowDoc Token；
3. 构建 checker 镜像；
4. 检查 Windows 宿主机是否已经能访问正方；
5. 依次尝试普通 Docker 直连和 Docker Desktop Host 网络；
6. Windows 宿主机不可达时，检查并复用现有容器 VPN；
7. 只有 VPN 未连接时才启动 EasyConnect，并打开 noVNC 等待短信验证；
8. 验证所选网络模式与正方网络；
9. 需要正方图片验证码时弹出 Windows 小窗口；
10. 登录成功后自动启动后台成绩检查服务。

启动器只使用“运行”和“成功”两种任务状态。每项任务开始时在当前行显示 `[运行]`，没有进度条的任务会显示循环旋转的 `| / - \`；结束后会在同一行切换为 `[成功]`。需要账号、验证码或 VPN 操作时只显示输入提示，不作为第三种状态。Docker 动态进度条会在同一行刷新百分比和耗时，正常英文输出会被收纳，仅在失败时附最后 12 行诊断信息。配色分别为启动台 `#f0f5e5`、运行 `#AB372F`、成功 `#2bae85`、输入提示 `#fbb929`，其他说明使用终端默认文字颜色。

同一菜单还可以停止服务、查看最近日志、实时跟踪日志和清除隐私数据，不再需要记忆多份脚本或 Docker 命令。

## VPN 登录

只有以下条件同时成立时，浏览器才会打开：

- Windows 宿主机无法直接访问正方，或 Docker 无法复用宿主机网络；
- 当前 EasyConnect 容器没有可用的 VPN 会话。

如果宿主机已经在校园网、已经连接 Windows 原生 VPN 且 Docker 能复用，或者容器 VPN 已经连接，启动器都会直接进入下一步，不弹出 VPN 登录页。

需要登录容器 VPN 时，启动器会先弹出注意事项和完整操作步骤。学校 VPN 地址会同时显示在终端和弹窗的只读地址框中，可以选中后按 `Ctrl+C`，也可以点击“复制地址”。只有用户点击“打开登录页面”后才会打开：

```text
http://127.0.0.1:18080/vnc.html
```

在 EasyConnect 页面中：

1. 接受隐私条款；
2. 服务器填写 `https://newvpn.cumt.edu.cn`；
3. 输入 VPN 账号和密码；
4. 完成手机短信验证；
5. 等待页面显示连接成功。

连接成功后不需要返回寻找确认弹窗。启动器会在后台自动检测 VPN 与正方教务的连通性，检测成功后直接进入下一步；最长等待 10 分钟，期间可以按 `Ctrl+C` 取消。

noVNC 只监听本机 `127.0.0.1`，不会暴露到局域网。

## 正方验证码

需要图片验证码时，启动程序会自动弹出一个置顶窗口，直接显示图片和输入框。输入后按 Enter 或点击“确定”即可。

如果正方拒绝登录，启动器会显示教务系统返回的失败原因以及当前学号、密码字段。密码默认以掩码显示，需要核对时可以勾选“显示密码”。此时可以直接获取新验证码重试，也可以修改学号和密码后重新验证；只有用户选择“取消启动”时才会停止本次流程，成绩基线和其他本地配置不会被删除。

验证码错误时会自动刷新图片并再次弹窗，最多尝试 5 次。不需要打开资源管理器，也不需要在容器 CLI 中输入。

项目不会识别、绕过或上传验证码，输入只保存在本机临时文件中，容器读取后立即删除。

## 推送规则

### 第一次检查

推送当前全部成绩，然后保存本地基线。课程按成绩提交时间从新到旧排列。

### 后续没有变化

不发送任何成绩通知。

### 后续有变化

推送当前完整成绩单，而不只是变化摘要：

- 新出现的课程增加 `类型：新增`；
- 已存在但成绩或相关字段变化的课程增加 `类型：更新`；
- 未变化的历史课程继续显示，但不添加类型；
- 消失的记录在末尾标记 `类型：移除`；
- 整体按提交时间从新到旧排列。

只有推送成功后才保存新基线。推送失败时，下次检查仍会重试同一次变化。

## 检查频率

- 启动后立即检查一次；
- 默认每 30 分钟检查成绩；
- 检查时间加入 0–120 秒随机抖动；
- 每 5 分钟保持正方登录会话；
- EasyConnect 容器每 5 分钟保持 VPN 活跃。

## 故障通知与恢复

服务会根据共享网络中的 `tun0` 隧道和错误内容分类通知：

| 通知 | 含义 | 恢复方法 |
| --- | --- | --- |
| `VPN连接断开，需要手动重启，累计监测35 分钟` | EasyConnect 隧道或 VPN 路由不存在 | 运行 `windows-launcher.cmd`，在 EasyConnect 中重新登录并完成短信验证 |
| `正方系统连接断开，需要手动重启，累计监测2 小时 10 分钟` | VPN 仍连接，但正方页面、接口或登录会话异常 | 运行 `windows-launcher.cmd`，按提示重新验证连接或输入图片验证码 |
| `未知错误` | 尚未分类的程序异常 | 查看 checker 日志，再运行 `windows-launcher.cmd` |

累计监测时间从本次同类故障首次被发现时开始计算。同类故障默认 6 小时内不重复推送，下次通知会显示最新持续时间；故障类型变化会重新计时并立即通知，连接恢复后会发送一次恢复通知并清零计时。

## 手动启动策略

EasyConnect 和 checker 都使用 `restart: "no"`。

这意味着：

- Docker Desktop 重启后，项目容器不会自行启动；
- Windows 开机后不会自动连接学校 VPN；
- 需要使用时手动双击 `windows-launcher.cmd`；
- 启动程序会复用已有 VPN 配置、正方 Cookie 和成绩基线。

这样可以避免用户没有主动使用时后台自动连接学校 VPN。

## 停止服务

双击 `windows-launcher.cmd`，选择“停止服务”。也可以直接运行：

```powershell
.\windows-launcher.ps1 -Action Stop
```

也可以直接使用 Docker Compose：

```powershell
docker compose -f .\compose.easyconnect.yml --profile vpn down
```

停止不会删除账号、VPN 配置、正方 Cookie 或成绩基线。

## 清除全部隐私数据并恢复到刚克隆状态

转让电脑、停止使用本项目，或需要模拟刚克隆后的状态时，打开 `windows-launcher.cmd`，选择“清除全部隐私数据并重置”。也可以直接运行：

```powershell
.\windows-launcher.ps1 -Action Erase
```

脚本会先显示清理范围，并要求输入 `ERASE`（不区分大小写）。确认后将：

1. 首先停止 checker 和 EasyConnect 的全部项目容器；停止失败时中止清理，不删除本地数据；
2. 删除已经停止的项目容器及项目网络；
3. 删除 `secrets/` 中的正方账号、密码和 ShowDoc Token；
4. 删除 `.env`、`.env.poc` 等运行时配置；
5. 删除 `runtime-data/` 中的正方 Cookie、成绩基线、验证码、日志和故障状态；
6. 删除 `easyconnect-data/` 中的 EasyConnect 登录配置和 VPN 会话缓存；
7. 删除 Python/测试缓存和本项目使用的 Docker 服务镜像。

脚本只保留：

- Git 仓库和项目源代码；
- Docker Desktop 本身；
- 其他项目的容器、网络、镜像和数据。

清理后工作目录与刚克隆时一致。再次运行 `windows-launcher.cmd`，需要重新输入正方账号、密码和 ShowDoc Token，并重新完成 EasyConnect 短信验证及正方图片验证码。由于成绩基线已删除，第一次成功查询会再次推送全部成绩。

为了确保容器、网络和镜像也被删除，清理时应保持 Docker Desktop 运行。如果 Docker 不可用，脚本仍会优先删除本地隐私文件，但会提示清理尚未完整；启动 Docker Desktop 后再次运行即可完成剩余清理。

自动化测试环境可以显式跳过人工确认：

```powershell
.\windows-launcher.ps1 -Action Erase -Force
```

`-Force` 会跳过不可撤销操作的人工确认，只应在明确需要隐私擦除的自动化环境使用。

## 日志与日常检查

统一启动器提供两种日志查询：

- “查看最近日志”：显示所选服务最近 120 行并返回菜单；
- “实时跟踪日志”：持续显示新增日志，按 `Ctrl+C` 停止。

日志可以选择成绩检查服务、校园 VPN 或两个服务。也可以直接运行：

```powershell
.\windows-launcher.ps1 -Action Logs
.\windows-launcher.ps1 -Action FollowLogs
```

查看容器状态：

```powershell
docker compose -f .\compose.easyconnect.yml --profile vpn ps
```

查看成绩检查日志：

```powershell
# 最近 100 行
docker compose -f .\compose.easyconnect.yml logs --tail 100 checker

# 实时跟踪
docker compose -f .\compose.easyconnect.yml logs -f checker
```

发送 ShowDoc 测试通知：

```powershell
docker compose -f .\compose.easyconnect.yml run --rm checker notify-test
```

成功时，微信会收到标题为”成绩推送测试”的消息，日志显示”测试通知已发送”。如果返回 `url或token不正确`，请重新登录 ShowDoc Push 的”推送”页面复制地址，并重新运行 `windows-setup.ps1` 更新凭证。

单次成绩检查（不进入后台循环）：

```powershell
docker compose -f .\compose.easyconnect.yml run --rm checker once
```

验证正方教务网络可达性（仅 HTTP 请求，不登录）：

```powershell
docker compose -f .\compose.easyconnect.yml run --rm checker network-probe
```

## 本地数据

```text
secrets/            正方账号、密码和 ShowDoc Token
runtime-data/       Cookie、成绩基线、验证码和状态数据库
easyconnect-data/   EasyConnect 配置
.env                可选参数
```

以上路径都已加入 `.gitignore`，不要提交到 GitHub、上传网盘或发送给他人。

删除 `runtime-data/state.db` 会清除正方 Cookie 和成绩基线。下一次运行需要重新输入验证码，并会再次推送全部成绩。

## 可选配置

编辑 `.env`：

```dotenv
ZF_URL=http://jwxt.cumt.edu.cn/jwglxt/
ZF_CAPTCHA_PASSWORD_MODE=plain
ZF_CAPTCHA_MAX_ATTEMPTS=5
EC_VNC_PASSWORD=zfcheck
CHECK_INTERVAL_SECONDS=1800
HEARTBEAT_INTERVAL_SECONDS=300
CHECK_JITTER_SECONDS=120
FAILURE_ALERT_COOLDOWN_SECONDS=21600
REQUEST_TIMEOUT_SECONDS=20
```

首次运行时会自动从 `.env.example` 复制默认配置。各变量说明：

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `ZF_URL` | `http://jwxt.cumt.edu.cn/jwglxt/` | 正方教务系统地址 |
| `ZF_CAPTCHA_PASSWORD_MODE` | `plain` | 验证码登录密码提交方式：`plain`（明文）或 `encrypted`（RSA 加密） |
| `ZF_CAPTCHA_MAX_ATTEMPTS` | `5` | 验证码最多尝试次数 |
| `EC_VNC_PASSWORD` | `zfcheck` | EasyConnect noVNC 访问密码 |
| `PUSH_PROVIDER` | `showdoc` | 推送渠道：`showdoc` 或 `stdout`（终端预览） |
| `CHECK_INTERVAL_SECONDS` | `1800` | 成绩检查间隔（秒） |
| `HEARTBEAT_INTERVAL_SECONDS` | `300` | 教务会话心跳间隔（秒） |
| `CHECK_JITTER_SECONDS` | `120` | 检查间隔随机抖动上限（秒） |
| `FAILURE_ALERT_COOLDOWN_SECONDS` | `21600` | 同类故障通知冷却时间（秒，默认 6 小时） |
| `REQUEST_TIMEOUT_SECONDS` | `20` | 单次 HTTP 请求超时（秒） |

### 调试选项

以下变量不在 `.env.example` 中，需要时手动设置：

| 变量 | 说明 |
| --- | --- |
| `ZF_LOGIN_DEBUG=1` | 启用登录诊断日志，输出到 `runtime-data/login-debug.log`。仅记录 Cookie 指纹和请求元数据，不记录明文密码。 |
| `ZF_NETWORK_MODE` | 由启动脚本自动设置（`direct` 或 `vpn`），手动运行 checker 时可按需覆盖。 |
| `ZF_PROXY` | HTTP 代理地址。VPN 模式下不使用；直连模式下一般也不需要。 |
| `DATA_DIR` | 持久化数据目录，默认 `/data`。 |

## 项目脚本参考

| 脚本 | 用途 |
| --- | --- |
| `windows-launcher.cmd` / `.ps1` | 统一启动器：启动、停止、最近日志、实时日志、隐私清理 |
| `windows-setup.ps1` | 单独配置或更新账号与推送凭证 |
| `windows-ui.ps1` | 内部工具：进度条、Docker 包装器、中文错误翻译 |

`windows-launcher.cmd` 是普通用户唯一需要双击的入口；`windows-launcher.ps1` 的 `-Action` 参数用于命令行和自动化调用。

## 常见问题

### Docker Desktop 没有启动

本项目不会自动安装或启动 Docker Desktop。请先按照[官方 Windows 安装文档](https://docs.docker.com/desktop/setup/install/windows-install/)自行安装，然后启动 Docker Desktop，等待状态变为 Running，再重新运行 `windows-launcher.cmd`。

### `docker` 命令不存在

说明 Docker Desktop 尚未安装，或安装后终端没有重新打开。请从[Docker Desktop 官方下载页](https://www.docker.com/products/docker-desktop/)下载安装，完成后关闭并重新打开 PowerShell。

### Docker 当前是 Windows Containers

执行 `docker info --format '{{.OSType}}'` 检查。如果结果为 `windows`，请通过 Docker Desktop 菜单切换到 Linux Containers；结果为 `linux` 后再运行 `windows-launcher.cmd`。

### 无法下载镜像

包含 `failed to resolve reference` 或 `Docker Desktop has no HTTPS proxy` 的错误属于 Docker Hub 网络问题。配置 Docker Desktop 代理或更换可访问 Docker Hub 的网络后重试。

### VPN 页面已经连接，但正方仍不可达

重新运行 `windows-launcher.cmd`。启动器会实际请求正方页面，而不是只检查 `tun0` 是否存在；现有 VPN 可用时会直接复用，不可用时才重新打开登录页面。

### 第二次启动仍然打开 VPN 页面

这表示 Windows 宿主机无法访问正方，并且现有容器 VPN 的实际正方请求也失败了。请确认 EasyConnect 页面确实显示已连接。若 Windows 宿主机已经可以访问正方，启动器不会打开容器 VPN；Docker 无法复用时会提示按照 [Docker Host 网络官方文档](https://docs.docker.com/engine/network/drivers/host/#docker-desktop) 启用 Host networking。

### 验证码窗口没有出现

窗口只在正方要求验证码时出现。若 Cookie 仍有效，程序会直接登录，不显示验证码。

## 安全边界

- 只有 EasyConnect 容器拥有 `/dev/net/tun` 和 `NET_ADMIN`；
- checker 直连时使用 Docker 普通网络或 Host 网络；VPN 模式下才共享 EasyConnect 网络命名空间；
- EasyConnect HTTP/SOCKS 代理不发布到 Windows 或局域网；
- noVNC 仅绑定 `127.0.0.1`；
- ShowDoc 请求使用独立 Session，不继承系统代理环境；
- 短信验证码和图片验证码必须由用户本人完成。
