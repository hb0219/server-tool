#!/usr/bin/env bash
#===============================================================================
#  🇺🇳 Server Pro Menus  —  多功能 VPS 管理脚本
#  用法: bash <(curl -sL https://raw.githubusercontent.com/你的用户名/你的仓库/main/server.sh)
#===============================================================================
set -e
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

# ── 检测系统 ─────────────────────────────────────────────────────────────────
check_root() { [[ $EUID -eq 0 ]] || { echo -e "${RED}✘ 请用 root 运行${NC}"; exit 1; }; }
get_os() { . /etc/os-release 2>/dev/null; echo "$ID $VERSION_ID"; }
get_ip()  { curl -4s --connect-timeout 5 https://ipinfo.io/ip 2>/dev/null || hostname -I | awk '{print $1}'; }

# ── 菜单框架 ─────────────────────────────────────────────────────────────────
menu_header() {
    clear
    echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║       🇺🇳 Server Pro Menus  v1.0        ║${NC}"
    echo -e "${GREEN}╠══════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║  $(hostname)  |  $(get_ip)${NC}"
    echo -e "${GREEN}║  $(get_os)  |  正常运行 $(($(awk '{print $1}' /proc/uptime)/86400))天${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
    echo ""
}

menu_footer() { echo ""; read -p "按回车返回主菜单..."; }

# ── 工具函数 ─────────────────────────────────────────────────────────────────
run_cmd() { echo -e "${YELLOW}▶ $*${NC}"; eval "$*"; }

confirm() { read -p "$1 [y/N]: " c; [[ "$c" =~ ^[Yy]$ ]]; }

# ═══════════════════════════════════════════════════════════════════════════════
#  1. 系统信息
# ═══════════════════════════════════════════════════════════════════════════════
sys_info() {
    menu_header
    echo -e " ${YELLOW}━━━ 系统信息 ━━━${NC}"
    echo "  主机名:   $(hostname)"
    echo "  系统版本: $(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2 | tr -d '\"')"
    echo "  内核版本: $(uname -r)"
    echo "  运行时长: $(uptime -p)"
    echo ""
    echo -e " ${YELLOW}━━━ 硬件信息 ━━━${NC}"
    echo "  CPU:      $(lscpu 2>/dev/null | grep 'Model name' | cut -d: -f2 | xargs || echo 'N/A')"
    echo "  核心数:   $(nproc) 核心"
    echo "  内存:     $(free -h | awk '/^Mem/{print $3 \"/\" $2}')"
    echo "  交换区:   $(free -h | awk '/^Swap/{print $3 \"/\" $2}')"
    echo "  磁盘:     $(df -h / | awk 'NR==2{print $3 \"/\" $2 \" (\" $5 \")\"}')"
    echo ""
    echo -e " ${YELLOW}━━━ 网络信息 ━━━${NC}"
    echo "  IPv4:     $(get_ip)"
    echo "  IPv6:     $(ip -6 addr show | grep 'global' | awk '{print $2}' | cut -d/ -f1 | head -1 || echo '无')"
    echo "  ASN:      $(curl -s --connect-timeout 5 https://ipinfo.io/org 2>/dev/null || echo 'N/A')"
    echo "  BBR:       $(lsmod 2>/dev/null | grep -q bbr && echo '启用 ✅' || echo '未启用')"
    menu_footer
}

# ═══════════════════════════════════════════════════════════════════════════════
#  2. 安全检测
# ═══════════════════════════════════════════════════════════════════════════════
security_check() {
    menu_header
    echo -e " ${YELLOW}━━━ 安全检测 ━━━${NC}"
    local issues=0
    # SSH 端口
    local ssh_port=$(ss -tlnp | grep sshd | head -1 | awk '{print $4}' | cut -d: -f2)
    if [[ "$ssh_port" == "22" ]]; then
        echo -e "  ${RED}⚠  SSH 使用默认端口 22，建议改${NC}"; ((issues++))
    else
        echo -e "  ${GREEN}✅ SSH 端口: $ssh_port${NC}"
    fi
    # 密码登录
    if grep -q 'PasswordAuthentication yes' /etc/ssh/sshd_config 2>/dev/null; then
        echo -e "  ${YELLOW}⚠  SSH 允许密码登录，建议禁用${NC}"; ((issues++))
    else
        echo -e "  ${GREEN}✅ SSH 已禁用密码登录${NC}"
    fi
    # Ping
    if [[ $(cat /proc/sys/net/ipv4/icmp_echo_ignore_all 2>/dev/null) == "1" ]]; then
        echo -e "  ${GREEN}✅ Ping 已禁用${NC}"
    else
        echo -e "  ${YELLOW}⚠  Ping 未禁用${NC}"; ((issues++))
    fi
    # 防火墙
    if command -v nft &>/dev/null; then
        echo -e "  ${GREEN}✅ nftables${NC}"
    elif command -v iptables &>/dev/null; then
        echo -e "  ${GREEN}✅ iptables${NC}"
    else
        echo -e "  ${YELLOW}⚠  无防火墙${NC}"; ((issues++))
    fi
    # fail2ban
    if systemctl is-active fail2ban &>/dev/null; then
        echo -e "  ${GREEN}✅ fail2ban 运行中${NC}"
    else
        echo -e "  ${YELLOW}⚠  fail2ban 未运行${NC}"; ((issues++))
    fi
    # DNS 加密
    if resolvectl status 2>/dev/null | grep -q DNSOverTLS; then
        echo -e "  ${GREEN}✅ DNS over TLS${NC}"
    else
        echo -e "  ${YELLOW}⚠  DNS 未加密${NC}"; ((issues++))
    fi
    echo ""
    if [[ $issues -eq 0 ]]; then echo -e "  ${GREEN}🎉 全部安全，优秀！${NC}"
    else echo -e "  ${YELLOW}发现 $issues 项可优化${NC}"; fi
    menu_footer
}

# ═══════════════════════════════════════════════════════════════════════════════
#  3. TCP 调优
# ═══════════════════════════════════════════════════════════════════════════════
tcp_tune() {
    menu_header
    echo -e " ${YELLOW}━━━ TCP 调优 ━━━${NC}"
    echo "  当前拥塞算法: $(sysctl net.ipv4.tcp_congestion_control 2>/dev/null | awk '{print $3}')"
    echo "  当前队列算法: $(sysctl net.core.default_qdisc 2>/dev/null | awk '{print $3}')"
    echo ""
    echo "  1) 开启 BBR + fq"
    echo "  2) 深度优化（CN2 GIA / 9929 / CMIN2 专用）"
    echo "  3) 恢复默认"
    echo "  0) 返回"
    read -p "  请选择 [0-3]: " opt
    case $opt in
        1) echo "net.core.default_qdisc=fq" >> /etc/sysctl.d/99-bbr.conf 2>/dev/null
           echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.d/99-bbr.conf 2>/dev/null
           sysctl -p /etc/sysctl.d/99-bbr.conf 2>/dev/null
           echo -e "${GREEN}✅ BBR 已开启${NC}" ;;
        2) cat >> /etc/sysctl.d/99-tcp-optimize.conf <<EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_fastopen=3
net.core.rmem_max=134217728
net.core.wmem_max=134217728
net.ipv4.tcp_rmem=4096 87380 134217728
net.ipv4.tcp_wmem=4096 65536 134217728
net.ipv4.tcp_mtu_probing=1
net.ipv4.tcp_fin_timeout=15
net.ipv4.tcp_tw_reuse=1
net.core.somaxconn=65535
net.ipv4.tcp_notsent_lowat=131072
EOF
           sysctl -p /etc/sysctl.d/99-tcp-optimize.conf 2>/dev/null
           echo -e "${GREEN}✅ 深度优化完成${NC}" ;;
        3) rm -f /etc/sysctl.d/99-bbr.conf /etc/sysctl.d/99-tcp-optimize.conf 2>/dev/null
           sysctl -w net.ipv4.tcp_congestion_control=cubic 2>/dev/null
           echo -e "${GREEN}✅ 已恢复默认${NC}" ;;
        0) return ;;
    esac
    menu_footer
}

# ═══════════════════════════════════════════════════════════════════════════════
#  4. 一键安全加固
# ═══════════════════════════════════════════════════════════════════════════════
hardening() {
    menu_header
    echo -e " ${YELLOW}━━━ 一键安全加固 ━━━${NC}"
    echo "  将执行以下操作："
    echo "  • 关闭 ping"
    echo "  • 关闭 IPv6"
    echo "  • 关闭 TCP 时间戳"
    echo "  • 安装 fail2ban"
    echo "  • 配置 DNS over TLS"
    echo "  • 开启自动安全更新"
    echo ""
    if confirm "确认执行？"; then
        # 禁 ping
        echo "net.ipv4.icmp_echo_ignore_all=1" >> /etc/sysctl.d/99-security.conf 2>/dev/null
        # 关 IPv6
        echo "net.ipv6.conf.all.disable_ipv6=1" >> /etc/sysctl.d/99-security.conf 2>/dev/null
        echo "net.ipv6.conf.default.disable_ipv6=1" >> /etc/sysctl.d/99-security.conf 2>/dev/null
        # 关时间戳
        echo "net.ipv4.tcp_timestamps=0" >> /etc/sysctl.d/99-security.conf 2>/dev/null
        # 防 IP 欺骗
        echo "net.ipv4.conf.all.rp_filter=1" >> /etc/sysctl.d/99-security.conf 2>/dev/null
        echo "net.ipv4.conf.all.accept_redirects=0" >> /etc/sysctl.d/99-security.conf 2>/dev/null
        echo "net.ipv4.conf.all.send_redirects=0" >> /etc/sysctl.d/99-security.conf 2>/dev/null
        sysctl -p /etc/sysctl.d/99-security.conf 2>/dev/null
        
        # fail2ban
        apt-get install -y -qq fail2ban 2>/dev/null
        systemctl restart fail2ban 2>/dev/null
        
        # DNS over TLS
        mkdir -p /etc/systemd/resolved.conf.d/
        cat > /etc/systemd/resolved.conf.d/dns-over-tls.conf <<DNSEOF
[Resolve]
DNS=8.8.8.8#dns.google 1.1.1.1#cloudflare-dns.com
DNSOverTLS=yes
LLMNR=no
MulticastDNS=no
DNSEOF
        systemctl restart systemd-resolved 2>/dev/null
        
        # 自动更新
        apt-get install -y -qq unattended-upgrades 2>/dev/null
        echo -e "${GREEN}✅ 安全加固完成！${NC}"
    fi
    menu_footer
}

# ═══════════════════════════════════════════════════════════════════════════════
#  5. 服务管理
# ═══════════════════════════════════════════════════════════════════════════════
service_menu() {
    while true; do
        menu_header
        echo -e " ${YELLOW}━━━ 服务管理 ━━━${NC}"
        local services=($(systemctl list-units --type=service --state=running 2>/dev/null | grep 'loaded active' | grep -vE 'systemd|user@|dbus|cron' | awk '{print $1}'))
        local i=1
        for s in "${services[@]}"; do
            local desc=""
            case $s in
                xray*) desc="Reality 代理";; sing-box*) desc="Sing-box 代理";; 
                nginx*) desc="Web 服务器";; fail2ban*) desc="SSH 防护";;
                ssh*) desc="SSH";; docker*) desc="Docker 引擎";;
                komari*) desc="监控探针";; *) desc="";;
            esac
            echo "  $i) $s${desc:+ — $desc}"
            ((i++))
        done
        echo "  0) 返回"
        read -p "  选服务编号查看状态 [0-$((i-1))]: " opt
        [[ "$opt" == "0" ]] && break
        local idx=$((opt-1))
        local svc="${services[$idx]}"
        [[ -z "$svc" ]] && continue
        systemctl status "$svc" --no-pager -n 10 2>/dev/null | head -15
        echo ""
        read -p "  [r]重启 [s]停止 [q]退出: " action
        case $action in
            r) systemctl restart "$svc" 2>/dev/null && echo -e "${GREEN}已重启${NC}" ;;
            s) systemctl stop "$svc" 2>/dev/null && echo -e "${GREEN}已停止${NC}" ;;
        esac
        menu_footer
    done
}

# ═══════════════════════════════════════════════════════════════════════════════
#  6. 网络工具
# ═══════════════════════════════════════════════════════════════════════════════
net_tools() {
    menu_header
    echo -e " ${YELLOW}━━━ 网络工具 ━━━${NC}"
    echo "  1) 测速（speedtest）"
    echo "  2) 延迟测试（ping）"
    echo "  3) 路由追踪（traceroute）"
    echo "  4) 端口扫描（本机）"
    echo "  5) DNS 泄露检测"
    echo "  0) 返回"
    read -p "  请选择 [0-5]: " opt
    case $opt in
        1) command -v speedtest-cli &>/dev/null || pip3 install speedtest-cli -q 2>/dev/null
           speedtest-cli --simple 2>/dev/null || echo -e "${RED}安装失败${NC}" ;;
        2) read -p "  目标IP/域名: " target
           ping -c 5 "$target" 2>&1 | tail -3 ;;
        3) read -p "  目标IP/域名: " target
           traceroute "$target" 2>&1 | head -15 ;;
        4) echo "  监听端口:"; ss -tlnp | grep LISTEN | awk '{print "    " $5}' | sort -u ;;
        5) echo -n "  DNS 出口: "; dig whoami.dns.controld.com +short 2>/dev/null
           echo -n "  本机 IP: "; curl -4s https://ipinfo.io/ip 2>/dev/null
           if resolvectl status 2>/dev/null | grep -q DNSOverTLS; then echo -e "\n  DNS 加密: ✅"; fi ;;
    esac
    menu_footer
}

# ═══════════════════════════════════════════════════════════════════════════════
#  7. 系统清理
# ═══════════════════════════════════════════════════════════════════════════════
clean_system() {
    menu_header
    echo -e " ${YELLOW}━━━ 系统清理 ━━━${NC}"
    echo "  将执行："
    echo "  • 清理 apt 缓存"
    echo "  • 清理旧内核"
    echo "  • 清理 journal 日志（保留 50M）"
    echo "  • 清理临时文件"
    echo "  • 删除 shell 历史"
    if confirm "确认执行？"; then
        apt-get clean -qq 2>/dev/null
        apt autoremove --purge -y -qq 2>/dev/null
        dpkg -l | grep linux-image | grep -v $(uname -r) | awk '{print $2}' | xargs -r dpkg --purge 2>/dev/null
        journalctl --vacuum-size=50M 2>/dev/null
        rm -rf /tmp/* /var/tmp/* 2>/dev/null || true
        rm -f /root/.bash_history /root/.wget-hsts 2>/dev/null || true
        echo -e "${GREEN}✅ 清理完成！${NC}"
        echo "  磁盘: $(df -h / | awk 'NR==2{print $3 \"/\" $2}')"
    fi
    menu_footer
}

# ═══════════════════════════════════════════════════════════════════════════════
#  主菜单
# ═══════════════════════════════════════════════════════════════════════════════
main_menu() {
    while true; do
        menu_header
        echo -e "  ${GREEN}1${NC})  系统信息"
        echo -e "  ${GREEN}2${NC})  安全检测"
        echo -e "  ${GREEN}3${NC})  TCP 调优"
        echo -e "  ${GREEN}4${NC})  一键安全加固"
        echo -e "  ${GREEN}5${NC})  服务管理"
        echo -e "  ${GREEN}6${NC})  网络工具"
        echo -e "  ${GREEN}7${NC})  系统清理"
        echo -e "  ${GREEN}0${NC})  退出"
        echo ""
        read -p "  请选择 [0-7]: " choice
        case $choice in
            1) sys_info ;;   2) security_check ;;
            3) tcp_tune ;;   4) hardening ;;
            5) service_menu ;; 6) net_tools ;;
            7) clean_system ;; 0) echo "再见！"; exit ;;
            *) continue ;;
        esac
    done
}

# ── 启动 ─────────────────────────────────────────────────────────────────────
check_root
main_menu
