# 正方教务成绩检查与微信推送

在 Windows 11 上用 Docker 定时查询正方教务系统成绩，并通过 ShowDoc Push 推送到微信。

本分支面向中国矿业大学当前网络环境。启动器会先检测 Windows 宿主机和 Docker 是否已经能访问教务系统：能访问时 checker 直接联网，不启动 EasyConnect；不能访问时才启动隔离的 EasyConnect 容器。VPN 已连接时会直接复用现有会话，不重复打开登录页面。

## 当前状态

- 已在 Windows 11、Docker Desktop Linux Containers 环境完成端到端验证。
- EasyConnect 容器可以访问 `jwxt.cumt.edu.cn`。
- 正方图片验证码和矿大明文密码兼容模式已验证。
- 登录 Cookie、成绩基线和故障状态可持久化。
- 默认每 30 分钟检查成绩，每 5 分钟保持教务会话活跃；使用容器 VPN 时同时保持 VPN 活跃。
- 第一次成功查询会推送当前全部成绩；以后仅在出现新增、更新或移除时推送。
- 有变化时推送按提交时间从新到旧排列的完整成绩单，并标注“新增”或“更新”；无变化时保持静默。
- Docker Desktop 重启后不会自动启动服务，由用户手动运行启动入口。

## 架构

```text
Windows/Docker can reach Zhengfang → checker direct ────────> Zhengfang
otherwise                        → checker → EasyConnect VPN → Zhengfang
checker ─────────────────────────────────────────────────────> ShowDoc Push
```

启动器根据实际连通性选择网络模式，通过 Docker Compose 文件叠加实现：

| 模式 | Compose 文件 | checker 网络 |
| --- | --- | --- |
| 宿主机直连 | `compose.easyconnect.yml` | 默认 Docker bridge |
| Host 网络直连 | `compose.easyconnect.yml` + `compose.host.yml` | Docker Desktop Host 网络 |
| 容器 VPN | `compose.easyconnect.yml` + `compose.vpn.yml` | `service:easyconnect` 共享网络命名空间 |

Windows 宿主机可达时，启动器只尝试普通 Docker 直连和 Docker Desktop Host 网络，不会启动容器 VPN；如果 Docker 无法复用宿主机网络，会提示用户启用 Host networking。只有宿主机不可达时，才检查现有容器 VPN 并在必要时新建连接。VPN 模式下只有 EasyConnect 容器拥有 `/dev/net/tun` 和 `NET_ADMIN`。checker 以非 root 用户运行、根文件系统只读，也不会修改 Windows 路由。

## 项目结构

```text
check-scores-for-zf/
├── zfcheck/                  # Python 成绩检查服务
│   ├── __init__.py
│   ├── __main__.py           # CLI 入口（run / probe / once / notify-test）
│   ├── config.py             # 环境变量配置读取
│   ├── model.py              # 成绩快照、比对与格式化
│   ├── notifier.py           # ShowDoc Push / stdout 通知
│   ├── service.py            # 成绩检查、登录、心跳与故障通知
│   └── state.py              # SQLite 状态持久化（Cookie、成绩基线）
├── scripts/
│   └── zfn_api.py            # 正方教务系统 API 客户端
├── tests/
│   ├── test_model.py
│   ├── test_notifier.py
│   ├── test_service.py
│   └── test_zfn_api.py
├── compose.easyconnect.yml   # 基础 Compose（checker + easyconnect profile）
├── compose.host.yml          # 叠加：checker 使用 Host 网络
├── compose.vpn.yml           # 叠加：checker 共享 EasyConnect 网络命名空间
├── Dockerfile                # checker 镜像（Python 3.12-slim，非 root）
├── windows-start.cmd         # 一键启动入口（双击或 PowerShell）
├── windows-start.ps1         # 启动编排脚本
├── windows-stop.cmd          # 停止全部容器
├── windows-stop.ps1
├── windows-setup.ps1         # 首次配置账号与 ShowDoc Token
├── windows-clear-cache.cmd   # 清除全部隐私数据
├── windows-clear-cache.ps1
├── windows-ui.ps1            # PowerShell WinForms 工具函数（进度条、Docker 包装器）
├── .env.example              # 可选配置模板
└── docs/
    └── ARCHITECTURE.md       # 架构与实现说明
```

## 快速开始

准备好以下内容：

- Windows 11；
- 用户自行下载安装并启动 Docker Desktop，使用 Linux Containers；
- 矿大 VPN、正方教务账号和密码；
- ShowDoc Push 的专属推送地址或 Token。

### 安装 Docker Desktop

本项目不会自动下载或安装 Docker。请读者自行从 [Docker Desktop 官方下载页](https://www.docker.com/products/docker-desktop/) 下载与电脑 CPU 架构匹配的 Windows 版本，并按照 [Docker Desktop for Windows 官方安装文档](https://docs.docker.com/desktop/setup/install/windows-install/) 完成安装。

推荐使用 WSL 2 后端。安装前请确认 Windows 已启用硬件虚拟化和 WSL 2；相关要求及设置方法见 [Docker Desktop WSL 2 官方文档](https://docs.docker.com/desktop/features/wsl/)。Docker Desktop 已包含 Docker Engine、Docker CLI 和 Docker Compose，不需要单独安装 Compose。

安装后启动 Docker Desktop，等待状态变为 Running，并在 PowerShell 中确认输出正常：

```powershell
docker version
docker compose version
docker info --format '{{.OSType}}'
```

最后一条命令应输出 `linux`。如果输出 `windows`，请在 Docker Desktop 菜单中切换到 Linux Containers，再运行本项目。

如果希望 checker 复用 Windows 原生 VPN，而普通 Docker 网络无法访问正方，请使用 Docker Desktop 4.34 或更高版本，并在 `Settings > Resources > Network` 中开启 `Enable host networking`。具体要求见 [Docker Host 网络官方文档](https://docs.docker.com/engine/network/drivers/host/#docker-desktop)。

### 获取 ShowDoc Push Token

ShowDoc Push 不需要单独设置用户名和密码：

1. 使用电脑打开 [ShowDoc 推送服务](https://push.showdoc.com.cn/)；
2. 点击右上角“登录”，使用微信扫描二维码；首次使用时还需要关注公众号，已关注用户直接扫码即可；
3. 登录后进入右上角“推送”，复制页面显示的专属推送地址；
4. 首次运行本项目时，可以粘贴完整地址，也可以只粘贴地址最后的 Token。

专属地址格式如下，其中最后一段就是 Token：

```text
https://push.showdoc.com.cn/server/api/push/你的token
```

推送地址和 Token 都属于私密凭证，请勿截图公开或提交到 Git。如果在 ShowDoc 中重置了推送地址，需要重新运行 `windows-setup.ps1` 更新本地凭证。更多接口说明见 [ShowDoc Push 官方文档](https://www.showdoc.com.cn/push)。

在项目目录中双击 `windows-start.cmd`，或者在 PowerShell 中只执行一个命令：

```powershell
.\windows-start.cmd
```

启动程序会自动完成环境检查、首次配置、镜像构建、网络模式选择、正方登录和后台服务启动。只有宿主机无法直连且容器 VPN 也未连接时，才会打开 EasyConnect 页面；正方需要图片验证码时会直接弹出轻量输入窗口。

完整的从零部署、成功标志、开机运行和故障排查见 [Windows 部署手册](WINDOWS-CONTAINER-VPN.md)。实现原理见 [架构说明](docs/ARCHITECTURE.md)。

## 常用命令

```powershell
# 一键启动或恢复（首次运行自动配置账号）
.\windows-start.cmd

# 仅配置或更新账号与推送凭证
.\windows-setup.ps1

# 停止全部容器（保留账号、Cookie 和成绩基线）
.\windows-stop.cmd

# 清除全部隐私数据并恢复到刚克隆状态
.\windows-clear-cache.cmd

# 查看服务状态
docker compose -f .\compose.easyconnect.yml --profile vpn ps

# 查看成绩检查日志（最近 100 行）
docker compose -f .\compose.easyconnect.yml logs --tail 100 checker

# 实时跟踪成绩检查日志
docker compose -f .\compose.easyconnect.yml logs -f checker

# 测试微信推送
docker compose -f .\compose.easyconnect.yml run --rm checker notify-test

# 单次成绩检查（不进入循环）
docker compose -f .\compose.easyconnect.yml run --rm checker once

# 验证正方教务连接
docker compose -f .\compose.easyconnect.yml run --rm checker network-probe
```

## 可选配置

复制 `.env.example` 为 `.env` 后按需修改：

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

详细说明见 [Windows 部署手册](WINDOWS-CONTAINER-VPN.md#可选配置)。

## 数据与隐私

以下路径都已加入 `.gitignore`，不得提交或发送给他人：

- `secrets/`：正方账号、密码和 ShowDoc Token；
- `runtime-data/`：登录 Cookie、成绩快照和验证码；
- `easyconnect-data/`：EasyConnect 登录配置。

转让电脑、停止使用或需要从全新状态重新测试时，可以双击 `windows-clear-cache.cmd`。脚本要求输入 `ERASE` 后，删除项目运行后产生的全部隐私数据和本地配置，包括账号密码、ShowDoc Token、`.env`、正方 Cookie、成绩基线、日志、验证码、EasyConnect 配置与 VPN 会话，同时删除本项目的容器、网络和服务镜像。Git 仓库、源代码、Docker Desktop 和其他项目的数据不会被删除。清理后再次启动需要重新输入全部凭据并完成短信及图片验证码。

首次发布前建议执行：

```powershell
git status --short
git grep -n -I -E "你的学号|你的Token|你的密码"
```

## 已知限制

- 短信验证码和正方图片验证码必须由用户本人输入，项目不会绕过验证码。
- 如果学校强制 VPN 或正方会话重新认证，重新运行 `windows-start.cmd` 即可。
- 当前容器 VPN 配置针对矿大验证；其他学校需要调整 VPN 地址、正方地址及登录兼容参数。
- 项目依赖第三方 EasyConnect 容器镜像；镜像已在 Compose 中固定到不可变摘要，升级前应重新验证。

## 致谢与许可证

本项目基于 [NianBroken/ZFCheckScores](https://github.com/NianBroken/ZFCheckScores) 和 [openschoolcn/zfn_api](https://github.com/openschoolcn/zfn_api) 改造。

代码按仓库中的 [Apache License 2.0](LICENSE) 发布。分发修改版本时请保留原作者版权、许可证和修改说明。
