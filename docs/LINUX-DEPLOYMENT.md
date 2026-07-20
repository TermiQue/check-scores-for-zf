# Linux 部署与启动器

项目提供 `linux-launcher.sh`，用于在安装了 Docker Engine 与 Docker Compose
插件的 x86-64 Linux 服务器上完成首次配置、网络选择、登录验证和日常运维。
使用容器 VPN 时需要普通（非 rootless）Docker，并且主机应提供 `/dev/net/tun`；
只使用直连模式时没有这项要求。

## 快速开始

```bash
git clone https://github.com/TermiQue/check-scores-for-zf.git
cd check-scores-for-zf
chmod +x linux-launcher.sh
./linux-launcher.sh start
```

首次启动会要求输入：

1. 正方教务学号；
2. 正方教务密码；
3. ShowDoc Push Token 或完整推送地址。

凭据保存在被 Git 忽略的 `secrets/` 目录，不会写入镜像或普通环境变量。

## 网络选择

启动器依次检测：

1. Docker Bridge 直连；
2. Linux Host 网络直连；
3. 隔离的 EasyConnect 容器 VPN。

只有两种直连方式都无法访问教务系统时，才会启动 EasyConnect。

### 远程登录容器 VPN

EasyConnect 的 noVNC 端口只监听服务器的 `127.0.0.1:18080`。在自己的电脑
另开终端，通过 SSH 隧道访问：

```bash
ssh -L 18080:127.0.0.1:18080 用户名@服务器地址
```

然后在本地浏览器打开：

```text
http://127.0.0.1:18080/vnc.html?autoconnect=true&resize=scale
```

noVNC 密码在 `.env` 的 `EC_VNC_PASSWORD` 中配置。EasyConnect 的服务器地址为：

```text
https://newvpn.cumt.edu.cn
```

完成账号登录和短信验证后，启动器会自动检测 VPN 是否已经连通。

## 教务图片验证码

如果教务系统要求图片验证码，图片会保存为：

```text
runtime-data/kaptcha.png
```

可以在另一个终端通过 `scp` 或 SFTP 下载并查看，再回到启动器所在终端输入
验证码。验证码必须由用户本人完成，项目不会识别或绕过。

## 日常命令

```bash
# 启动或恢复服务
./linux-launcher.sh start

# 查看状态
./linux-launcher.sh status

# 查看最近日志
./linux-launcher.sh logs

# 实时日志，按 Ctrl+C 退出
./linux-launcher.sh follow

# 测试微信通知
./linux-launcher.sh notify-test

# 更新账号、密码或推送 Token
./linux-launcher.sh setup

# 停止服务但保留本地状态
./linux-launcher.sh stop
```

## 服务器重启

项目的容器保持 `restart: "no"`。服务器或 Docker 重启后，应再次运行：

```bash
./linux-launcher.sh start
```

这是有意的安全策略：EasyConnect 可能需要短信验证，教务登录也可能需要图片
验证码。VPN 容器重建后，启动器还会重新建立独立的微信推送路由。

## 数据与权限

启动器会创建并保护以下本地目录：

| 路径 | 内容 |
| --- | --- |
| `secrets/` | 教务账号、密码和推送 Token |
| `runtime-data/` | Cookie、成绩基线、验证码、日志和状态数据库 |
| `easyconnect-data/` | EasyConnect 配置、VPN 会话和缓存 |

构建完成后，启动器会在容器内把 `runtime-data/` 修正为 checker 使用的 UID
`10001`，通常无需在宿主机手动执行 `sudo chown`。
