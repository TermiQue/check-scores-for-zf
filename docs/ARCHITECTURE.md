# 架构与实现说明

## Compose 文件叠加

项目使用三个 Compose 文件，通过 `-f` 参数按需叠加，而不是在不同文件中重复完整定义：

| 文件 | 职责 |
| --- | --- |
| `compose.easyconnect.yml` | 基础定义。包含 `checker` 服务（默认 bridge 网络）和 `easyconnect` 服务（`vpn` profile，默认不启动）。 |
| `compose.host.yml` | 叠加文件。将 checker 的 `network_mode` 改为 `host`，用于 Docker Desktop Host 网络直连。 |
| `compose.vpn.yml` | 叠加文件。将 checker 的 `network_mode` 改为 `service:easyconnect`，并启用 `vpn` profile 以启动 EasyConnect。 |

启动脚本按以下顺序选择 Compose 参数：

1. **`compose.easyconnect.yml`**（默认 bridge）—— 宿主机可达时优先尝试；
2. **`compose.easyconnect.yml` + `compose.host.yml`**（Host 网络）—— bridge 不通时尝试；
3. **`compose.easyconnect.yml` + `compose.vpn.yml` + `--profile vpn`**（共享 VPN 网络命名空间）—— 仅宿主机不可达时使用。

## 组件

### `easyconnect`

使用固定摘要的 `hagb/docker-easyconnect` 镜像，在独立容器中运行深信服客户端。该容器拥有 `/dev/net/tun` 和 `NET_ADMIN`。noVNC 通过 `127.0.0.1:18080` 暴露给本机，用于人工完成隐私确认、账号密码和短信验证。

容器配置了以下关键环境变量：

- `PING_ADDR_URL`：指向正方登录页，EasyConnect 内部每 300 秒请求一次以保持 VPN 活跃；
- `IPTABLES_LEGACY`：使用 iptables-legacy 兼容内核；
- `DISABLE_PKG_VERSION_XML`：禁用版本检查以加速启动。

EasyConnect 配置和 VPN 会话缓存持久化在 `easyconnect-data/`。

### `checker`

Python 3.12 容器，入口为 `python -m zfcheck run`。启动器根据实际连通性选择普通 Docker 网络、Docker Desktop Host 网络，或通过 `network_mode: service:easyconnect` 共享 VPN 网络。访问正方不经过应用层 HTTP 代理。ShowDoc 通知使用单独 Session 且不继承代理环境。

checker 以 UID 10001 运行，根文件系统只读，唯一持久化写入位置是 `/data`。

支持以下 CLI 命令：

| 命令 | 用途 |
| --- | --- |
| `run` | 常驻后台循环（默认） |
| `once` | 单次成绩检查并推送 |
| `probe` | 非交互式登录验证 |
| `interactive-probe` | 交互式登录验证（支持验证码窗口） |
| `network-probe` | 仅验证正方页面可达性 |
| `notify-test` | 发送微信测试通知 |

## 请求路径

### 网络模式选择流程

启动脚本 `windows-start.ps1` 按以下决策树选择网络模式：

```text
Windows 宿主机能否访问正方登录页？
├── 是 → Docker bridge 能否访问正方？
│   ├── 是 → 模式 1：bridge 直连（compose.easyconnect.yml）
│   └── 否 → Docker Host 网络能否访问正方？
│       ├── 是 → 模式 2：Host 网络直连（+ compose.host.yml）
│       └── 否 → 报错：请启用 Host networking（不启动容器 VPN）
└── 否 → 已有 EasyConnect 容器能否访问正方？
    ├── 是 → 模式 3：复用现有 VPN（+ compose.vpn.yml）
    └── 否 → 启动 EasyConnect → 用户完成短信验证 → 模式 3
```

### 三种模式的请求路径

```text
模式 1 — bridge 直连
checker → Docker bridge → Windows/校园网 → 正方

模式 2 — Host 网络直连
checker → Docker Desktop host network → Windows/VPN → 正方

模式 3 — 容器 VPN
checker → 共享网络命名空间 → EasyConnect 隧道 → 正方

通知请求（所有模式）
checker → 共享命名空间公网路由 → Docker/Windows → push.showdoc.com.cn
```

### 设计考量

VPN 网络命名空间隔离不依赖 Windows 静态路由，也不会与 Clash Fake-IP 网段竞争。实测应用层 HTTP 代理会导致矿大正方登录链路的 `JSESSIONID` 在请求间变化，因此 VPN 模式采用共享网络命名空间而非 HTTP 代理。

## 数据模型

成绩快照以课程键值对字典存储，每个课程取以下字段的子集：

```python
SNAPSHOT_FIELDS = (
    "class_id",           # 教学班 ID（主键）
    "title",              # 课程名称
    "teacher",            # 教师
    "grade",              # 成绩（等级制或数值）
    "percentage_grades",  # 百分制成绩
    "credit",             # 学分
    "xfjd",               # 学分绩点
    "submission_time",    # 成绩提交时间
    "name_of_submitter",  # 提交人
    "course_year",        # 学年
    "course_semester",    # 学期
)
```

主键策略：优先使用 `class_id`（教学班 ID）；`class_id` 为空时使用 `学年|学期|课程名|教师` 组合键。

`state.db`（SQLite）中的键值对：

| 键 | 内容 |
| --- | --- |
| `login_cookies` | 正方会话 Cookie（JSON） |
| `snapshot` | 上一次成功推送的成绩快照（JSON） |
| `snapshot_hash` | 快照 SHA-256 哈希 |
| `last_success_at` | 最后一次成功检查时间（ISO 8601） |
| `failure_active` | 当前是否有活跃故障（`"1"` 或不存在） |
| `failure_kind` | 故障类型：`vpn` / `zhengfang` / `session` / `unknown` |
| `failure_title` | 故障通知标题（用于恢复通知） |
| `last_failure_alert_at:{kind}` | 各类型故障上次通知时间戳 |

## Windows 启动脚本

启动脚本 `windows-start.ps1` 是编排核心，负责：

1. 检查 Docker Desktop 运行状态；
2. 首次运行时调用 `windows-setup.ps1` 收集账号和推送凭证；
3. 构建 checker 镜像；
4. 按决策树选择网络模式并验证正方可达性；
5. 需要时启动 EasyConnect 并引导用户完成短信验证；
6. 使用 `interactive-probe` 命令验证正方登录，同时通过验证码文件 (`captcha-answer.txt`) 与 WinForms 弹窗交互；
7. 以选定的 Compose 参数启动 checker 后台服务。

进度显示通过 `windows-ui.ps1` 中的 `Invoke-DockerWithProgress` 函数实现，该函数包装 Docker CLI 调用，提供动态进度条、耗时统计和友好的中文错误翻译。Docker 正常输出被收纳，仅在失败时显示最后 12 行诊断信息。

## 登录状态

正方客户端首次登录后，将 Cookie 以 JSON 存入 `runtime-data/state.db`。新容器启动时先加载 Cookie；成绩接口返回会话失效代码时，程序清除 Cookie 并重新进入登录流程。

交互式 `interactive-probe` 保存验证码图片后，可通过 `/data/captcha-answer.txt` 接收 Windows 启动器的 WinForms 输入；文件读取后立即删除。保留 CLI 输入作为诊断后备。常驻 `run` 模式不会自动识别或绕过验证码。

## 定时循环

服务启动后立即执行一次成绩检查。之后：

- 成绩检查间隔为 1800 秒，并加入 0 到 120 秒抖动；
- 教务会话心跳间隔为 300 秒；
- VPN 容器另有 300 秒网络心跳。

## 一致性与通知顺序

课程数据先规范化，再用课程编号作为主键比较；缺少编号时使用学年、学期、课程名和教师组成备用键。

首次检查的事务顺序是：

1. 获取并规范化全部课程；
2. 发送“首次成绩同步”通知；
3. 推送成功后保存成绩基线。

后续变化同样先推送、后写入新快照。这样推送接口失败时不会丢失待通知变化，下次检查会再次尝试。

变化通知包含按提交时间从新到旧排列的完整当前成绩单；新增和更新记录分别标注类型，未变化课程不标注，移除记录追加在末尾。

状态数据库还保存最后成功时间、Cookie、快照哈希和故障通知冷却状态。空成绩列表不会覆盖已有非空快照，避免教务接口异常造成“全部成绩被删除”的误报。

## 故障策略

检查异常会结合 `ZF_NETWORK_MODE`、`tun0` 和错误内容分为 VPN 断开、正方不可用、登录过期和未知错误。直连模式不会因为缺少 `tun0` 被误报为 VPN 断开。同类故障默认 6 小时内不重复发送，类型变化立即通知；恢复时发送一次恢复通知。VPN 或正方强制重新认证仍需要用户人工完成短信或图片验证码。

两个服务均配置 `restart: "no"`。Docker Desktop 重启后由用户手动运行 `windows-start.cmd`，启动器负责恢复 VPN、登录和后台 checker。

## 安全模型

- **凭证隔离**：正方账号、密码和 ShowDoc Token 通过 Docker Compose `secrets` 机制以文件形式挂载到 `/run/secrets/`，不进入环境变量或镜像层；
- **网络隔离**：VPN 能力仅授予 EasyConnect 容器（`/dev/net/tun` + `NET_ADMIN`）；checker 在直连模式下不使用 VPN 网络；
- **只读文件系统**：checker 容器根文件系统 `read_only: true`，仅 `/data` 可写，`/tmp` 使用 tmpfs；
- **非 root 运行**：checker 以 UID 10001 运行，不拥有特权；
- **noVNC 绑定**：EasyConnect 的 noVNC 仅监听 `127.0.0.1:18080`，不暴露到局域网；
- **通知隔离**：ShowDoc 推送使用独立 `requests.Session`，设置 `trust_env = False` 不继承系统代理；
- **隐私路径保护**：`secrets/`、`runtime-data/`、`easyconnect-data/` 和 `.env` 均加入 `.gitignore`；
- **验证码不可绕过**：短信验证码和图片验证码必须由用户本人完成，项目不会识别或绕过。
