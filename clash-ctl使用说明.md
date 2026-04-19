# Clash‑ctl 使用说明

本说明文档面向在 **Clash‑Verge** 环境下，通过 `clash‑ctl` 脚本对运行中的 Clash‑Verge 实例进行代理模式和节点切换的操作。

---

## 1. 前置条件

- 已通过系统代理（如 `http://127.0.0.1:7897`）启动 **Clash‑Verge**，进程在运行中。
- `clash‑ctl` 位于项目目录 `~/Project/clash-verge-rev/`，可直接使用 `python3 clash‑ctl …` 调用。
- `clash‑ctl` 默认通过 Unix socket ` /tmp/verge/verge‑mihomo.sock` 与 Clash‑Verge 交互，无需手动指定 socket（除非控制第二套实例）。
- 环境变量中已设置代理（`HTTP_PROXY/HTTPS_PROXY`），本脚本的网络请求会走该代理。

---

## 2. 基本命令概览

| 子命令 | 说明 | 示例 |
|--------|------|------|
| `mode <global|rule|direct>` | 切换全局模式：`global`（所有流量走代理），`rule`（规则匹配走代理），`direct`（关闭代理） | `python3 clash-ctl mode global` |
| `switch <group> <node-name>` | 将指定 **代理组**（如 `GLOBAL`、`PROXY`）切换到某个节点 | `python3 clash-ctl switch GLOBAL "20251228cf - cloudflare.182682.xyz-443-WS-TLS"` |
| `list` | 列出当前所有代理组及其中的节点名称，便于查找要切换的节点 | `python3 clash-ctl list` |
| `status` | 查看当前代理模式以及各组的选中节点 | `python3 clash-ctl status` |
| `-s/--socket <path>` | 当系统中有多个 Clash‑Verge 实例时，指定要控制的 Unix socket 路径（默认 `/tmp/verge/verge-mihomo.sock`） | `python3 clash-ctl -s /tmp/verge2/verge-mihomo.sock switch GLOBAL "node"` |

> **注意**：`clash-ctl` 只负责向 Clash‑Verge 发起 API 请求，不会重启或中断已有连接。

---

## 3. 常用工作流程（示例）

以下示例演示了从订阅获取节点、测试连通性、切换节点并验证公网 IP 变化的完整步骤。

### 3.1 获取节点列表（手动或脚本）
```bash
# 直接使用 clash-ctl list 查看已加载的节点（已通过订阅自动写入）
python3 clash-ctl list
```
> 输出会列出所有代理组（如 `GLOBAL`、`PROXY`）以及对应的节点名称。

### 3.2 测试目标节点连通性
```bash
# 以示例节点 cloudflare.182682.xyz 为例，使用 netcat 检测 443 端口
nc -z -w5 cloudflare.182682.xyz 443 && echo ok || echo fail
```
> 若返回 `ok`，说明节点 TCP 端口可达，后续可安全切换。

### 3.3 切换节点
```bash
# 将 GLOBAL 组切换到示例节点
python3 /home/kali/Project/clash-verge-rev/clash-ctl \
    switch GLOBAL "20251228cf - cloudflare.182682.xyz-443-WS-TLS"
```
> 执行后会得到类似以下输出：
```
✓ 已切换 GLOBAL -> 20251228cf - cloudflare.182682.xyz-443-WS-TLS
```

### 3.4 验证公网 IP 是否变化
```bash
# 通过系统代理查询公网 IP（curl 使用代理端口 7897）
curl -s -x http://127.0.0.1:7897 https://api.ipify.org
```
> 切换前后 IP 不同，即说明流量已经走新的代理节点。

---

## 4. 完整实例记录（本次操作日志）
```
1️⃣ 当前公网 IP（切换前）: 157.245.200.76
2️⃣ 选取的节点: 20251228cf - cloudflare.182682.xyz-443-WS-TLS (属于 GLOBAL 组)
3️⃣ 连通性测试: ok (nc -z -w5 cloudflare.182682.xyz 443)
4️⃣ 节点切换命令: 
   python3 /home/kali/Project/clash-verge-rev/clash-ctl switch GLOBAL "20251228cf - cloudflare.182682.xyz-443-WS-TLS"
   → ✓ 已切换 GLOBAL -> 20251228cf - cloudflare.182682.xyz-443-WS-TLS
5️⃣ 切换后公网 IP: 164.52.1.179
```

---

## 5. 常见坑点 & 解决方案

| 症状 | 可能原因 | 解决方案 |
|------|----------|----------|
| `clash-ctl: command not found` | 脚本未加入 `$PATH` 或未使用 `python3` 调用 | 使用完整路径 `python3 /path/to/clash-ctl` 或将脚本所在目录加入 `PATH` |
| 节点切换后 IP 未变化 | 代理组不是当前使用的组，或系统代理变量未指向 Clash‑Verge | 确认使用的 `mode` 为 `global` 或对应组已在规则中生效；检查 `HTTP_PROXY/HTTPS_PROXY` 是否指向 `127.0.0.1:7897` |
| `nc: command not found` | 系统缺少 netcat 包 | `sudo apt-get install netcat`（Debian/Ubuntu 系统） |
| 多实例冲突 | 两套 Clash‑Verge 共用同一 socket/端口 | 为第二套实例修改 `external-controller`（或 `unix-socket`）路径，并使用 `-s/--socket` 指定不同 socket |

---

## 6. 脚本化（可选）
如果需要一次性完成 **获取可用节点 → 自动测速 → 选取最低延迟节点 → 自动切换**，可参考下面的简易 Bash 脚本（自行保存为 `auto-switch.sh` 并 `chmod +x`）：

```bash
#!/usr/bin/env bash

SUBS_URL="https://20260215.1770164.xyz/profiles/0dab8a00-6ef6-4e64-a4be-20f047a8f28e?target=clash&builtin=1"
TMP_JSON="/tmp/clash_nodes.json"

# 1. 下载订阅（使用系统代理）
curl -s -x http://127.0.0.1:7897 "$SUBS_URL" -o "$TMP_JSON"

# 2. 解析节点名称和服务器（这里只演示提取前 10 条）
awk '/name:/ {print $2}' "$TMP_JSON" | head -n 10 > /tmp/node_names.txt
awk '/server:/ {print $2}' "$TMP_JSON" | head -n 10 > /tmp/node_hosts.txt

best_node=""
best_latency=9999

while read -r name && read -r host <&3; do
    latency=$(nc -z -w5 "$host" 443 2>/dev/null && echo 0 || echo 9999)
    # 简单的可连通性检测，实际可改为 `curl -o /dev/null -s -w "%{time_total}" -x http://127.0.0.1:7897 https://$host`
    if [[ $latency -eq 0 && $latency -lt $best_latency ]]; then
        best_latency=$latency
        best_node="$name"
    fi
done < /tmp/node_names.txt 3< /tmp/node_hosts.txt

if [[ -n $best_node ]]; then
    echo "选中节点: $best_node (latency: $best_latency)"
    python3 /home/kali/Project/clash-verge-rev/clash-ctl switch GLOBAL "$best_node"
else
    echo "未找到可用节点"
fi
```
> 该脚本仅作示例，实际项目中可使用更精准的 HTTP 延迟检测或 `clash-ctl list` 的 JSON 输出进行筛选。

---

## 7. 参考链接
- **Clash‑Verge 官方文档**： https://github.com/zzzgydi/clash-verge-rev
- **clash‑ctl 源码**（本项目 `clash-ctl` 脚本所在路径）
- **Clash‑Meta 配置格式**： https://github.com/MetaCubeX/Clash.Meta/wiki/Configuration-File

---

**祝使用顺利** 🚀
