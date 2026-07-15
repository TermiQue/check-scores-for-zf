# 开发与测试

## 项目结构

```text
check-scores-for-zf/
├── zfcheck/                  # Python 成绩检查服务
│   ├── __main__.py           # run / probe / once / notify-test 等 CLI
│   ├── config.py             # 配置读取
│   ├── model.py              # 成绩快照、比对与格式化
│   ├── notifier.py           # ShowDoc Push / stdout 通知
│   ├── service.py            # 查询、心跳、故障与恢复逻辑
│   └── state.py              # SQLite 状态持久化
├── scripts/zfn_api.py        # 正方教务 API 客户端
├── tests/                    # Python 单元测试
├── compose.easyconnect.yml   # 基础服务定义
├── compose.host.yml          # Docker Desktop Host 网络叠加
├── compose.vpn.yml           # EasyConnect 共享网络叠加
├── Dockerfile                # checker 镜像
├── windows-launcher.cmd      # 用户统一入口
├── windows-launcher.ps1      # Windows 编排逻辑
├── windows-setup.ps1         # 凭证配置
└── windows-ui.ps1            # 两态 UI、动态进度与 WinForms 支持
```

组件、请求路径和状态模型的详细说明见[技术架构](ARCHITECTURE.md)。

## 运行测试

项目测试以标准库 `unittest` 编写。推荐在 checker 镜像中运行，以使用与生产一致的 Python 和依赖：

```powershell
docker compose -f .\compose.easyconnect.yml build checker
docker run --rm --entrypoint python `
  -v "${PWD}:/workspace" -w /workspace `
  zf-check-scores:windows -m unittest discover -s tests -v
```

验证 Compose 文件：

```powershell
docker compose -f .\compose.easyconnect.yml config --quiet
docker compose -f .\compose.easyconnect.yml -f .\compose.host.yml config --quiet
docker compose -f .\compose.easyconnect.yml -f .\compose.vpn.yml --profile vpn config --quiet
```

Windows 脚本需要兼容 Windows PowerShell 5.1：

- `.ps1` 使用带 BOM 的 UTF-8；
- `.cmd` 使用无 BOM 的 UTF-8 和 CRLF；
- 中文动态行使用 ANSI 清行后重绘，避免 Windows Terminal 双宽字符重叠；
- 重定向输出时自动关闭 ANSI 真彩色和后台旋转动画。

## 发布前检查

```powershell
git diff --check
git status --short
git grep -n -I -E "你的学号|你的Token|你的密码"
```

发布前还应从隐私清除后的全新状态走完一次 [Windows 部署流程](../WINDOWS-CONTAINER-VPN.md)。

## 上游项目

本项目基于以下开源项目改造：

- [NianBroken/ZFCheckScores](https://github.com/NianBroken/ZFCheckScores)
- [openschoolcn/zfn_api](https://github.com/openschoolcn/zfn_api)

## 许可证

代码按仓库中的 [Apache License 2.0](../LICENSE) 发布。分发修改版本时请保留原作者版权、许可证和修改说明。
