# 日常运维与隐私

## 统一启动器

双击 `windows-launcher.cmd` 可以完成：

1. 启动或恢复服务；
2. 停止服务；
3. 查看最近 120 行日志；
4. 实时跟踪日志；
5. 清除全部隐私数据并重置。

Docker Desktop 重启后，本项目不会自动连接校园 VPN，也不会自动启动容器。需要继续检查成绩时，重新打开启动器并选择“启动或恢复服务”。已有 VPN 会话和正方 Cookie 可用时会直接复用。

## 查看运行状态

```powershell
docker compose -f .\compose.easyconnect.yml --profile vpn ps
```

正常运行时，`checker` 应处于运行状态；使用容器 VPN 时，`easyconnect` 也应处于运行状态。

## 日志

推荐直接使用启动器菜单选择成绩检查日志、校园 VPN 日志或两者。也可以运行：

```powershell
# 最近日志
.\windows-launcher.ps1 -Action Logs

# 实时日志；按 Ctrl+C 停止
.\windows-launcher.ps1 -Action FollowLogs
```

原始 Compose 命令：

```powershell
docker compose -f .\compose.easyconnect.yml logs --tail 120 checker
docker compose -f .\compose.easyconnect.yml logs -f checker
docker compose -f .\compose.easyconnect.yml --profile vpn logs --tail 120 easyconnect
```

## 微信推送检查

如果成绩检查成功但微信没有收到消息，可以发送测试通知：

```powershell
docker compose -f .\compose.easyconnect.yml run --rm checker notify-test
```

成功时微信会收到“成绩推送测试”。如果 ShowDoc 返回 Token 错误，请登录 [ShowDoc 推送服务](https://push.showdoc.com.cn/) 重新复制专属地址，然后运行 `windows-setup.ps1` 更新本地凭证。

## 故障恢复

| 通知或现象 | 处理方式 |
| --- | --- |
| `VPN连接断开，需要手动重启` | 打开启动器；按提示重新登录 EasyConnect 并完成短信验证 |
| `正方系统连接断开，需要手动重启` | 打开启动器；重新验证正方连接，必要时输入图片验证码 |
| VPN 页面显示已连接但启动器仍等待 | 保持页面连接，查看 VPN 日志；持续失败时停止后重新启动 |
| 微信没有收到成绩 | 运行 `notify-test`，检查 ShowDoc Token 和公众号通知设置 |
| Docker Desktop 无法启动项目 | 确认 Docker Desktop 正在运行 Linux Containers，再查看[完整常见问题](../WINDOWS-CONTAINER-VPN.md#常见问题) |

故障通知会显示从本次同类故障首次出现开始计算的累计监测时间。连接恢复后会发送一次恢复通知并清零计时。

## 本地数据

以下内容均已加入 `.gitignore`：

| 路径 | 内容 |
| --- | --- |
| `secrets/` | 正方账号、密码和 ShowDoc Token |
| `runtime-data/` | Cookie、成绩基线、验证码、日志和故障状态数据库 |
| `easyconnect-data/` | EasyConnect 登录配置、短信验证会话和 VPN 缓存 |
| `.env` | 当前电脑的可选配置 |

不要公开、压缩发送或提交这些目录。日志用于排错时也应先检查是否包含个人信息。

## 清除全部隐私数据

转让电脑、停止使用项目或进行全新部署测试时，在启动器中选择“清除全部隐私数据并重置”。启动器会先停止本项目全部容器，再要求输入 `ERASE`（不区分大小写），随后删除：

- 账号、密码和 ShowDoc Token；
- 正方 Cookie、成绩基线、验证码、日志和故障状态；
- EasyConnect 登录配置和 VPN 会话；
- `.env`、测试缓存、本项目容器、网络和服务镜像。

不会删除 Git 仓库、源代码、Docker Desktop 或其他项目的数据。为了完整删除容器和镜像，执行清理时应保持 Docker Desktop 运行。

## 已知边界

- 手机短信验证码和正方图片验证码必须由用户本人完成，项目不会识别或绕过。
- 当前默认地址和明文密码兼容模式针对中国矿业大学；其他学校需要调整配置并重新验证。
- EasyConnect 使用第三方容器镜像，Compose 已固定不可变摘要；升级镜像前应重新做完整兼容性测试。
- Docker Desktop 重启后服务不会自动恢复，这是避免后台自动连接校园 VPN 的安全选择。
