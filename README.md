# 正方教务成绩检查与微信推送

在 Windows 11 上用 Docker 定时查询正方教务系统成绩，并通过 ShowDoc Push 推送到微信。

本分支面向中国矿业大学当前网络环境：学校教务系统只能从校园网访问，EasyConnect 登录还需要短信验证码。项目将 EasyConnect 放在独立容器中，checker 共享该容器的网络命名空间，避免宿主机 VPN 接管 Windows 默认路由或影响 Clash TUN。

## 当前状态

- 已在 Windows 11、Docker Desktop Linux Containers 环境完成端到端验证。
- EasyConnect 容器可以访问 `jwxt.cumt.edu.cn`。
- 正方图片验证码和矿大明文密码兼容模式已验证。
- 登录 Cookie、成绩基线和故障状态可持久化。
- 默认每 30 分钟检查成绩，每 5 分钟保持 VPN 与教务会话活跃。
- 第一次成功查询会推送当前全部成绩；以后仅在出现新增、更新或移除时推送。
- 有变化时推送按提交时间从新到旧排列的完整成绩单，并标注“新增”或“更新”；无变化时保持静默。
- Docker Desktop 重启后不会自动启动服务，由用户手动运行启动入口。

## 架构

```text
checker --shared network--> EasyConnect container --CUMT VPN--> Zhengfang
checker --shared network--> Docker public route -------------> ShowDoc Push
Windows / Clash ----------------------------------------------> normal network
```

只有 EasyConnect 容器拥有 `/dev/net/tun` 和 `NET_ADMIN`。checker 容器以非 root 用户运行、根文件系统只读，也不会修改 Windows 路由。

## 快速开始

准备好以下内容：

- Windows 11；
- 已启动的 Docker Desktop，并切换到 Linux Containers；
- 矿大 VPN、正方教务账号和密码；
- ShowDoc Push Token。

在项目目录中双击 `windows-start.cmd`，或者在 PowerShell 中只执行一个命令：

```powershell
.\windows-start.cmd
```

启动程序会自动完成环境检查、首次配置、镜像构建、VPN 检查、正方登录和后台服务启动。VPN 未连接时会打开 EasyConnect 页面；正方需要图片验证码时会直接弹出轻量输入窗口。

完整的从零部署、成功标志、开机运行和故障排查见 [Windows 部署手册](WINDOWS-CONTAINER-VPN.md)。实现原理见 [架构说明](docs/ARCHITECTURE.md)。

## 常用命令

```powershell
# 一键启动或恢复
.\windows-start.cmd

# 停止全部容器
.\windows-stop.cmd

# 查看状态
docker compose -f .\compose.easyconnect.yml ps

# 查看成绩检查日志
docker compose -f .\compose.easyconnect.yml logs -f checker

# 测试微信推送
docker compose -f .\compose.easyconnect.yml run --rm checker notify-test

```

## 数据与隐私

以下路径都已加入 `.gitignore`，不得提交或发送给他人：

- `secrets/`：正方账号、密码和 ShowDoc Token；
- `runtime-data/`：登录 Cookie、成绩快照和验证码；
- `easyconnect-data/`：EasyConnect 登录配置。

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
