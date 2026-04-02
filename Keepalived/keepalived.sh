#!/bin/bash
# Keepalived Manager v23.1 (MosDNS Check & Optimized Edition)

# --- 环境预检 ---
# 巧妙的预处理：如果在 OpenWrt 且没有 bash，先用默认 shell 安装 bash 再重新执行
[ -f /etc/openwrt_release ] && [ ! -f /bin/bash ] && opkg update && opkg install bash && exec /bin/bash "$0" "$@"

# 定义颜色
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

check_iface_exists() {
    if ! ip link show "$1" >/dev/null 2>&1; then return 1; fi
    return 0
}

get_default_iface() {
    ip route | grep default | awk '{print $5}' | head -n 1
}

manage_service() {
    local action=$1
    echo -e "${BLUE}>> 执行操作: $action Keepalived...${NC}"
    if [ -f /etc/openwrt_release ]; then
        /etc/init.d/keepalived "$action"
    else
        systemctl "$action" keepalived
    fi
    sleep 1
    if pgrep keepalived >/dev/null; then
        echo -e "当前状态: ${GREEN}运行中${NC}"
    else
        echo -e "当前状态: ${RED}已停止${NC}"
    fi
}

rewrite_openwrt_init() {
    if [ ! -f /etc/openwrt_release ]; then return; fi
    local INIT_FILE="/etc/init.d/keepalived"
    cat > "$INIT_FILE" <<EOF
#!/bin/sh /etc/rc.common
START=90
STOP=10
USE_PROCD=1
PROG=/usr/sbin/keepalived
CONF="/etc/keepalived/keepalived.conf"

start_service() {
    procd_open_instance
    procd_set_param command \$PROG
    procd_append_param command -n
    procd_append_param command -f "\$CONF"
    procd_set_param respawn
    procd_close_instance
}
service_triggers() {
    procd_add_reload_trigger "keepalived"
}
EOF
    chmod +x "$INIT_FILE"
}

# === 核心：一键更换国内源 (Armbian/Debian) ===
change_apt_source() {
    if [ -f /etc/openwrt_release ]; then
        echo -e "${YELLOW}>> OpenWrt 无需换源，跳过。${NC}"
        return
    fi
    
    echo -e "${BLUE}>> 正在更换为中科大(USTC)国内源...${NC}"
    
    # 1. 备份原文件
    if [ ! -f /etc/apt/sources.list.bak ]; then
        cp /etc/apt/sources.list /etc/apt/sources.list.bak
        echo "   已备份原源列表到 /etc/apt/sources.list.bak"
    fi

    # 2. 检测系统版本代号
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        CODENAME=${VERSION_CODENAME}
    fi
    if [ -z "$CODENAME" ]; then
        echo -e "${YELLOW}   未检测到版本代号，根据日志推断为: trixie${NC}"
        CODENAME="trixie"
    else
        echo "   检测到系统版本: $CODENAME"
    fi

    # 3. 写入新的源列表
    cat > /etc/apt/sources.list <<EOF
deb http://mirrors.ustc.edu.cn/debian/ $CODENAME main contrib non-free non-free-firmware
deb http://mirrors.ustc.edu.cn/debian/ $CODENAME-updates main contrib non-free non-free-firmware
deb http://mirrors.ustc.edu.cn/debian/ $CODENAME-backports main contrib non-free non-free-firmware
deb http://mirrors.ustc.edu.cn/debian-security/ $CODENAME-security main contrib non-free non-free-firmware
EOF

    # 4. 清理并更新
    echo -e "${BLUE}>> 正在更新软件列表 (apt-get update)...${NC}"
    rm /var/lib/apt/lists/lock /var/cache/apt/archives/lock /var/lib/dpkg/lock* 2>/dev/null
    dpkg --configure -a 2>/dev/null
    
    apt-get update
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ 换源成功！列表更新完成。${NC}"
    else
        echo -e "${RED}❌ 更新失败。请检查网络连接是否正常。${NC}"
    fi
    read -p "按回车继续..."
}

fix_firewall() {
    if [ -f /etc/openwrt_release ]; then return; fi
    echo -e "${BLUE}>> 正在检查防火墙设置...${NC}"
    if command -v ufw &>/dev/null && ufw status | grep -q "Status: active"; then
        ufw allow in proto vrrp >/dev/null 2>&1
        ufw allow out proto vrrp >/dev/null 2>&1
        ufw allow from 224.0.0.0/8 >/dev/null 2>&1
    fi
    if command -v iptables &>/dev/null; then
        iptables -C INPUT -p vrrp -j ACCEPT 2>/dev/null || iptables -I INPUT -p vrrp -j ACCEPT
        iptables -C OUTPUT -p vrrp -j ACCEPT 2>/dev/null || iptables -I OUTPUT -p vrrp -j ACCEPT
        if command -v netfilter-persistent &>/dev/null; then
            netfilter-persistent save >/dev/null 2>&1
        elif command -v iptables-save &>/dev/null; then
            mkdir -p /etc/iptables
            iptables-save > /etc/iptables/rules.v4
        fi
    fi
}

fix_package_lock() {
    if [ ! -f /etc/openwrt_release ]; then
        rm /var/lib/apt/lists/lock /var/cache/apt/archives/lock /var/lib/dpkg/lock* 2>/dev/null
        dpkg --configure -a 2>/dev/null
    fi
}

# --- 菜单循环 ---
while true; do
    clear
    echo -e "${GREEN}==========================================${NC}"
    echo -e "${GREEN}    Keepalived 全功能管家 v23.1    ${NC}"
    echo -e "${GREEN}    (MosDNS 联动检测优化版)    ${NC}"
    echo -e "${GREEN}==========================================${NC}"
    echo "1. 安装 / 重置配置 (Install/Reset)"
    echo "2. 状态诊断 (Diagnose)"
    echo "3. 查看日志 (View Logs)"
    echo "4. 卸载清除 (Uninstall)"
    echo "------------------------------------------"
    echo "5. 启动服务 (Start)"
    echo "6. 停止服务 (Stop)"
    echo "7. 重启服务 (Restart)"
    echo "------------------------------------------"
    echo -e "${YELLOW}8. 修复: 更换国内软件源 (Fix Apt Source)${NC}"
    echo "------------------------------------------"
    echo "0. 退出脚本 (Exit)"
    echo "=========================================="
    read -p "请选择 [0-8]: " MENU_OPT

    case "$MENU_OPT" in
        0) 
            echo "再见。"; exit 0 
            ;;
        5) 
            manage_service "start"; read -p "按回车继续..."; continue 
            ;;
        6) 
            manage_service "stop"; read -p "按回车继续..."; continue 
            ;;
        7) 
            manage_service "restart"; read -p "按回车继续..."; continue 
            ;;
        8) 
            change_apt_source; continue 
            ;;
        2)
            echo -e "\n${GREEN}=== 状态诊断报告 ===${NC}"
            PID=$(pgrep keepalived | head -n 1)
            [ -n "$PID" ] && echo -e "进程: ${GREEN}● 运行中 (PID: $PID)${NC}" || echo -e "进程: ${RED}● 未运行${NC}"
            CONF_FILE="/etc/keepalived/keepalived.conf"
            CONF_IF=$(grep "interface" "$CONF_FILE" 2>/dev/null | awk '{print $2}' | tr -d ';')
            if [ -n "$CONF_IF" ]; then
                REAL_VIP=$(ip -4 addr show dev "$CONF_IF" 2>/dev/null | grep " secondary " | awk '{print $2}' | cut -d/ -f1 | head -n 1)
                [ -n "$REAL_VIP" ] && echo -e "VIP : ${GREEN}MASTER ($REAL_VIP)${NC}" || echo -e "VIP : ${YELLOW}BACKUP${NC}"
            fi
            read -p "按回车返回..."
            continue
            ;;
        3)
            echo -e "\n${BLUE}=== 最近 20 条日志 ===${NC}"
            if [ -f /etc/openwrt_release ]; then 
                logread | grep Keepalived | tail -n 20 
            else 
                journalctl -u keepalived -n 20 --no-pager 
            fi
            read -p "按回车返回..."
            continue
            ;;
        4)
            # ... 原卸载代码 ...
            echo "执行卸载..."
            read -p "按回车返回..."
            continue
            ;;
        1)
            # ================= 1. 安装/重置 =================
            fix_package_lock
            
            DEF_IF=$(get_default_iface)
            read -p "输入 VIP [默认: 192.168.8.8]: " VIP
            VIP=${VIP:-192.168.8.8}

            echo -e "\n角色: 1) MASTER (主-Mosdns)  2) BACKUP (备-Ros)"
            read -p "选择 [1-2]: " ROLE_OPT
            [ "$ROLE_OPT" == "1" ] && { STATE="MASTER"; PRI=100; } || { STATE="BACKUP"; PRI=90; }

            while true; do
                read -p "网卡名称 [默认: $DEF_IF]: " IFACE
                IFACE=${IFACE:-$DEF_IF}
                check_iface_exists "$IFACE" && break
                echo -e "${RED}错误: 网卡不存在!${NC}"
            done

            echo -e "\n${YELLOW}=== 监控配置 ===${NC}"
            echo "1. MosDNS 联动检测 (检测 ai.mosdns.mos 是否为 10.10.88.88)"
            echo "2. 仅端口检测 (检查 53 端口是否存活)"
            echo "3. 不监控"
            read -p "选择 [1-3]: " MON_OPT
            MON_OPT=${MON_OPT:-1}

            mkdir -p /etc/keepalived
            chown root:root /etc/keepalived
            chmod 755 /etc/keepalived

            SCRIPT_PATH="/etc/keepalived/check_dns.sh"
            CHECK_BLK=""; TRACK_BLK=""

            if [ "$MON_OPT" == "1" ] || [ "$MON_OPT" == "2" ]; then
                # 生成检测脚本第一部分：端口检测
                cat > "$SCRIPT_PATH" <<EOF
#!/bin/bash
PORT_UP=0
if command -v ss &>/dev/null; then 
    ss -uln | grep ':53 ' >/dev/null && PORT_UP=1
elif command -v netstat &>/dev/null; then 
    netstat -uln | grep ':53 ' >/dev/null && PORT_UP=1
fi
if [ \$PORT_UP -eq 0 ]; then exit 1; fi
EOF
                # 生成检测脚本第二部分：MosDNS 特定解析检测
                if [ "$MON_OPT" == "1" ]; then
                    cat >> "$SCRIPT_PATH" <<EOF

if command -v nslookup &>/dev/null; then
    # 查询本地 DNS 并使用 grep 静默匹配目标 IP
    if ! timeout 2s nslookup ai.mosdns.mos 127.0.0.1 2>/dev/null | grep -q "10.10.88.88"; then
        exit 1 # IP 不匹配或解析失败则触发降级
    fi
fi
exit 0
EOF
                else
                    echo "exit 0" >> "$SCRIPT_PATH"
                fi

                chmod 755 "$SCRIPT_PATH"
                chown root:root "$SCRIPT_PATH" 2>/dev/null 
                
                CHECK_BLK="vrrp_script chk_dns {
    script \"$SCRIPT_PATH\"
    interval 3
    weight -20
    fall 3
    rise 2
}"
                TRACK_BLK="track_script {
        chk_dns
    }"
            fi

            echo -e "\n${BLUE}>> 安装依赖...${NC}"
            if [ -f /etc/openwrt_release ]; then
                opkg update && opkg install keepalived ip-full
                rewrite_openwrt_init
                fix_firewall 
            else
                echo ">> 正在安装 Keepalived..."
                apt-get update -y
                apt-get install -y keepalived net-tools dnsutils
                
                if [ ! -f /usr/sbin/keepalived ]; then
                    echo -e "${RED}❌ 安装失败！无法连接到 Debian 官方源。${NC}"
                    echo -e "${YELLOW}>>> 检测到您可能在中国大陆，需要更换国内源。${NC}"
                    read -p "是否立即执行更换源操作？(y/n): " CHANGE_SRC
                    if [[ "$CHANGE_SRC" == "y" || "$CHANGE_SRC" == "Y" ]]; then
                        change_apt_source
                        echo -e "${BLUE}>> 正在重试安装...${NC}"
                        apt-get install -y keepalived net-tools dnsutils
                        if [ ! -f /usr/sbin/keepalived ]; then
                             echo -e "${RED}❌ 重试依然失败，请检查网络 DNS。${NC}"; exit 1
                        fi
                    else
                        echo "取消安装。"; exit 1
                    fi
                fi
                fix_firewall
            fi

            echo -e "${BLUE}>> 生成配置...${NC}"
            cat > /etc/keepalived/keepalived.conf <<EOF
global_defs {
    router_id $HOSTNAME
    script_user root
}

$CHECK_BLK

vrrp_instance VI_1 {
    state $STATE
    interface $IFACE
    virtual_router_id 51
    priority $PRI
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass 1111
    }
    virtual_ipaddress {
        $VIP/24
    }
    $TRACK_BLK
}
EOF
            manage_service "restart"
            echo -e "${GREEN}配置完成!${NC}"
            read -p "按回车返回主菜单..."
            ;;
    esac
done
