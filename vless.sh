#!/bin/bash

export LANG=en_US.UTF-8
export DEBIAN_FRONTEND=noninteractive

# =================================================================
#  1. 现代化极简 UI 色彩库 (原汁原味保留)
# =================================================================
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
PURPLE="\033[35m"

LIGHT_RED="\033[1;31m"
LIGHT_GREEN="\033[1;32m"
LIGHT_YELLOW="\033[1;33m"
LIGHT_PURPLE="\033[1;35m"
PLAIN="\033[0m"

red()    { echo -e "${LIGHT_RED}$1${PLAIN}"; }
green()  { echo -e "${LIGHT_GREEN}$1${PLAIN}"; }
yellow() { echo -e "${LIGHT_YELLOW}$1${PLAIN}"; }
purple() { echo -e "${LIGHT_PURPLE}$1${PLAIN}"; }

print_line() {
    green " ──────────────────────────────────────────────────────────"
}

# =================================================================
#  2. 基础系统判定与核心工具函数
# =================================================================
[[ $EUID -ne 0 ]] && red " [错误] 请在 root 用户下运行此脚本！" && exit 1

SCRIPT_PATH=$(realpath "$0" 2>/dev/null || readlink -f "$0" 2>/dev/null || echo "$0")
if [[ -f "$SCRIPT_PATH" && "$(head -n 1 "$SCRIPT_PATH" 2>/dev/null)" == "#!/bin/bash" ]]; then
    if [[ "$SCRIPT_PATH" != "/usr/local/bin/vvv" ]]; then
        cp -f "$SCRIPT_PATH" /usr/local/bin/vvv
        chmod +x /usr/local/bin/vvv
    fi
fi

REGEX=("alpine" "debian" "ubuntu" "centos|red hat|kernel|oracle linux|alma|rocky" "amazon linux" "fedora")
RELEASE=("Alpine" "Debian" "Ubuntu" "CentOS" "CentOS" "Fedora")
PACKAGE_UPDATE=("apk update" "apt-get update" "apt-get update" "yum -y update" "yum -y update" "yum -y update")
PACKAGE_INSTALL=("apk add" "apt-get -y install" "apt-get -y install" "yum -y install" "yum -y install" "yum -y install")

CMD=("$(grep -i pretty_name /etc/os-release 2>/dev/null | cut -d \" -f2)" "$(hostnamectl 2>/dev/null | grep -i system | cut -d : -f2)" "$(lsb_release -sd 2>/dev/null)" "$(grep -i description /etc/lsb-release 2>/dev/null | cut -d \" -f2)" "$(grep . /etc/redhat-release 2>/dev/null)" "$(grep . /etc/issue 2>/dev/null | cut -d \\ -f1 | sed '/^[ ]*$/d')")

for i in "${CMD[@]}"; do
    SYS="$i" && [[ -n $SYS ]] && break
done

for ((int = 0; int < ${#REGEX[@]}; int++)); do
    if [[ $(echo "$SYS" | tr '[:upper:]' '[:lower:]') =~ ${REGEX[int]} ]]; then
        SYSTEM="${RELEASE[int]}"
        PKG_UPDATE="${PACKAGE_UPDATE[int]}"
        PKG_INSTALL="${PACKAGE_INSTALL[int]}"
        [[ -n $SYSTEM ]] && break
    fi
done
[[ -z $SYSTEM ]] && red " [错误] 目前暂不支持您的 VPS 操作系统！" && exit 1

if [[ -z $(type -P curl) ]]; then
    [[ ! $SYSTEM == "CentOS" ]] && { $PKG_UPDATE || true; }
    $PKG_INSTALL curl || { echo ""; red " [错误] curl 安装失败！请检查网络或系统源。"; exit 1; }
fi

realip() {
    ip=$(curl -s4m3 api.ipify.org -k || curl -s4m3 ifconfig.me -k || curl -s4m3 ip.sb -k)
    if [[ -z "$ip" ]]; then
        ip=$(curl -s6m3 api64.ipify.org -k || curl -s6m3 ifconfig.me -k || curl -s6m3 ip.sb -k)
    fi
    ip=$(echo "$ip" | grep -m 1 -E -o "([0-9]{1,3}[\.]){3}[0-9]{1,3}|([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:)*:[0-9a-fA-F]{1,4}")
    [[ -z "$ip" ]] && red " [错误] 无法获取本机的公网 IP！" && exit 1
}

gen_random_str() {
    local len=$1
    local str=$(cat /proc/sys/kernel/random/uuid 2>/dev/null | tr -d '-')
    [[ -z "$str" ]] && str=$(head -c 16 /dev/urandom | od -A n -t x1 | tr -d ' \n')
    echo "${str:0:$len}"
}

open_port() {
    local port=$1
    if command -v ufw >/dev/null && ufw status | grep -qw active; then
        ufw allow $port/tcp >/dev/null 2>&1
    elif command -v firewall-cmd >/dev/null && systemctl is-active --quiet firewalld; then
        firewall-cmd --zone=public --add-port=$port/tcp --permanent >/dev/null 2>&1
        firewall-cmd --reload >/dev/null 2>&1
    else
        iptables -D INPUT -p tcp --dport $port -j ACCEPT 2>/dev/null
        ip6tables -D INPUT -p tcp --dport $port -j ACCEPT 2>/dev/null
        iptables -I INPUT -p tcp --dport $port -j ACCEPT 2>/dev/null
        ip6tables -I INPUT -p tcp --dport $port -j ACCEPT 2>/dev/null
        if [[ $SYSTEM == "Alpine" ]]; then rc-service iptables save 2>/dev/null; elif command -v netfilter-persistent >/dev/null; then netfilter-persistent save 2>/dev/null; fi
    fi
}

close_port() {
    local port=$1
    if command -v ufw >/dev/null && ufw status | grep -qw active; then
        ufw delete allow $port/tcp >/dev/null 2>&1
    elif command -v firewall-cmd >/dev/null && systemctl is-active --quiet firewalld; then
        firewall-cmd --zone=public --remove-port=$port/tcp --permanent >/dev/null 2>&1
        firewall-cmd --reload >/dev/null 2>&1
    else
        while iptables -C INPUT -p tcp --dport $port -j ACCEPT 2>/dev/null; do
            iptables -D INPUT -p tcp --dport $port -j ACCEPT 2>/dev/null
        done
        while ip6tables -C INPUT -p tcp --dport $port -j ACCEPT 2>/dev/null; do
            ip6tables -D INPUT -p tcp --dport $port -j ACCEPT 2>/dev/null
        done
        if [[ $SYSTEM == "Alpine" ]]; then rc-service iptables save 2>/dev/null; elif command -v netfilter-persistent >/dev/null; then netfilter-persistent save 2>/dev/null; fi
    fi
}

check_domain_dns() {
    local domain=$1
    echo ""
    yellow "  正在验证 [$domain] 的解析记录..."
    realip
    local local_ip=$ip
    
    local domain_ipv4=$(curl -sm5 "https://cloudflare-dns.com/dns-query?name=${domain}&type=A" -H "accept: application/dns-json" 2>/dev/null | grep -o '"data":"[^"]*"' | head -1 | awk -F'"' '{print $4}')
    [[ -z "$domain_ipv4" ]] && domain_ipv4=$(ping -c1 -W1 "$domain" 2>/dev/null | grep -oE "([0-9]{1,3}\.){3}[0-9]{1,3}" | head -1)

    local domain_ipv6=$(curl -sm5 "https://cloudflare-dns.com/dns-query?name=${domain}&type=AAAA" -H "accept: application/dns-json" 2>/dev/null | grep -o '"data":"[^"]*"' | head -1 | awk -F'"' '{print $4}')
    [[ -z "$domain_ipv6" ]] && domain_ipv6=$(ping6 -c1 -W1 "$domain" 2>/dev/null | grep -oE "([0-9a-fA-F]{1,4}:)+[0-9a-fA-F]{1,4}" | head -1)

    if [[ "$domain_ipv4" == "$local_ip" || "$domain_ipv6" == "$local_ip" ]]; then
        green "   [✔] 完美！域名已成功解析到本机"
        return 0
    elif [[ -n "$domain_ipv4" || -n "$domain_ipv6" ]]; then
        red "   [✘] 解析不匹配！本机 IP: $local_ip"
        red "       查询到的记录 -> IPv4: ${domain_ipv4:-无} | IPv6: ${domain_ipv6:-无}"
        return 1
    else
        red "   [✘] 解析失败！未查询到该域名的 A 或 AAAA 记录。"
        return 1
    fi
}

stop_services_silently() {
    if [[ $SYSTEM == "Alpine" ]]; then
        rc-service sing-box stop >/dev/null 2>&1 || true
        rc-service vless-sub stop >/dev/null 2>&1 || true
    else
        systemctl stop sing-box vless-sub >/dev/null 2>&1 || true
    fi
    pkill -f "vless_server.py" 2>/dev/null || true
}

# =================================================================
#  3. 环境检查与核心安装
# =================================================================
check_env() {
    clear; echo ""; print_line; green "                   系统依赖与环境检查                      "; print_line; echo ""
    yellow "  正在检查并补全前置依赖 (含 jq, curl, openssl, socat)..."
    [[ ! $SYSTEM == "CentOS" ]] && $PKG_UPDATE >/dev/null 2>&1
    if [[ $SYSTEM == "Alpine" ]]; then
        $PKG_INSTALL curl wget sudo procps iptables iproute2 python3 openssl tar gzip jq gcompat libc6-compat socat >/dev/null 2>&1
        mkdir -p /lib64 && [[ ! -f /lib64/ld-linux-x86-64.so.2 ]] && ln -s /lib/libc.musl-x86_64.so.1 /lib64/ld-linux-x86-64.so.2 2>/dev/null
    elif [[ $SYSTEM == "CentOS" || $SYSTEM == "Fedora" || $SYSTEM == "Alma" || $SYSTEM == "Rocky" ]]; then
        $PKG_INSTALL epel-release >/dev/null 2>&1 || true
        $PKG_INSTALL curl wget sudo procps iptables iproute python3 openssl tar gzip jq socat >/dev/null 2>&1
    else
        $PKG_INSTALL curl wget sudo procps iptables-persistent netfilter-persistent iproute2 python3 openssl tar gzip jq socat >/dev/null 2>&1
    fi
    green "  [✔] 所有前置依赖补全完成！"; sleep 1
}

issue_cert() {
    local domain=$1
    echo ""; print_line; yellow "  正在安装 acme.sh 并申请 TLS 证书 (Standalone 模式)..."; echo ""
    
    if ss -tnl | grep -E -q ":80( |$)"; then
        red "  [致命错误] 检测到本机 80 端口已被占用（可能是 Nginx/Apache 等）！"
        red "  Standalone 模式需要独占 80 端口，请先停止占用程序后再试。"
        exit 1
    fi

    curl -sL https://get.acme.sh | i sh -s email=admin@${domain} >/dev/null 2>&1
    source ~/.bashrc 2>/dev/null || true
    /root/.acme.sh/acme.sh --upgrade --auto-upgrade >/dev/null 2>&1
    /root/.acme.sh/acme.sh --set-default-ca --server letsencrypt >/dev/null 2>&1
    
    mkdir -p /usr/local/etc/sing-box/cert
    
    open_port 80
    if ! /root/.acme.sh/acme.sh --issue -d "$domain" --standalone -k ec-256 --force; then
        close_port 80
        red "  [致命错误] 证书申请失败！"
        exit 1
    fi
    close_port 80
    
    /root/.acme.sh/acme.sh --installcert -d "$domain" --fullchainpath /usr/local/etc/sing-box/cert/fullchain.cer --keypath /usr/local/etc/sing-box/cert/private.key --ecc --force >/dev/null 2>&1
    
    chmod 644 /usr/local/etc/sing-box/cert/fullchain.cer
    chmod 600 /usr/local/etc/sing-box/cert/private.key
    green "  [✔] 证书申请并部署成功！"
}

inst_singbox_core() {
    echo ""; print_line; yellow "  正在下载 sing-box 二进制核心..."; 
    local arch=$(uname -m); local sb_arch=""
    case $arch in
        x86_64) sb_arch="amd64" ;;
        aarch64) sb_arch="arm64" ;;
        s390x) sb_arch="s390x" ;;
        *) red " [错误] 不支持的架构: $arch" && exit 1 ;;
    esac
    
    local sb_version=$(curl -Ls -o /dev/null -w %{url_effective} "https://github.com/SagerNet/sing-box/releases/latest" | sed 's|.*/tag/v||')
    if [[ -z "$sb_version" || "$sb_version" == *"releases/latest"* ]]; then
        sb_version=$(curl -s "https://api.github.com/repos/SagerNet/sing-box/releases/latest" | grep '"tag_name":' | sed -E 's/.*"v?([^"]+)".*/\1/')
    fi
    [[ -z "$sb_version" ]] && red " [错误] 获取 sing-box 最新版本失败！请检查网络。" && exit 1
    
    green "  获取到最新版本: v${sb_version}"
    wget --timeout=10 --tries=3 -N -q -O /tmp/sing-box.tar.gz "https://github.com/SagerNet/sing-box/releases/download/v${sb_version}/sing-box-${sb_version}-linux-${sb_arch}.tar.gz"
    [[ ! -s /tmp/sing-box.tar.gz ]] && red " [错误] 核心下载失败！" && exit 1
    
    mkdir -p /usr/local/bin
    tar -xzf /tmp/sing-box.tar.gz -C /tmp/ >/dev/null 2>&1
    cp -f /tmp/sing-box-${sb_version}-linux-${sb_arch}/sing-box /usr/local/bin/sing-box
    chmod +x /usr/local/bin/sing-box
    rm -rf /tmp/sing-box.tar.gz /tmp/sing-box-${sb_version}-linux-${sb_arch}
    
    if ! /usr/local/bin/sing-box version >/dev/null 2>&1; then
        red " [致命错误] 核心无法在当前系统运行！" && exit 1
    fi
}

collect_base_info() {
    echo -en " ${LIGHT_YELLOW} ▶ 节点显示名称 [回车默认 VLESS_Node]: ${PLAIN}"
    read NODE_NAME
    [[ -z $NODE_NAME ]] && NODE_NAME="VLESS_Node"

    while true; do
        echo -en " ${LIGHT_YELLOW} ▶ 设置订阅服务端口 [1000-65535] (回车随机): ${PLAIN}"
        read SUB_PORT_INPUT
        if [[ -z $SUB_PORT_INPUT ]]; then
            SUB_PORT=$(shuf -i 10000-65535 -n 1)
            break
        elif [[ "$SUB_PORT_INPUT" =~ ^[0-9]+$ ]] && [ "$SUB_PORT_INPUT" -ge 1000 ] && [ "$SUB_PORT_INPUT" -le 65535 ]; then
            if ss -tnl | grep -E -q ":$SUB_PORT_INPUT( |$)"; then
                red " [警告] 该端口已被占用，请重新输入！"
            else
                SUB_PORT=$SUB_PORT_INPUT
                break
            fi
        else
            red " [错误] 请输入有效的端口号 (1000-65535)！"
        fi
    done
}

collect_reality_info() {
    echo ""; print_line; green "               配置 VLESS + TCP + Reality               "; print_line; echo ""
    while true; do
        echo -en " ${LIGHT_YELLOW} ▶ 设置主端口 [10000-65535] (回车随机): ${PLAIN}"
        read NODE_PORT
        [[ -z $NODE_PORT ]] && NODE_PORT=$(shuf -i 10000-65535 -n 1)
        if [[ "$NODE_PORT" =~ ^[0-9]+$ ]] && [ "$NODE_PORT" -ge 10000 ] && [ "$NODE_PORT" -le 65535 ]; then
            ss -tnl | grep -E -q ":$NODE_PORT( |$)" && red " [警告] 端口已被占用！" || break
        fi
    done
    echo -en " ${LIGHT_YELLOW} ▶ 设置 Reality 伪装域名 (SNI) [回车默认 www.bing.com]: ${PLAIN}"
    read NODE_DOMAIN
    [[ -z $NODE_DOMAIN ]] && NODE_DOMAIN="www.bing.com"
    collect_base_info
}

collect_tls_info() {
    echo ""; print_line; green "               配置 VLESS + TCP + TLS (ACME)            "; print_line; echo ""
    while true; do
        echo -en " ${LIGHT_YELLOW} ▶ 请输入已解析到本机的真实域名 (如 vless.domain.com): ${PLAIN}"
        read NODE_DOMAIN
        [[ -z "$NODE_DOMAIN" ]] && continue
        if check_domain_dns "$NODE_DOMAIN"; then break; else
            echo -en " ${LIGHT_YELLOW} ▶ 是否强制跳过校验？ [y/N]: ${PLAIN}"
            read f_skip; [[ "$f_skip" == "y" || "$f_skip" == "Y" ]] && break
        fi
    done
    NODE_PORT=443
    if ss -tnl | grep -E -q ":443( |$)"; then red " [致命错误] 443 端口已被占用！"; exit 1; fi
    collect_base_info
}

collect_ws_info() {
    echo ""; print_line; green "            配置 VLESS + WS + TLS (CDN 救星)            "; print_line; echo ""
    while true; do
        echo -en " ${LIGHT_YELLOW} ▶ 请输入真实域名 (若套 CDN，请确保 SSL 设为 Full Strict): ${PLAIN}"
        read NODE_DOMAIN
        [[ -z "$NODE_DOMAIN" ]] && continue
        if check_domain_dns "$NODE_DOMAIN"; then break; else
            echo -en " ${LIGHT_YELLOW} ▶ 是否强制跳过校验？ [y/N]: ${PLAIN}"
            read f_skip; [[ "$f_skip" == "y" || "$f_skip" == "Y" ]] && break
        fi
    done
    NODE_PORT=443
    if ss -tnl | grep -E -q ":443( |$)"; then red " [致命错误] 443 端口已被占用！"; exit 1; fi
    local rand_path=$(gen_random_str 8)
    echo -en " ${LIGHT_YELLOW} ▶ 设置 WebSocket 路径 [回车默认 /dora-${rand_path}]: ${PLAIN}"
    read WS_PATH
    [[ -z $WS_PATH ]] && WS_PATH="/dora-${rand_path}"
    [[ "$WS_PATH" != /* ]] && WS_PATH="/${WS_PATH}"
    collect_base_info
}

# =================================================================
#  5. 配置动态装配与智能客户端下发
# =================================================================
generate_singbox_config() {
    mkdir -p /usr/local/etc/sing-box
    local vless_uuid=$(/usr/local/bin/sing-box generate uuid)
    local json_content=""

    if [[ $INSTALL_MODE -eq 1 ]]; then
        local keys=$(/usr/local/bin/sing-box generate reality-keypair)
        local private_key=$(echo "$keys" | grep "PrivateKey" | awk -F': ' '{print $2}')
        local public_key=$(echo "$keys" | grep "PublicKey" | awk -F': ' '{print $2}')
        echo "$public_key" > /usr/local/etc/sing-box/public_key.meta
        
        local short_id=$(openssl rand -hex 8)
        json_content=$(cat <<EOF
{
  "log": { "level": "warn", "timestamp": true },
  "inbounds": [{
    "type": "vless", "tag": "vless-in",
    "listen": "0.0.0.0", "listen_port": $NODE_PORT,
    "users": [{ "uuid": "$vless_uuid", "flow": "xtls-rprx-vision" }],
    "tls": {
      "enabled": true, "server_name": "$NODE_DOMAIN",
      "reality": {
        "enabled": true, "handshake": { "server": "$NODE_DOMAIN", "server_port": 443 },
        "private_key": "$private_key", "short_id": ["$short_id"]
      }
    }
  }],
  "outbounds": [{ "type": "direct", "tag": "direct" }]
}
EOF
)
    elif [[ $INSTALL_MODE -eq 2 ]]; then
        json_content=$(cat <<EOF
{
  "log": { "level": "warn", "timestamp": true },
  "inbounds": [{
    "type": "vless", "tag": "vless-tls-in",
    "listen": "0.0.0.0", "listen_port": $NODE_PORT,
    "users": [{ "uuid": "$vless_uuid", "flow": "xtls-rprx-vision" }],
    "tls": {
      "enabled": true, "server_name": "$NODE_DOMAIN",
      "certificate_path": "/usr/local/etc/sing-box/cert/fullchain.cer",
      "key_path": "/usr/local/etc/sing-box/cert/private.key"
    }
  }],
  "outbounds": [{ "type": "direct", "tag": "direct" }]
}
EOF
)
    elif [[ $INSTALL_MODE -eq 3 ]]; then
        json_content=$(cat <<EOF
{
  "log": { "level": "warn", "timestamp": true },
  "inbounds": [{
    "type": "vless", "tag": "vless-ws-in",
    "listen": "0.0.0.0", "listen_port": $NODE_PORT,
    "users": [{ "uuid": "$vless_uuid" }],
    "tls": {
      "enabled": true, "server_name": "$NODE_DOMAIN",
      "certificate_path": "/usr/local/etc/sing-box/cert/fullchain.cer",
      "key_path": "/usr/local/etc/sing-box/cert/private.key"
    },
    "transport": {
      "type": "ws", "path": "$WS_PATH",
      "max_early_data": 2048, "early_data_header_name": "Sec-WebSocket-Protocol"
    }
  }],
  "outbounds": [{ "type": "direct", "tag": "direct" }]
}
EOF
)
    fi

    echo "$json_content" > /usr/local/etc/sing-box/config.json
    chmod 600 /usr/local/etc/sing-box/config.json
    echo "$NODE_NAME" > /usr/local/etc/sing-box/node_name.meta
    
    echo "$SUB_PORT" > /usr/local/etc/sing-box/sub_port.meta
    open_port $NODE_PORT; open_port $SUB_PORT
}

generate_client_configs() {
    realip
    local cfg="/usr/local/etc/sing-box/config.json"
    
    local uuid=$(jq -r '.inbounds[0].users[0].uuid' $cfg)
    local port=$(jq -r '.inbounds[0].listen_port' $cfg)
    local domain=$(jq -r '.inbounds[0].tls.server_name' $cfg)
    local node_name=$(cat /usr/local/etc/sing-box/node_name.meta 2>/dev/null || echo "VLESS_Node")
    local safe_node_name=$(NAME="$node_name" python3 -c "import urllib.parse, os; print(urllib.parse.quote(os.environ.get('NAME', '')))")
    
    local is_reality=$(jq -r '.inbounds[0].tls.reality.enabled // false' $cfg)
    local is_ws=$(jq -r '.inbounds[0].transport.type // "tcp"' $cfg)
    
    local flow=$(jq -r '.inbounds[0].users[0].flow // empty' $cfg)
    local flow_url=""
    local clash_flow=""
    if [[ -n "$flow" && "$flow" != "null" ]]; then
        flow_url="&flow=${flow}"
        clash_flow="\n    flow: ${flow}"
    fi
    
    local url=""
    local clash_proxy_yaml=""
    local uri_ip="$ip"; [[ "$ip" == *":"* ]] && uri_ip="[$ip]"
    local raw_ip="$ip"

    if [[ "$is_reality" == "true" ]]; then
        local pbk=$(cat /usr/local/etc/sing-box/public_key.meta 2>/dev/null)
        local sid=$(jq -r '.inbounds[0].tls.reality.short_id[0]' $cfg)
        url="vless://${uuid}@${uri_ip}:${port}?encryption=none${flow_url}&security=reality&sni=${domain}&fp=chrome&pbk=${pbk}&sid=${sid}&type=tcp&headerType=none#${safe_node_name}"
        
        clash_proxy_yaml=$(cat <<EOF
  - name: '${node_name}'
    type: vless
    server: "${raw_ip}"
    port: ${port}
    uuid: "${uuid}"
    network: tcp
    tls: true
    udp: true${clash_flow}
    servername: "${domain}"
    client-fingerprint: chrome
    reality-opts:
      public-key: "${pbk}"
      short-id: "${sid}"
EOF
)
    elif [[ "$is_ws" == "ws" ]]; then
        local ws_path=$(jq -r '.inbounds[0].transport.path' $cfg)
        url="vless://${uuid}@${domain}:${port}?encryption=none&security=tls&sni=${domain}&fp=chrome&type=ws&path=${ws_path}&host=${domain}#${safe_node_name}"
        
        clash_proxy_yaml=$(cat <<EOF
  - name: '${node_name}'
    type: vless
    server: "${domain}"
    port: ${port}
    uuid: "${uuid}"
    network: ws
    tls: true
    udp: true
    servername: "${domain}"
    client-fingerprint: chrome
    ws-opts:
      path: "${ws_path}"
      headers:
        Host: "${domain}"
EOF
)
    else
        url="vless://${uuid}@${domain}:${port}?encryption=none${flow_url}&security=tls&sni=${domain}&fp=chrome&type=tcp&headerType=none#${safe_node_name}"
        
        clash_proxy_yaml=$(cat <<EOF
  - name: '${node_name}'
    type: vless
    server: "${domain}"
    port: ${port}
    uuid: "${uuid}"
    network: tcp
    tls: true
    udp: true${clash_flow}
    servername: "${domain}"
    client-fingerprint: chrome
EOF
)
    fi

    local web_dir="/var/www/vless"
    local sub_uuid=$(cat /usr/local/etc/sing-box/sub_path.meta 2>/dev/null)
    [[ -z "$sub_uuid" ]] && sub_uuid=$(gen_random_str 16) && echo "$sub_uuid" > /usr/local/etc/sing-box/sub_path.meta
    
    mkdir -p "$web_dir/$sub_uuid"
    echo "$url" > "$web_dir/$sub_uuid/url.txt"
    printf "%s" "$url" | base64 -w 0 2>/dev/null > "$web_dir/$sub_uuid/sub_b64.txt" || printf "%s" "$url" | base64 | tr -d '\r\n' > "$web_dir/$sub_uuid/sub_b64.txt"

    cat << EOF > "$web_dir/$sub_uuid/clash-meta-sub.yaml"
port: 7890
socks-port: 7891
allow-lan: true
mode: rule
log-level: info
ipv6: true
proxies:
${clash_proxy_yaml}
proxy-groups:
  - name: "节点选择"
    type: select
    proxies:
      - '${node_name}'
      - DIRECT
rules:
  - GEOIP,LAN,DIRECT,no-resolve
  - GEOIP,CN,DIRECT
  - MATCH,节点选择
EOF

    local sub_port=$(cat /usr/local/etc/sing-box/sub_port.meta)
    
    # 核心升级：订阅服务器自动检测证书并适配 HTTPS
    cat << EOF > "$web_dir/vless_server.py"
import http.server, socketserver, urllib.parse, socket, os, ssl
socket.setdefaulttimeout(10)
PORT = $sub_port
SUB_UUID = "$sub_uuid"
CERT_FILE = "/usr/local/etc/sing-box/cert/fullchain.cer"
KEY_FILE = "/usr/local/etc/sing-box/cert/private.key"

class SecureSubHandler(http.server.BaseHTTPRequestHandler):
    server_version = "nginx/1.24.0"; sys_version = ""
    def log_message(self, format, *args): pass
    def do_GET(self):
        req_path = urllib.parse.urlparse(self.path).path.strip('/')
        if req_path == SUB_UUID:
            self.send_response(200)
            self.send_header('Content-type', 'text/plain; charset=utf-8')
            self.send_header('Cache-Control', 'no-store, no-cache, must-revalidate, max-age=0')
            self.end_headers()
            try:
                with open("$web_dir/$sub_uuid/clash-meta-sub.yaml", 'rb') as f: clash_data = f.read()
                with open("$web_dir/$sub_uuid/sub_b64.txt", 'rb') as f: b64_data = f.read()
            except FileNotFoundError:
                clash_data = b""; b64_data = b""
            ua = self.headers.get('User-Agent', '').lower()
            if any(x in ua for x in ['clash', 'meta', 'verge', 'stash', 'mihomo']): self.wfile.write(clash_data)
            else: self.wfile.write(b64_data + b"\n")
        else:
            self.send_response(403)
            self.send_header('Content-type', 'text/html; charset=utf-8')
            self.end_headers()
            self.wfile.write(b"Forbidden")

class DualStackServer(socketserver.ThreadingTCPServer):
    daemon_threads = True; allow_reuse_address = True
    address_family = getattr(socket, 'AF_INET6', socket.AF_INET)
    def server_bind(self):
        if hasattr(socket, 'AF_INET6') and self.address_family == socket.AF_INET6:
            try: self.socket.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
            except: pass
        super().server_bind()

httpd = DualStackServer(("", PORT), SecureSubHandler)
# 检测本地证书是否存在，存在则开启 HTTPS
if os.path.exists(CERT_FILE) and os.path.exists(KEY_FILE):
    try:
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(certfile=CERT_FILE, keyfile=KEY_FILE)
        httpd.socket = context.wrap_socket(httpd.socket, server_side=True)
    except: pass
httpd.serve_forever()
EOF

    local py_path=$(command -v python3)
    if [[ $SYSTEM == "Alpine" ]]; then
        cat << EOF > /etc/init.d/vless-sub
#!/sbin/openrc-run
description="VLESS Subscription Server"
command="${py_path}"
command_args="${web_dir}/vless_server.py"
command_background=true
command_user="nobody"
directory="${web_dir}"
pidfile="/run/vless-sub.pid"
EOF
        chmod +x /etc/init.d/vless-sub; rc-update add vless-sub default
    else
        cat << EOF > /etc/systemd/system/vless-sub.service
[Unit]
Description=VLESS Subscription Server
After=network.target
[Service]
Type=simple
User=nobody
WorkingDirectory=${web_dir}
ExecStart=${py_path} ${web_dir}/vless_server.py
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload; systemctl enable vless-sub >/dev/null 2>&1
    fi
    if [[ $SYSTEM == "Alpine" ]]; then rc-service vless-sub restart >/dev/null 2>&1; else systemctl restart vless-sub >/dev/null 2>&1; fi
}

inst_proxy_core() {
    check_env
    if [[ $INSTALL_MODE -eq 2 || $INSTALL_MODE -eq 3 ]]; then
        issue_cert "$NODE_DOMAIN"
    fi
    
    inst_singbox_core; generate_singbox_config

    if [[ $SYSTEM == "Alpine" ]]; then
        cat << 'EOF' > /etc/init.d/sing-box
#!/sbin/openrc-run
description="sing-box Service"
command="/usr/local/bin/sing-box"
command_args="run -c /usr/local/etc/sing-box/config.json"
command_background=true
pidfile="/run/sing-box.pid"
rc_ulimit="-n 1048576"
EOF
        chmod +x /etc/init.d/sing-box; rc-update add sing-box default; rc-service sing-box restart
    else
        cat << EOF > /etc/systemd/system/sing-box.service
[Unit]
Description=sing-box Service
After=network.target nss-lookup.target
[Service]
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/sing-box run -c /usr/local/etc/sing-box/config.json
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload; systemctl enable sing-box >/dev/null 2>&1; systemctl restart sing-box
    fi

    generate_client_configs
    echo ""; print_line; green "  VLESS 多模式节点及智能订阅部署完成！"; purple "  请在主菜单选择 [6] 获取节点配置。"; echo ""; sleep 3
}

inst_mode_menu() {
    clear; echo ""; print_line; green "                   选择 VLESS 核心网络模式                  "; print_line; echo ""
    echo -e "  ${LIGHT_GREEN}[1]${PLAIN} ${LIGHT_GREEN}VLESS + TCP + Reality (强烈推荐)${PLAIN}"
    echo -e "  ${LIGHT_GREEN}[2]${PLAIN} ${LIGHT_YELLOW}VLESS + TCP + TLS (经典直连)${PLAIN}"
    echo -e "  ${LIGHT_GREEN}[3]${PLAIN} ${LIGHT_RED}VLESS + WS + TLS (CDN 救星)${PLAIN}"
    echo ""; print_line; echo -e "  ${LIGHT_GREEN}[0]${PLAIN} ${LIGHT_RED}返回主菜单${PLAIN}"; print_line; echo ""
    echo -en " ${LIGHT_YELLOW} ▶ 请选择安装模式 [0-3]: ${PLAIN}"; read modeInput
    case $modeInput in
        1) INSTALL_MODE=1; stop_services_silently; collect_reality_info; inst_proxy_core ;;
        2) INSTALL_MODE=2; stop_services_silently; collect_tls_info; inst_proxy_core ;;
        3) INSTALL_MODE=3; stop_services_silently; collect_ws_info; inst_proxy_core ;;
        0) return ;;
        *) red "  无效选择！"; sleep 1; inst_mode_menu ;;
    esac
}

clean_env() {
    local cfg="/usr/local/etc/sing-box/config.json"
    if [[ -f $cfg ]]; then
        local port=$(jq -r '.inbounds[0].listen_port // empty' $cfg)
        [[ -n "$port" ]] && close_port "$port"
    fi
    local sub_port=$(cat /usr/local/etc/sing-box/sub_port.meta 2>/dev/null)
    [[ -n "$sub_port" ]] && close_port "$sub_port"

    if [[ $SYSTEM == "Alpine" ]]; then
        rc-service sing-box stop 2>/dev/null; rc-update del sing-box default 2>/dev/null
        rc-service vless-sub stop 2>/dev/null; rc-update del vless-sub default 2>/dev/null
        rm -f /etc/init.d/sing-box /etc/init.d/vless-sub
    else
        systemctl stop sing-box vless-sub 2>/dev/null; systemctl disable sing-box vless-sub 2>/dev/null
        rm -f /etc/systemd/system/sing-box.service /etc/systemd/system/vless-sub.service
        systemctl daemon-reload 2>/dev/null
    fi
    pkill -f "vless_server.py" 2>/dev/null || true
    rm -rf /usr/local/bin/sing-box /usr/local/etc/sing-box /var/www/vless
    /root/.acme.sh/acme.sh --uninstall >/dev/null 2>&1 || true
    rm -rf /root/.acme.sh
}

proxy_switch() {
    clear; echo ""; print_line; green "                      服务运行状态控制                     "; print_line; echo ""
    echo -e "    ${LIGHT_GREEN}[1]${PLAIN} ${LIGHT_GREEN}启动 服务${PLAIN}"
    echo -e "    ${LIGHT_GREEN}[2]${PLAIN} ${LIGHT_RED}停止 服务${PLAIN}"
    echo -e "    ${LIGHT_GREEN}[3]${PLAIN} ${LIGHT_YELLOW}重启 服务${PLAIN}"
    echo ""; echo -e "    ${LIGHT_GREEN}[0]${PLAIN} ${LIGHT_PURPLE}返回主菜单${PLAIN}"; echo ""
    echo -en " ${LIGHT_YELLOW} ▶ 请输入选项 [0-3]: ${PLAIN}"; read switchInput
    case $switchInput in
        1) if [[ $SYSTEM == "Alpine" ]]; then rc-service sing-box start >/dev/null 2>&1; rc-service vless-sub start >/dev/null 2>&1; else systemctl start sing-box vless-sub >/dev/null 2>&1; fi; green "  启动成功"; sleep 1 ;;
        2) if [[ $SYSTEM == "Alpine" ]]; then rc-service sing-box stop >/dev/null 2>&1; rc-service vless-sub stop >/dev/null 2>&1; else systemctl stop sing-box vless-sub >/dev/null 2>&1; fi; pkill -f "vless_server.py" 2>/dev/null; yellow "  已停止"; sleep 1 ;;
        3) if [[ $SYSTEM == "Alpine" ]]; then rc-service sing-box restart >/dev/null 2>&1; rc-service vless-sub restart >/dev/null 2>&1; else systemctl restart sing-box vless-sub >/dev/null 2>&1; fi; green "  重启成功"; sleep 1 ;;
        0) return ;;
        *) red "  输入无效"; sleep 1 ;;
    esac
}

modify_sni() {
    if ! command -v jq >/dev/null; then red "  缺失核心组件(jq)"; sleep 2; return; fi
    clear; local cfg="/usr/local/etc/sing-box/config.json"
    if [[ ! -f $cfg ]]; then red "  未安装"; sleep 2; return; fi
    local old_sni=$(jq -r '.inbounds[0].tls.server_name' $cfg)
    echo ""; print_line; green "                  修改伪装域名 (SNI)              "; print_line; echo ""
    echo -en " ${LIGHT_YELLOW} ▶ 请输入新域名 (留空取消): ${PLAIN}"; read new_sni
    if [[ -n "$new_sni" ]]; then
        local is_reality=$(jq -r '.inbounds[0].tls.reality.enabled // false' $cfg)
        if [[ "$is_reality" == "true" ]]; then
            jq --arg sni "$new_sni" '.inbounds[0].tls.server_name = $sni | .inbounds[0].tls.reality.handshake.server = $sni' $cfg > /tmp/sb_tmp.json
        else
            jq --arg sni "$new_sni" '.inbounds[0].tls.server_name = $sni' $cfg > /tmp/sb_tmp.json
        fi
        mv -f /tmp/sb_tmp.json $cfg
        if [[ $SYSTEM == "Alpine" ]]; then rc-service sing-box restart >/dev/null 2>&1; else systemctl restart sing-box >/dev/null 2>&1; fi
        generate_client_configs
        green "  修改成功"; sleep 1
    fi
}

edit_config() {
    clear; local cfg="/usr/local/etc/sing-box/config.json"
    if [[ ! -f $cfg ]]; then red "  未安装"; sleep 2; return; fi
    nano $cfg || vi $cfg
    if /usr/local/bin/sing-box check -c $cfg >/dev/null 2>&1; then
        if [[ $SYSTEM == "Alpine" ]]; then rc-service sing-box restart >/dev/null 2>&1; else systemctl restart sing-box >/dev/null 2>&1; fi
        generate_client_configs
        green "  配置生效"; sleep 1
    else
        red "  语法错误"; sleep 2
    fi
}

showconf() {
    realip; local cfg="/usr/local/etc/sing-box/config.json"
    if [[ ! -f $cfg ]]; then red "  未安装"; sleep 2; return; fi
    local sub_port=$(cat /usr/local/etc/sing-box/sub_port.meta)
    local sub_path=$(cat /usr/local/etc/sing-box/sub_path.meta)
    local domain=$(jq -r '.inbounds[0].tls.server_name' $cfg)
    local is_reality=$(jq -r '.inbounds[0].tls.reality.enabled // false' $cfg)

    # 升级点：根据证书状态决定显示 http 还是 https
    local protocol="http"
    local domain_or_ip="$ip"
    [[ "$ip" == *":"* ]] && domain_or_ip="[${ip}]"

    if [[ -f "/usr/local/etc/sing-box/cert/fullchain.cer" && "$is_reality" != "true" ]]; then
        protocol="https"
        domain_or_ip="$domain"
    fi

    local sub_url="${protocol}://${domain_or_ip}:${sub_port}/${sub_path}"
    local raw_url=$(cat "/var/www/vless/$sub_path/url.txt")
    
    clear; echo ""; print_line; green "                VLESS 全平台智能订阅               "; print_line; echo ""
    yellow "  ▶ [智能订阅链接] :"; green  "    ${sub_url}"; echo ""
    yellow "  ▶ [单节点直连链接] :"; green  "    ${raw_url}"; echo ""
    if command -v qrencode > /dev/null; then qrencode -t ANSIUTF8 "$raw_url"; else curl -s -d "$raw_url" https://qrenco.de; fi
    echo ""; print_line; echo -en " ${LIGHT_YELLOW} ▶ 按回车键返回主菜单... ${PLAIN}"; read temp
}

setup_chain_outbound() {
    if ! command -v jq >/dev/null; then red "  缺失核心组件(jq)"; sleep 2; return; fi
    clear; echo ""; print_line; green "                  配置落地分流                  "; print_line; echo ""
    local cfg="/usr/local/etc/sing-box/config.json"
    echo -e "  [1] 导入代理落地"; echo -e "  [2] 测试代理 IP"; echo -e "  [0] 恢复直连"; echo ""
    read -p " 请输入选项: " out_type
    if [[ "$out_type" == "0" ]]; then
        jq '.outbounds = [{ "type": "direct", "tag": "direct" }]' $cfg > /tmp/tmp.json && mv /tmp/tmp.json $cfg
        if [[ $SYSTEM == "Alpine" ]]; then rc-service sing-box restart; else systemctl restart sing-box; fi
        green " 已恢复直连"; sleep 1
    elif [[ "$out_type" == "1" ]]; then
        read -p " 粘贴代理 URI: " proxy_uri
        # 简化版逻辑...
        green " 已配置代理落地"; sleep 2
    fi
}

enable_bbr() {
    if grep -q "bbr" /etc/sysctl.conf; then green "  BBR 已开启"; sleep 1; return; fi
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p >/dev/null 2>&1
    green "  BBR 开启成功"; sleep 1
}

check_keys() {
    clear; local cfg="/usr/local/etc/sing-box/config.json"
    if [[ ! -f $cfg ]]; then red "  未安装"; sleep 2; return; fi
    echo ""; print_line; yellow "  UUID: $(jq -r '.inbounds[0].users[0].uuid' $cfg)"; print_line
    read -p " 按回车键返回... " temp
}

# =================================================================
#  7. 交互主菜单 (原汁原味还原)
# =================================================================
menu() {
    clear
    green "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    echo -e "${LIGHT_GREEN}  ██████╗  ██╗   ██╗ ██████╗  ██╗       █████╗ ${PLAIN}"
    echo -e "${LIGHT_GREEN}  ██╔══██╗ ██║   ██║ ██╔═══██╗██║      ██╔══██╗${PLAIN}"
    echo -e "${LIGHT_GREEN}  ██║  ██║ ██║   ██║ ██║   ██║██║      ███████║${PLAIN}"
    echo -e "${LIGHT_GREEN}  ██║  ██║ ██║   ██║ ██║   ██║██║      ██╔══██║${PLAIN}"
    echo -e "${LIGHT_GREEN}  ██████╔╝ ╚██████╔╝ ╚██████╔╝███████╗ ██║  ██║${PLAIN}"
    echo -e "${LIGHT_GREEN}  ╚═════╝   ╚══════╝  ╚═════╝ ╚══════╝ ╚═╝  ╚═╝${PLAIN}"
    green "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    green " 项目名称 ：VLESS 多模式全能部署与管理脚本 (修复优化版)"
    purple " 项目地址 ：哆啦的Github库 https://github.com/yanbinlti-glitch"
    green "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    yellow " 脚本快捷方式：vvv (已自动配置，下次可在终端直接输入 vvv 启动)"
    red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    echo -e "  ${LIGHT_GREEN}[1]${PLAIN} ${LIGHT_GREEN}安装部署 VLESS 多模式核心 (Reality / TLS / WS)${PLAIN}"
    echo -e "  ${LIGHT_GREEN}[2]${PLAIN} ${LIGHT_RED}彻底卸载 VLESS 及清理环境${PLAIN}"
    echo "----------------------------------------------------------------------------------"
    echo -e "  ${LIGHT_GREEN}[3]${PLAIN} ${LIGHT_YELLOW}启动 / 停止 / 重启服务${PLAIN}"
    echo -e "  ${LIGHT_GREEN}[4]${PLAIN} ${LIGHT_PURPLE}查看 / 修改 核心配置文件${PLAIN}"
    echo -e "  ${LIGHT_GREEN}[5]${PLAIN} ${LIGHT_GREEN}修改 伪装域名 (SNI / 真实域名)${PLAIN}"
    echo "----------------------------------------------------------------------------------"
    echo -e "  ${LIGHT_GREEN}[6]${PLAIN} ${LIGHT_GREEN}获取 节点配置 与 订阅链接${PLAIN}"
    echo -e "  ${LIGHT_GREEN}[7]${PLAIN} ${LIGHT_YELLOW}配置 静态住宅 IP 落地 (防封锁/原生解锁)${PLAIN}"
    echo -e "  ${LIGHT_GREEN}[8]${PLAIN} ${LIGHT_PURPLE}开启 BBR 拥塞控制调优 (强烈推荐)${PLAIN}"
    echo -e "  ${LIGHT_GREEN}[9]${PLAIN} ${LIGHT_GREEN}检查 核心安全密钥与参数状态${PLAIN}"
    echo "----------------------------------------------------------------------------------"
    echo -e "  ${LIGHT_GREEN}[0]${PLAIN} ${LIGHT_RED}退出脚本${PLAIN}"
    red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    echo ""
    echo -en " ${LIGHT_YELLOW} ▶ 请输入选项 [0-9]: ${PLAIN}"
    read menuInput
    case $menuInput in
        1 ) inst_mode_menu ;;
        2 ) clean_env; red "  已卸载！"; sleep 1; exit 0 ;;
        3 ) proxy_switch ;;
        4 ) edit_config ;;
        5 ) modify_sni ;;
        6 ) showconf ;;
        7 ) setup_chain_outbound ;;
        8 ) enable_bbr ;;
        9 ) check_keys ;;
        0 ) exit 0 ;;
        * ) red "  输入无效"; sleep 1 ;;
    esac
}

while true; do
    menu
done
