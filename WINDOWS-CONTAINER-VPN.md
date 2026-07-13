# Windows 11 一键部署与使用手册

当前推荐方案是在 Docker 中同时运行 EasyConnect 和成绩检查器。Windows 原有网络及 Clash TUN 不需要修改，也不需要额外虚拟机。

## 准备内容

- Windows 11；
- 已启动的 Docker Desktop，使用 Linux Containers；
- 矿大 VPN 账号、密码和可接收短信的手机；
- 正方教务账号、密码；
- ShowDoc Push Token。

在 PowerShell 中确认 Docker 可用：

```powershell
docker version
docker compose version
```

## 一键启动

进入项目目录，双击：

```text
windows-start.cmd
```

也可以在 PowerShell 中运行：

```powershell
.\windows-start.cmd
```

启动程序会自动完成：

1. 检查 Docker Desktop 和 Windows 原生 EasyConnect；
2. 首次运行时询问正方账号、密码和 ShowDoc Token；
3. 构建 checker 镜像；
4. 启动 EasyConnect 容器；
5. VPN 未连接时打开 noVNC 页面并等待短信验证；
6. 验证校园 VPN 与正方网络；
7. 需要正方图片验证码时弹出 Windows 小窗口；
8. 登录成功后自动启动后台成绩检查服务。

不再需要依次运行 setup、POC、Compose 启动和日志四个命令。

## VPN 登录

首次运行或 VPN 会话失效时，浏览器会打开：

```text
http://127.0.0.1:18080/vnc.html
```

在 EasyConnect 页面中：

1. 接受隐私条款；
2. 服务器填写 `https://newvpn.cumt.edu.cn`；
3. 输入 VPN 账号和密码；
4. 完成手机短信验证；
5. 页面显示连接成功后，回到提示窗口点击“确定”。

noVNC 只监听本机 `127.0.0.1`，不会暴露到局域网。

## 正方验证码

需要图片验证码时，启动程序会自动弹出一个置顶窗口，直接显示图片和输入框。输入后按 Enter 或点击“确定”即可。

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
| `VPN 已断开` | EasyConnect 隧道或 VPN 路由不存在 | 运行 `windows-start.cmd`，在 EasyConnect 中重新登录并完成短信验证 |
| `正方教务不可用` | VPN 仍连接，但正方页面或接口异常 | 通常等待自动重试；持续失败时运行 `windows-start.cmd` 重新验证 |
| `正方登录已过期` | Cookie 失效，需要图片验证码 | 运行 `windows-start.cmd`，在弹窗中输入新验证码 |
| `未知错误` | 尚未分类的程序异常 | 查看 checker 日志，再运行 `windows-start.cmd` |

同类故障默认 6 小时内不重复推送；故障类型变化会立即通知。连接恢复后会发送一次恢复通知。

## 手动启动策略

EasyConnect 和 checker 都使用 `restart: "no"`。

这意味着：

- Docker Desktop 重启后，项目容器不会自行启动；
- Windows 开机后不会自动连接学校 VPN；
- 需要使用时手动双击 `windows-start.cmd`；
- 启动程序会复用已有 VPN 配置、正方 Cookie 和成绩基线。

这样可以避免用户没有主动使用时后台自动连接学校 VPN。

## 停止服务

双击：

```text
windows-stop.cmd
```

或者执行：

```powershell
docker compose -f .\compose.easyconnect.yml down
```

停止不会删除账号、VPN 配置、正方 Cookie 或成绩基线。

## 日常检查

查看容器状态：

```powershell
docker compose -f .\compose.easyconnect.yml ps
```

查看成绩检查日志：

```powershell
docker compose -f .\compose.easyconnect.yml logs --tail 100 checker
docker compose -f .\compose.easyconnect.yml logs -f checker
```

发送 ShowDoc 测试通知：

```powershell
docker compose -f .\compose.easyconnect.yml run --rm checker notify-test
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

## 常见问题

### Docker Desktop 没有启动

先启动 Docker Desktop，等待状态变为 Running，再重新运行 `windows-start.cmd`。

### 无法下载镜像

包含 `failed to resolve reference` 或 `Docker Desktop has no HTTPS proxy` 的错误属于 Docker Hub 网络问题。配置 Docker Desktop 代理或更换可访问 Docker Hub 的网络后重试。

### VPN 页面已经连接，但正方仍不可达

退出 Windows 原生 EasyConnect，确认当前登录的是容器 noVNC 页面中的 EasyConnect，然后重新运行 `windows-start.cmd`。

### 验证码窗口没有出现

窗口只在正方要求验证码时出现。若 Cookie 仍有效，程序会直接登录，不显示验证码。

## 安全边界

- 只有 EasyConnect 容器拥有 `/dev/net/tun` 和 `NET_ADMIN`；
- checker 共享网络命名空间，但以非 root 用户运行且根文件系统只读；
- EasyConnect HTTP/SOCKS 代理不发布到 Windows 或局域网；
- noVNC 仅绑定 `127.0.0.1`；
- ShowDoc 请求使用独立 Session，不继承系统代理环境；
- 短信验证码和图片验证码必须由用户本人完成。
