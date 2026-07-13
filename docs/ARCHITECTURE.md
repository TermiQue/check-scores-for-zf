# 架构与实现说明

## 组件

### `easyconnect`

使用固定摘要的 `hagb/docker-easyconnect` 镜像，在独立容器中运行深信服客户端。该容器拥有 `/dev/net/tun` 和 `NET_ADMIN`。noVNC 通过 `127.0.0.1:18080` 暴露给本机，用于人工完成隐私确认、账号密码和短信验证。

### `checker`

Python 3.12 容器，入口为 `python -m zfcheck run`。它通过 Compose 的 `network_mode: service:easyconnect` 共享 VPN 容器网络，访问正方时不经过应用层 HTTP 代理。ShowDoc 通知使用单独 Session 且不继承代理环境。

checker 以 UID 10001 运行，根文件系统只读，唯一持久化写入位置是 `/data`。

## 请求路径

```text
Zhengfang request
checker -> shared network namespace -> EasyConnect tunnel -> campus

Notification request
checker -> shared namespace public route -> Docker/Windows -> push.showdoc.com.cn
```

这种网络命名空间隔离不依赖 Windows 静态路由，也不会与 Clash Fake-IP 网段竞争。实测 HTTP 代理会导致矿大正方登录链路的 `JSESSIONID` 在请求间变化，因此 checker 必须共享网络并直接连接。

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

检查异常会根据 `tun0` 和错误内容分为 VPN 断开、正方不可用、登录过期和未知错误。同类故障默认 6 小时内不重复发送，类型变化立即通知；恢复时发送一次恢复通知。VPN 或正方强制重新认证仍需要用户人工完成短信或图片验证码。

两个服务均配置 `restart: "no"`。Docker Desktop 重启后由用户手动运行 `windows-start.cmd`，启动器负责恢复 VPN、登录和后台 checker。
