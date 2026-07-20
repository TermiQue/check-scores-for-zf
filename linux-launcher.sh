#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

BASE_COMPOSE=(docker compose -f compose.easyconnect.yml)
HOST_COMPOSE=(docker compose -f compose.easyconnect.yml -f compose.host.yml)
VPN_COMPOSE=(docker compose -f compose.easyconnect.yml -f compose.vpn.yml --profile vpn)

VPN_ADDRESS="https://newvpn.cumt.edu.cn"
CAPTCHA_FILE="$ROOT_DIR/runtime-data/kaptcha.png"
MODE_FILE="$ROOT_DIR/runtime-data/linux-network-mode"

info() { printf '[信息] %s\n' "$*"; }
ok() { printf '[成功] %s\n' "$*"; }
warn() { printf '[注意] %s\n' "$*" >&2; }
die() { printf '[失败] %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<'EOF'
正方成绩检查服务 · Linux 启动器

用法：
  bash linux-launcher.sh setup        配置或更新账号、密码和推送 Token
  bash linux-launcher.sh start        自动选择直连或容器 VPN 并启动服务
  bash linux-launcher.sh stop         停止全部项目容器
  bash linux-launcher.sh status       查看容器状态
  bash linux-launcher.sh logs         查看最近 120 行日志
  bash linux-launcher.sh follow       实时查看日志（Ctrl+C 退出）
  bash linux-launcher.sh notify-test  发送一条测试通知
  bash linux-launcher.sh help         显示本帮助

远程服务器使用容器 VPN 时，需要在本地电脑另开一个终端执行：
  ssh -L 18080:127.0.0.1:18080 用户名@服务器地址
EOF
}

require_docker() {
    command -v docker >/dev/null 2>&1 || \
        die "未找到 Docker，请先安装 Docker Engine 和 Compose 插件。"
    docker info >/dev/null 2>&1 || \
        die "Docker 服务不可用；请启动 Docker，或确认当前用户有权访问 Docker。"
    docker compose version >/dev/null 2>&1 || \
        die "未找到 Docker Compose 插件。"
}

prepare_directories() {
    mkdir -p secrets runtime-data easyconnect-data
    chmod 700 secrets runtime-data easyconnect-data 2>/dev/null || true
    if [[ ! -f .env ]]; then
        cp .env.example .env
        chmod 600 .env 2>/dev/null || true
        info "已从 .env.example 创建 .env。"
    fi
}

read_required() {
    local prompt="$1"
    local secret="${2:-false}"
    local value
    while true; do
        if [[ "$secret" == "true" ]]; then
            IFS= read -r -s -p "$prompt" value
            printf '\n' >&2
        else
            IFS= read -r -p "$prompt" value
        fi
        if [[ -n "$value" ]]; then
            REPLY="$value"
            return
        fi
        warn "输入不能为空。"
    done
}

setup_credentials() {
    prepare_directories

    read_required "教务学号：" false
    printf '%s' "$REPLY" > secrets/zf_username.txt
    REPLY=''

    read_required "教务密码（输入不会显示）：" true
    printf '%s' "$REPLY" > secrets/zf_password.txt
    REPLY=''

    read_required "ShowDoc Push Token 或完整推送地址（输入不会显示）：" true
    printf '%s' "$REPLY" > secrets/push_token.txt
    REPLY=''

    chmod 600 secrets/zf_username.txt secrets/zf_password.txt secrets/push_token.txt
    ok "凭据已写入本地 secrets 目录；该目录已被 Git 忽略。"
}

credentials_ready() {
    [[ -s secrets/zf_username.txt ]] && \
        [[ -s secrets/zf_password.txt ]] && \
        [[ -s secrets/push_token.txt ]]
}

build_checker() {
    info "正在构建成绩检查镜像……"
    "${BASE_COMPOSE[@]}" build checker || \
        die "镜像构建失败。若 Docker Hub 访问受限，请在 .env 中设置 PYTHON_BASE_IMAGE。"

    # checker 以 UID 10001 运行。使用镜像内的 root 只修正数据目录权限，
    # 避免要求部署用户在宿主机上额外执行 sudo chown。
    "${BASE_COMPOSE[@]}" run --rm --no-deps \
        --user 0 --entrypoint sh checker \
        -c 'chown -R 10001:10001 /data' >/dev/null
    ok "镜像和数据目录已准备完成。"
}

network_probe() {
    local -n compose_ref="$1"
    "${compose_ref[@]}" run --rm --no-deps checker network-probe
}

network_probe_quiet() {
    local -n compose_ref="$1"
    "${compose_ref[@]}" run --rm --no-deps checker network-probe \
        >/dev/null 2>&1
}

select_direct_mode() {
    info "正在检测 Docker Bridge 网络……"
    if network_probe_quiet BASE_COMPOSE; then
        SELECTED_MODE="direct"
        SELECTED_COMPOSE=("${BASE_COMPOSE[@]}")
        ok "Docker Bridge 可以访问教务系统。"
        return 0
    fi

    info "正在检测 Linux Host 网络……"
    if network_probe_quiet HOST_COMPOSE; then
        SELECTED_MODE="host"
        SELECTED_COMPOSE=("${HOST_COMPOSE[@]}")
        ok "Linux Host 网络可以访问教务系统。"
        return 0
    fi
    return 1
}

wait_for_vpn() {
    local deadline=$((SECONDS + 600))
    info "正在等待 VPN 连通教务系统，最长等待 10 分钟……"
    while (( SECONDS < deadline )); do
        if network_probe_quiet VPN_COMPOSE; then
            ok "VPN 已连接，教务系统可以访问。"
            return 0
        fi
        sleep 5
    done
    return 1
}

prepare_vpn() {
    info "直连不可用，正在启动隔离的 EasyConnect 容器……"
    "${VPN_COMPOSE[@]}" up -d easyconnect

    cat <<EOF

请在自己的电脑建立 SSH 隧道：
  ssh -L 18080:127.0.0.1:18080 用户名@服务器地址

然后在本地浏览器打开：
  http://127.0.0.1:18080/vnc.html?autoconnect=true&resize=scale

noVNC 密码由 .env 中的 EC_VNC_PASSWORD 指定。
在 EasyConnect 中连接：$VPN_ADDRESS
完成账号登录和短信验证后，本脚本会自动继续。

EOF

    wait_for_vpn || die "等待 VPN 连接超时，请检查 EasyConnect 页面和容器日志。"
    SELECTED_MODE="vpn"
    SELECTED_COMPOSE=("${VPN_COMPOSE[@]}")
}

interactive_login() {
    rm -f runtime-data/interactive-probe-success \
        runtime-data/interactive-probe-error.txt \
        runtime-data/captcha-answer.txt \
        "$CAPTCHA_FILE"

    cat <<EOF
正在验证教务登录。
如果需要图片验证码，程序会把图片保存到：
  $CAPTCHA_FILE
可在另一个终端用 scp/sftp 下载查看，然后回到当前终端输入验证码。
EOF

    "${SELECTED_COMPOSE[@]}" run --rm --no-deps checker interactive-probe || \
        die "教务登录验证失败。请检查账号密码、验证码和 runtime-data/interactive-probe-error.txt。"
    ok "教务账号登录验证成功。"
}

configure_vpn_relay() {
    local relay_id vpn_id relay_ip

    "${VPN_COMPOSE[@]}" up -d --no-deps push-relay
    relay_id="$("${VPN_COMPOSE[@]}" ps -q push-relay | head -n 1)"
    vpn_id="$("${VPN_COMPOSE[@]}" ps -q easyconnect | head -n 1)"
    [[ -n "$relay_id" && -n "$vpn_id" ]] || \
        die "无法确定 push-relay 或 EasyConnect 容器。"

    relay_ip="$(docker inspect --format \
        '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' \
        "$relay_id")"
    [[ -n "$relay_ip" ]] || die "无法获取 push-relay 的 Docker 内部地址。"

    docker exec "$vpn_id" ip route replace "$relay_ip/32" dev eth0 || \
        die "无法建立 VPN 到推送中继的直连路由。"
    PUSH_RELAY_URL="http://${relay_ip}:8765/notify"
    export PUSH_RELAY_URL
    ok "微信推送中继路由已建立。"
}

start_service() {
    require_docker
    prepare_directories
    if ! credentials_ready; then
        info "尚未配置凭据，先进入首次配置。"
        setup_credentials
    fi

    build_checker
    "${BASE_COMPOSE[@]}" --profile vpn stop checker >/dev/null 2>&1 || true

    if ! select_direct_mode; then
        prepare_vpn
    else
        "${VPN_COMPOSE[@]}" stop easyconnect push-relay >/dev/null 2>&1 || true
    fi

    info "再次确认所选网络通道……"
    network_probe SELECTED_COMPOSE || die "所选网络通道无法访问教务系统。"
    interactive_login

    if [[ "$SELECTED_MODE" == "vpn" ]]; then
        configure_vpn_relay
    fi

    "${SELECTED_COMPOSE[@]}" up -d --no-deps checker
    printf '%s\n' "$SELECTED_MODE" > "$MODE_FILE"
    chmod 600 "$MODE_FILE" 2>/dev/null || true
    "${SELECTED_COMPOSE[@]}" ps
    ok "服务启动完成，网络模式：$SELECTED_MODE。"
    warn "当前 Compose 配置不会在服务器重启后自动恢复；重启后请再次运行 start。"
}

stop_service() {
    require_docker
    "${BASE_COMPOSE[@]}" --profile vpn down
    ok "全部项目容器已停止；凭据、Cookie 和成绩基线均已保留。"
}

status_service() {
    require_docker
    "${BASE_COMPOSE[@]}" --profile vpn ps
    if [[ -f "$MODE_FILE" ]]; then
        info "上次选择的网络模式：$(<"$MODE_FILE")"
    fi
}

logs_service() {
    require_docker
    "${BASE_COMPOSE[@]}" --profile vpn logs --tail 120 \
        checker easyconnect push-relay
}

follow_logs() {
    require_docker
    "${BASE_COMPOSE[@]}" --profile vpn logs -f --tail 120 \
        checker easyconnect push-relay
}

load_saved_compose() {
    local mode="direct"
    [[ -f "$MODE_FILE" ]] && mode="$(<"$MODE_FILE")"
    case "$mode" in
        direct) SELECTED_COMPOSE=("${BASE_COMPOSE[@]}") ;;
        host) SELECTED_COMPOSE=("${HOST_COMPOSE[@]}") ;;
        vpn) SELECTED_COMPOSE=("${VPN_COMPOSE[@]}") ;;
        *) die "未知的已保存网络模式：$mode" ;;
    esac
}

notify_test() {
    require_docker
    prepare_directories
    credentials_ready || die "尚未配置凭据，请先运行 setup。"
    load_saved_compose

    if [[ -f "$MODE_FILE" && "$(<"$MODE_FILE")" == "vpn" ]]; then
        configure_vpn_relay
    fi
    "${SELECTED_COMPOSE[@]}" run --rm --no-deps checker notify-test
}

main() {
    local action="${1:-help}"
    case "$action" in
        setup) require_docker; setup_credentials; build_checker ;;
        start) start_service ;;
        stop) stop_service ;;
        status) status_service ;;
        logs) logs_service ;;
        follow) follow_logs ;;
        notify-test) notify_test ;;
        help|-h|--help) usage ;;
        *) usage >&2; die "未知操作：$action" ;;
    esac
}

main "$@"
