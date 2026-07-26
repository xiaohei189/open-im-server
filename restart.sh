#!/bin/bash
# OpenIM Server 本地启动/重启脚本
# 每个服务可独立启动/停止/重启
# 日志输出: ./_output/logs/
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_DIR="$SCRIPT_DIR/_output/logs"
BIN_DIR="$SCRIPT_DIR/_output/bin/platforms/linux/amd64"
mkdir -p "$LOG_DIR"
export PATH=$PATH:/usr/local/go/bin:/home/weirui/go/bin

# 所有服务
ALL_SERVICES=(
    "openim-api"
    "openim-msggateway"
    "openim-rpc-auth"
    "openim-rpc-user"
    "openim-rpc-friend"
    "openim-rpc-group"
    "openim-rpc-msg"
    "openim-rpc-conversation"
    "openim-rpc-third"
    "openim-push"
    "openim-msgtransfer"
    "openim-crontask"
)

# 服务分组
CORE_SERVICES=("openim-api" "openim-msggateway")
RPC_SERVICES=("openim-rpc-auth" "openim-rpc-user" "openim-rpc-friend" "openim-rpc-group" "openim-rpc-msg" "openim-rpc-conversation" "openim-rpc-third")
WORKER_SERVICES=("openim-push" "openim-msgtransfer" "openim-crontask")

usage() {
    echo "用法: $0 <命令> [服务名]"
    echo ""
    echo "命令:"
    echo "  start [服务名|组名|all]   - 启动服务"
    echo "  stop  [服务名|组名|all]   - 停止服务"
    echo "  restart [服务名|组名|all] - 重启服务（先停后启）"
    echo "  status [服务名]           - 查看状态"
    echo "  log   [服务名]            - 实时查看日志"
    echo "  build                     - 重新构建所有二进制"
    echo ""
    echo "服务名: ${ALL_SERVICES[*]}"
    echo ""
    echo "组名:"
    echo "  core    - 核心服务 (api, msggateway)"
    echo "  rpc     - RPC 服务 (7 个)"
    echo "  worker  - Worker (push, msgtransfer, crontask)"
    echo "  all     - 所有服务"
    echo ""
    echo "示例:"
    echo "  $0 start openim-api          # 启动单个服务"
    echo "  $0 stop openim-rpc-msg       # 停止单个服务"
    echo "  $0 restart openim-api        # 重启单个服务"
    echo "  $0 start core                # 启动核心服务组"
    echo "  $0 start rpc                 # 启动所有 RPC"
    echo "  $0 start all                 # 启动所有服务"
    echo "  $0 status openim-api         # 查看单个服务状态"
    echo "  $0 log openim-api            # 查看单个服务日志"
    exit 1
}

# 获取服务对应的二进制路径
get_binary() {
    echo "$BIN_DIR/$1"
}

# 获取服务日志路径
get_log_file() {
    echo "$LOG_DIR/$1.log"
}

# 检查服务是否正在运行
is_running() {
    local service=$1
    local binary=$(get_binary "$service")
    pgrep -f "$binary" > /dev/null 2>&1
}

# 获取服务所有 PID
get_pids() {
    local service=$1
    local binary=$(get_binary "$service")
    pgrep -f "$binary" 2>/dev/null
}

# 获取服务第一个 PID（用于显示）
get_pid() {
    get_pids "$1" | head -1
}

# 启动单个服务
do_start_one() {
    local service=$1
    local binary=$(get_binary "$service")
    local log_file=$(get_log_file "$service")

    if [ ! -f "$binary" ]; then
        echo "  [ERROR] 二进制不存在: $binary"
        echo "  请先执行: $0 build"
        return 1
    fi

    if is_running "$service"; then
        echo "  [SKIP] $service 已在运行 (PID: $(get_pid "$service"))"
        return 0
    fi

    nohup "$binary" -i 0 -c "$SCRIPT_DIR/config/" > "$log_file" 2>&1 &
    echo "  [OK] $service (PID: $!)"
}

# 停止单个服务（杀掉所有实例）
do_stop_one() {
    local service=$1
    local pids=$(get_pids "$service")

    if [ -z "$pids" ]; then
        echo "  [SKIP] $service 未运行"
        return 0
    fi

    # 杀掉所有实例
    for pid in $pids; do
        kill "$pid" 2>/dev/null || true
    done
    sleep 1

    # 强制杀掉还活着的
    for pid in $pids; do
        if kill -0 "$pid" 2>/dev/null; then
            kill -9 "$pid" 2>/dev/null || true
        fi
    done

    echo "  [OK] $service 已停止 (${#pids[@]} 个实例)"
}

# 解析服务名/组名 -> 服务列表
resolve_services() {
    local name=$1
    case "$name" in
        all)
            echo "${ALL_SERVICES[@]}"
            ;;
        core)
            echo "${CORE_SERVICES[@]}"
            ;;
        rpc)
            echo "${RPC_SERVICES[@]}"
            ;;
        worker)
            echo "${WORKER_SERVICES[@]}"
            ;;
        *)
            # 检查是否是合法服务名
            for s in "${ALL_SERVICES[@]}"; do
                if [ "$s" = "$name" ]; then
                    echo "$name"
                    return
                fi
            done
            echo ""
            ;;
    esac
}

# 批量启动
do_start() {
    local target=${1:-all}
    local services
    read -ra services <<< "$(resolve_services "$target")"

    if [ ${#services[@]} -eq 0 ]; then
        echo "[ERROR] 未知服务或组: $target"
        echo "可用服务: ${ALL_SERVICES[*]}"
        echo "可用组: core, rpc, worker, all"
        exit 1
    fi

    echo "=== 启动 ${#services[@]} 个服务 ($target) ==="
    for service in "${services[@]}"; do
        do_start_one "$service"
    done
    echo ""
}

# 批量停止
do_stop() {
    local target=${1:-all}
    local services
    read -ra services <<< "$(resolve_services "$target")"

    if [ ${#services[@]} -eq 0 ]; then
        echo "[ERROR] 未知服务或组: $target"
        exit 1
    fi

    echo "=== 停止 ${#services[@]} 个服务 ($target) ==="
    for service in "${services[@]}"; do
        do_stop_one "$service"
    done
    echo ""
}

# 重启
do_restart() {
    local target=${1:-all}
    do_stop "$target"
    sleep 1
    do_start "$target"
}

# 状态
do_status() {
    local target=${1:-all}

    if [ "$target" != "all" ]; then
        local services
        read -ra services <<< "$(resolve_services "$target")"
        if [ ${#services[@]} -eq 0 ]; then
            echo "[ERROR] 未知服务或组: $target"
            exit 1
        fi
    else
        services=("${ALL_SERVICES[@]}")
    fi

    echo "=== 服务状态 ==="
    printf "%-30s %-10s %-10s %s\n" "服务" "状态" "PID" "日志"
    printf "%-30s %-10s %-10s %s\n" "------------------------------" "----------" "----------" "----"

    for service in "${services[@]}"; do
        local pid=$(get_pid "$service")
        local log_file=$(get_log_file "$service")
        if [ -n "$pid" ]; then
            printf "%-30s %-10s %-10s %s\n" "$service" "RUNNING" "$pid" "$log_file"
        else
            printf "%-30s %-10s %-10s %s\n" "$service" "STOPPED" "-" "$log_file"
        fi
    done

    echo ""
    echo "=== 端口 ==="
    ss -tlnp | grep -E "10001|10002"
}

# 查看日志
do_log() {
    local service=${1:-openim-api}
    local log_file=$(get_log_file "$service")

    if [ -f "$log_file" ]; then
        tail -f "$log_file"
    else
        echo "日志文件不存在: $log_file"
        echo ""
        echo "可用服务:"
        for s in "${ALL_SERVICES[@]}"; do
            echo "  $s"
        done
    fi
}

# 构建
do_build() {
    echo "=== 构建 openim-server ==="
    cd "$SCRIPT_DIR"
    mage build 2>&1 | tail -10
    echo ""
    echo "=== 构建完成 ==="
    ls -la "$BIN_DIR/" 2>/dev/null | grep openim
}

# 主逻辑
case "${1:-}" in
    start)   do_start "${2:-all}" ;;
    stop)    do_stop "${2:-all}" ;;
    restart) do_restart "${2:-all}" ;;
    status)  do_status "${2:-all}" ;;
    log)     do_log "${2:-openim-api}" ;;
    build)   do_build ;;
    *)       usage ;;
esac
