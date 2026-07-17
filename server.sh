#!/usr/bin/env bash
#===============================================================================
#  🇺🇳 Server Pro Menus  v1.0  —  多功能 VPS 管理脚本
#  GitHub: https://github.com/hb0219/server-tool
#  用法:
#    bash <(curl -sL https://raw.githubusercontent.com/hb0219/server-tool/main/server.sh)
#===============================================================================
[[ $EUID -eq 0 ]] || { echo "请用 root 运行"; exit 1; }

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
BOLD='\033[1m'

r() {
    local prompt="$1" var="$2"
    echo -n -e "${prompt}"
    read "$var"
}

ssh_port() {
    local p
    p=$(ss -tlnp 2>/dev/null | grep sshd | head -1 | awk '{print $4}' | cut -d: -f2)
    echo "${p:-22}"
}

# ── 系统信息 ─────────────────────────────────────────────────────────────────
menu_1() {
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━ 系统信息 ━━━━━━━━━━━━${NC}"
    echo -e "  主机名:    $(hostname)"
    echo -e "  系统版本:  $(. /etc/os-release 2>/dev/null; echo "$PRETTY_NAME")"
    echo -e "  内核版本:  $(uname -r)"
    echo -e "  运行时长:  $(uptime -p 2>/dev/null || uptime)"
    echo ""
    echo -e " ${YELLOW}CPU / 内存 / 磁盘${NC}"
    echo -e "  CPU:       $(lscpu 2>/dev/null | grep 'Model name' | cut -d: -f2 | xargs | head -c50 || echo 'N/A')"
    echo -e "  核心:      $(nproc) 核心"
    echo -e "  内存:      $(free -h | awk '/^Mem/{print $3"/"$2}')"
    echo -e "  磁盘:      $(df -h / | awk 'NR==2{print $3"/"$2" ("$5")"}')"
    echo ""
    echo -e " ${YELLOW}网络${NC}"
    echo -e "  IPv4:      $(curl -4s --connect-timeout 3 https://ipinfo.io/ip 2>/dev/null || hostname -I | awk '{print $1}')"
    echo -e "  IPv6:      $(ip -6 addr show 2>/dev/null | grep global | awk '{print $2}' | cut -d/ -f1 | head -1 || echo '无')"
    echo -e "  ASN:       $(curl -4s --connect-timeout 3 https://ipinfo.io/org 2>/dev/null || echo 'N/A')"
    echo -e "  SSH端口:   $(ssh_port)"
    echo -e "  BBR:       $(lsmod 2>/dev/null | grep -q bbr && echo '✅ 已启用' || echo '❌ 未启用')"
}

# ── 安全检测 ─────────────────────────────────────────────────────────────────
menu_2() {
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━ 安全检测 ━━━━━━━━━━━━${NC}"
    local s=$(ssh_port) n=0
    [[ "$s" != "22" ]] && echo -e "  ✅ SSH端口: $s" || { echo -e "  ⚠️  SSH默认端口22"; ((n++)); }
    grep -q 'PasswordAuthentication yes' /etc/ssh/sshd_config 2>/dev/null \
      && { echo -e "  ⚠️  允许密码登录"; ((n++)); } || echo -e "  ✅ 已禁用密码登录"
    [[ $(cat /proc/sys/net/ipv4/icmp_echo_ignore_all 2>/dev/null) == "1" ]] \
      && echo -e "  ✅ Ping已禁" || { echo -e "  ⚠️  Ping未禁"; ((n++)); }
    systemctl is-active fail2ban &>/dev/null \
      && echo -e "  ✅ fail2ban运行中" || { echo -e "  ⚠️  fail2ban未运行"; ((n++)); }
    resolvectl status 2>/dev/null | grep -q DNSOverTLS \
      && echo -e "  ✅ DNS加密(DoT)" || { echo -e "  ⚠️  DNS未加密"; ((n++)); }
    echo ""
    [[ $n -eq 0 ]] && echo -e "  ${GREEN}🎉 全部安全！${NC}" || echo -e "  ${YELLOW}⚠️  发现 $n 项待优化${NC}"
}

# ── TCP调优 ──────────────────────────────────────────────────────────────────
menu_3() {
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━ TCP 调优 ━━━━━━━━━━━━${NC}"
    echo -e "  当前: $(sysctl net.ipv4.tcp_congestion_control 2>/dev/null | awk '{print $3}') / $(sysctl net.core.default_qdisc 2>/dev/null | awk '{print $3}')"
    echo ""
    echo "  1) 启用 BBR"
    echo "  2) 深度优化 (CN2 GIA / 9929 / CMIN2)"
    echo "  3) 恢复默认"
    echo "  0) 返回"
    r "  请选择 [0-3]: " opt
    case $opt in
        1) echo "net.core.default_qdisc=fq" > /etc/sysctl.d/99-bbr.conf
           echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.d/99-bbr.conf
           sysctl -p /etc/sysctl.d/99-bbr.conf &>/dev/null
           echo -e "${GREEN}✅ BBR 已启用${NC}" ;;
        2) cat > /etc/sysctl.d/99-tcp.conf << 'EOT'
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
EOT
           sysctl -p /etc/sysctl.d/99-tcp.conf &>/dev/null
           echo -e "${GREEN}✅ 深度优化完成${NC}" ;;
        3) rm -f /etc/sysctl.d/99-bbr.conf /etc/sysctl.d/99-tcp.conf &>/dev/null
           sysctl -w net.ipv4.tcp_congestion_control=cubic &>/dev/null
           echo -e "${GREEN}✅ 已恢复默认${NC}" ;;
    esac
    [ "$opt" != "0" ] && { echo ""; r "  按回车返回..."; }
}

# ── 一键加固 ─────────────────────────────────────────────────────────────────
menu_4() {
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━ 一键加固 ━━━━━━━━━━━━${NC}"
    echo "  1) 禁用ping + 关IPv6 + 关时间戳"
    echo "  2) 安装fail2ban"
    echo "  3) 配置DNS over TLS"
    echo "  4) 开启自动安全更新"
    echo "  5) 全部执行"
    echo "  0) 返回"
    r "  请选择 [0-5]: " opt
    case $opt in
        1) printf 'net.ipv4.icmp_echo_ignore_all=1\nnet.ipv6.conf.all.disable_ipv6=1\nnet.ipv4.tcp_timestamps=0\n' >> /etc/sysctl.d/99-security.conf
           sysctl -p /etc/sysctl.d/99-security.conf &>/dev/null && echo -e "${GREEN}✅ 已禁用${NC}" ;;
        2) apt-get install -y -qq fail2ban &>/dev/null; systemctl restart fail2ban &>/dev/null; echo -e "${GREEN}✅ fail2ban已安装${NC}" ;;
        3) mkdir -p /etc/systemd/resolved.conf.d
           printf '[Resolve]\nDNS=1.1.1.1#cloudflare-dns.com 8.8.8.8#dns.google\nDNSOverTLS=yes\nLLMNR=no\nMulticastDNS=no\n' > /etc/systemd/resolved.conf.d/dns-over-tls.conf
           systemctl restart systemd-resolved &>/dev/null && echo -e "${GREEN}✅ DoT已配置${NC}" ;;
        4) apt-get install -y -qq unattended-upgrades &>/dev/null && echo -e "${GREEN}✅ 自动更新已开启${NC}" ;;
        5) apt-get install -y -qq fail2ban unattended-upgrades &>/dev/null
           printf 'net.ipv4.icmp_echo_ignore_all=1\nnet.ipv6.conf.all.disable_ipv6=1\nnet.ipv4.tcp_timestamps=0\nnet.ipv4.conf.all.rp_filter=1\nnet.ipv4.conf.all.accept_redirects=0\n' >> /etc/sysctl.d/99-security.conf
           sysctl -p /etc/sysctl.d/99-security.conf &>/dev/null
           mkdir -p /etc/systemd/resolved.conf.d
           printf '[Resolve]\nDNS=1.1.1.1#cloudflare-dns.com 8.8.8.8#dns.google\nDNSOverTLS=yes\nLLMNR=no\nMulticastDNS=no\n' > /etc/systemd/resolved.conf.d/dns-over-tls.conf
           systemctl restart systemd-resolved &>/dev/null; systemctl restart fail2ban &>/dev/null
           echo -e "${GREEN}✅ 全部加固完成${NC}" ;;
    esac
    [ "$opt" != "0" ] && { echo ""; r "  按回车返回..."; }
}

# ── 系统清理 ─────────────────────────────────────────────────────────────────
menu_5() {
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━ 系统清理 ━━━━━━━━━━━━${NC}"
    echo "  1) 清理apt缓存"
    echo "  2) 清理旧内核"
    echo "  3) 清理journal日志"
    echo "  4) 全部清理"
    echo "  0) 返回"
    r "  请选择 [0-4]: " opt
    case $opt in
        1) apt-get clean -qq &>/dev/null; apt autoremove --purge -y -qq &>/dev/null; echo -e "${GREEN}✅ apt已清理${NC}" ;;
        2) dpkg -l | grep linux-image | grep -v $(uname -r) | awk '{print $2}' | xargs -r dpkg --purge &>/dev/null
           echo -e "${GREEN}✅ 旧内核已清理${NC}" ;;
        3) journalctl --vacuum-size=50M &>/dev/null && echo -e "${GREEN}✅ journal已清理${NC}" ;;
        4) apt-get clean -qq &>/dev/null; apt autoremove --purge -y -qq &>/dev/null
           dpkg -l | grep linux-image | grep -v $(uname -r) | awk '{print $2}' | xargs -r dpkg --purge &>/dev/null
           journalctl --vacuum-size=50M &>/dev/null; rm -rf /tmp/* /var/tmp/* &>/dev/null || true
           echo -e "${GREEN}✅ 全部清理完成${NC}" ;;
    esac
    [ "$opt" != "0" ] && { echo ""; r "  按回车返回..."; }
}

# ── 网络工具 ─────────────────────────────────────────────────────────────────
menu_6() {
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━ 网络工具 ━━━━━━━━━━━━${NC}"
    echo "  1) 测速"
    echo "  2) Ping测试"
    echo "  3) 路由追踪"
    echo "  4) 本机端口"
    echo "  5) DNS检测"
    echo "  0) 返回"
    r "  请选择 [0-5]: " opt
    case $opt in
        1) command -v speedtest-cli &>/dev/null || pip3 install speedtest-cli -q &>/dev/null
           speedtest-cli --simple 2>/dev/null || echo -e "${RED}测速失败${NC}" ;;
        2) r "  目标: " t; ping -c 5 "$t" 2>&1 | tail -3 ;;
        3) r "  目标: " t; traceroute "$t" 2>&1 | head -15 ;;
        4) echo -e "  ${YELLOW}监听端口:${NC}"; ss -tlnp | grep LISTEN | awk '{print "    "$4}' | sort -u ;;
        5) echo -n "  DNS加密: "; resolvectl status 2>/dev/null | grep -q DNSOverTLS && echo -e "${GREEN}✅${NC}" || echo -e "${RED}❌${NC}"
           echo -n "  DNS出口: "; dig whoami.dns.controld.com +short 2>/dev/null
           echo -n "  本机IP:  "; curl -4s https://ipinfo.io/ip 2>/dev/null ;;
    esac
    [ "$opt" != "0" ] && { echo ""; r "  按回车返回..."; }
}

# ── 服务状态 ─────────────────────────────────────────────────────────────────
menu_7() {
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━ 服务状态 ━━━━━━━━━━━━${NC}"
    local list=($(systemctl list-units --type=service --state=running 2>/dev/null | grep 'loaded active' | grep -vE 'systemd|user@|dbus|cron|resolv|getty|logind|networkd|timesyncd' | awk '{print $1}'))
    local i=0
    for s in "${list[@]}"; do
        local d=""; case $s in xray*) d="代理";; sing-box*) d="代理";; nginx*) d="Web";; fail2ban*) d="防护";; esac
        printf "  %2d) %-20s %s\n" $((i+1)) "$s" "${d:+($d)}"; ((i++))
    done
    [ ${#list[@]} -eq 0 ] && echo "  (无运行服务)"
    echo "  0) 返回"
    r "  选择查看 [0-${#list[@]}]: " n
    [[ "$n" == "0" ]] && return
    local idx=$((n-1)); [[ -z "${list[$idx]}" ]] && return
    systemctl status "${list[$idx]}" --no-pager -n 10 2>/dev/null | head -15
    echo ""; r "  [r]重启 [s]停止 [其他]返回: " a
    case $a in r|R) systemctl restart "${list[$idx]}" &>/dev/null && echo -e "${GREEN}已重启${NC}";; s|S) systemctl stop "${list[$idx]}" &>/dev/null && echo -e "${GREEN}已停止${NC}";; esac
}

# ── 关于 ──────────────────────────────────────────────────────────────────────
menu_8() {
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━ 关于 ─━━━━━━━━━━━━${NC}"
    echo ""
    echo "  🇺🇳 Server Pro Menus v1.0"
    echo "  功能: 系统信息 / 安全检测 / TCP调优"
    echo "        / 一键加固 / 系统清理 / 网络工具"
    echo "        / 服务管理"
    echo ""
    echo "  📦 GitHub: github.com/hb0219/server-tool"
    echo "  🚀 运行: bash <(curl -sL https://raw.githubusercontent.com/hb0219/server-tool/main/server.sh)"
}

# ═══════════════════════════════════════════════════════════════════════════════
#  主菜单
# ═══════════════════════════════════════════════════════════════════════════════
clear
while true; do
    echo ""
    echo -e "${GREEN}┌──────────────────────────────────────────────────┐${NC}"
    echo -e "${GREEN}│        ${BOLD}🇺🇳  Server Pro Menus  v1.0${NC}${GREEN}            │${NC}"
    echo -e "${GREEN}├──────────────────────────────────────────────────┤${NC}"
    printf "${GREEN}│${NC}  %-46s ${GREEN}│${NC}\n" "$(hostname)"
    printf "${GREEN}│${NC}  %-46s ${GREEN}│${NC}\n" "IP: $(curl -4s --connect-timeout 2 https://ipinfo.io/ip 2>/dev/null || echo 'N/A')"
    echo -e "${GREEN}└──────────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "  ${GREEN}1${NC})  系统信息        ${GREEN}5${NC})  系统清理"
    echo -e "  ${GREEN}2${NC})  安全检测        ${GREEN}6${NC})  网络工具"
    echo -e "  ${GREEN}3${NC})  TCP 调优        ${GREEN}7${NC})  服务状态"
    echo -e "  ${GREEN}4${NC})  一键加固        ${GREEN}8${NC})  关于"
    echo -e "                     ${GREEN}0${NC})  退出"
    echo ""
    r "  请输入数字选择 [0-8]: " ch
    echo ""
    case $ch in
        1) menu_1 ;; 2) menu_2 ;; 3) menu_3 ;;
        4) menu_4 ;; 5) menu_5 ;; 6) menu_6 ;;
        7) menu_7 ;; 8) menu_8 ;;
        0) echo -e "${GREEN}  再见！${NC}"; exit ;;
        *) echo -e "  ${RED}无效输入${NC}"; sleep 1; continue ;;
    esac
    # 只有选择 0 才退出，其他都等按回车后回菜单
    if [ "$ch" != "0" ]; then
        echo ""
        r "  按回车返回主菜单..."
    fi
done
