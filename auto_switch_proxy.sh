#!/usr/bin/env bash
#
# 自动检测并切换代理节点脚本
# 当网络不通时自动切换到自动选择组
#

set -e

LOG_DIR="/home/kali/TMP"
CLASH_CTL="/home/kali/Project/clash-verge-rev/clash-ctl"
SOCKET="/tmp/verge/verge-mihomo.sock"
PROXY_PORT="7897"
LOG_FILE="${LOG_DIR}/cronjob_network_$(date '+%Y%m%d_%H%M%S').log"

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# 检查网络连通性
check_network() {
    log "检查网络连通性..."
    
    # 直接使用代理端口，不使用unix socket
    local http_code
    http_code=$(curl -s -x http://127.0.0.1:$PROXY_PORT -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 10 https://www.google.com 2>/dev/null)
    
    if [ "$http_code" = "200" ]; then
        log "网络连通正常 (HTTP $http_code)，结束任务"
        return 0
    else
        log "网络不通 (HTTP $http_code)，继续检测节点"
        return 1
    fi
}

# 获取当前节点信息
get_current_node() {
    curl -s --unix-socket "$SOCKET" http://localhost/proxies 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
proxies = data.get('proxies', {})
g = proxies.get('GLOBAL', {})
print(g.get('now', 'DIRECT'))
"
}

# 切换到自动选择组
switch_to_autoselect() {
    log "切换到自动选择组: GLOBAL -> ♻️ 自动选择"
    python3 "$CLASH_CTL" switch GLOBAL "♻️ 自动选择" 2>&1 | tee -a "$LOG_FILE"
    return $?
}

# 切换到手动选择组的第一个可用节点
switch_to_first_working() {
    log "尝试切换到手动选择组的第一个节点..."
    
    # 获取可用节点列表并测试
    local nodes_output
    nodes_output=$(python3 "$CLASH_CTL" list 2>/dev/null)
    
    # 提取 GLOBAL 组的节点列表
    local global_nodes
    global_nodes=$(echo "$nodes_output" | sed -n '/【GLOBAL】/,/【/p' | grep -oP '2025[^,]+' | head -n 5)
    
    if [ -z "$global_nodes" ]; then
        log "未找到 GLOBAL 组的节点"
        return 1
    fi
    
    log "GLOBAL 可用节点: $global_nodes"
    
    # 逐个尝试切换
    for node in $global_nodes; do
        log "尝试节点: $node"
        
        # 提取服务器地址（从节点名）
        local server
        server=$(echo "$node" | grep -oP '(cloudflare|sin|speed|marisalnc)[^ ]*' | head -1)
        
        if [ -n "$server" ]; then
            # 测试连通性
            if nc -z -w3 "$server" 443 2>/dev/null; then
                log "节点可达: $node"
                
                python3 "$CLASH_CTL" switch GLOBAL "$node" 2>&1 | tee -a "$LOG_FILE"
                return $?
            fi
        fi
    done
    
    log "未找到可用节点，尝试自动选择"
    return 1
}

# 主流程
main() {
    log "========== 开始自动切换代理任务 =========="
    
    # 获取当前节点
    local current_node
    current_node=$(get_current_node)
    log "当前节点: $current_node"
    
    # 步骤1: 检查网络连通性
    if check_network; then
        log "网络正常，任务结束"
        exit 0
    fi
    
    # 步骤2-5: 网络不通，切换节点
    log "步骤2: 尝试切换到备用节点"
    
    # 先尝试第一个可用节点
    if ! switch_to_first_working; then
        # 如果失败，使用自动选择
        log "步骤3: 使用自动选���组"
        switch_to_autoselect
    fi
    
    # 等待一下
    sleep 3
    
    # 步骤5: 验证网络
    log "验证网络..."
    if check_network; then
        log "网络恢复，任务完成"
        exit 0
    else
        log "网络仍然不通，任务结束"
        exit 1
    fi
}

main "$@"