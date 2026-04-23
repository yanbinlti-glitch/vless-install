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

    curl -sL https://get.acme.sh | sh -s email=admin@${domain} >/dev/null 2>&1
    source ~/.bashrc 2>/dev/null || true
    /root/.acme.sh/acme.sh --upgrade --auto-upgrade >/dev/null 2>&1
    /root/.acme.sh/acme.sh --set-default-ca --server letsencrypt >/dev/null 2>&1
    
    mkdir -p /usr/local/etc/sing-box/cert
    
    open_port 80
    if ! /root/.acme.sh/acme.sh --issue -d "$domain" --standalone -k ec-256 --force; then
        close_port 80
        red "  [致命错误] 证书申请失败！"
        red "  请检查: 1. 域名是否准确解析到本机 IP"
        red "          2. 防火墙是否放行了 80 端口"
        red "          3. 若使用了 CDN，请确保证书申请期间已设为【仅 DNS (灰云)】"
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
        red " [致命错误] 核心无法在当前系统运行！可能是不兼容的架构或缺失底层 C 库。" && exit 1
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
            echo -en " ${LIGHT_YELLOW} ▶ 是否强制跳过校验？(选y自担证书申请失败风险) [y/N]: ${PLAIN}"
            read f_skip; [[ "$f_skip" == "y" || "$f_skip" == "Y" ]] && break
        fi
    done
    NODE_PORT=443
    if ss -tnl | grep -E -q ":443( |$)"; then red " [致命错误] 本机 443 端口已被占用，请先停止占用程序 (如 Nginx)！"; exit 1; fi
    collect_base_info
}

collect_ws_info() {
    echo ""; print_line; green "            配置 VLESS + WS + TLS (CDN 救星)            "; print_line; echo ""
    red "  ⚠️ [重要警告] 如果您使用 Cloudflare 等 CDN 服务，请务必先将域名解析设置为"
    red "               【仅 DNS (灰云)】状态！等脚本部署完成且证书申请成功后，"
    red "               再到 CDN 面板开启代理 (小黄云)，否则将导致 TLS 证书申请失败！"
    echo ""
    while true; do
        echo -en " ${LIGHT_YELLOW} ▶ 请输入真实域名 (若套 CDN，请确保 SSL 设为 Full Strict): ${PLAIN}"
        read NODE_DOMAIN
        [[ -z "$NODE_DOMAIN" ]] && continue
        if check_domain_dns "$NODE_DOMAIN"; then break; else
            echo -en " ${LIGHT_YELLOW} ▶ 是否强制跳过校验？(套了 CDN 查不出本机 IP 属正常，选 y 即可) [y/N]: ${PLAIN}"
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
        yellow "  正在生成 Reality 密钥对..."
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

    chown -R root:root "$web_dir"
    find "$web_dir" -type d -exec chmod 755 {} +
    find "$web_dir" -type f -exec chmod 644 {} +

    local sub_port=$(cat /usr/local/etc/sing-box/sub_port.meta)
    
    # 升级：注入 HTTPS 证书处理 和 Headers 自动更新响应头
    cat << EOF > "$web_dir/vless_server.py"
import http.server, socketserver, urllib.parse, socket, os, ssl
socket.setdefaulttimeout(10)
PORT = $sub_port
SUB_UUID = "$sub_uuid"
CERT_PATH = "/usr/local/etc/sing-box/cert/fullchain.cer"
KEY_PATH = "/usr/local/etc/sing-box/cert/private.key"

class SecureSubHandler(http.server.BaseHTTPRequestHandler):
    server_version = "nginx/1.24.0"; sys_version = ""
    def log_message(self, format, *args): pass
    def do_GET(self):
        req_path = urllib.parse.urlparse(self.path).path.strip('/')
        if req_path == SUB_UUID:
            self.send_response(200)
            self.send_header('Content-type', 'text/plain; charset=utf-8')
            # --- 新增：高级订阅响应头 ---
            self.send_header('profile-update-interval', '24')
            self.send_header('profile-title', 'VLESS-Pro-Sub')
            self.send_header('Subscription-Userinfo', 'upload=0; download=0; total=1073741824000; expire=0')
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
            self.wfile.write(b"<html><head><title>403 Forbidden</title></head><body><center><h1>403 Forbidden</h1></center><hr><center>nginx</center></body></html>")

class DualStackServer(socketserver.ThreadingTCPServer):
    daemon_threads = True; allow_reuse_address = True
    address_family = getattr(socket, 'AF_INET6', socket.AF_INET)
    def server_bind(self):
        if hasattr(socket, 'AF_INET6') and self.address_family == socket.AF_INET6:
            try: self.socket.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
            except: pass
        super().server_bind()

try: httpd = DualStackServer(("", PORT), SecureSubHandler)
except OSError:
    DualStackServer.address_family = socket.AF_INET
    httpd = DualStackServer(("0.0.0.0", PORT), SecureSubHandler)

# --- 新增：尝试包裹 SSL/TLS 层 ---
if os.path.exists(CERT_PATH) and os.path.exists(KEY_PATH):
    try:
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(certfile=CERT_PATH, keyfile=KEY_PATH)
        httpd.socket = context.wrap_socket(httpd.socket, server_side=True)
    except Exception as e:
        pass

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
Documentation=https://sing-box.sagernet.org/
After=network.target nss-lookup.target
[Service]
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/sing-box run -c /usr/local/etc/sing-box/config.json
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000
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
    echo -e "      ${LIGHT_PURPLE}↳ 特性:${PLAIN} 免域名 / 防御主动探测极佳 / 适合所有 VPS"
    echo ""
    echo -e "  ${LIGHT_GREEN}[2]${PLAIN} ${LIGHT_YELLOW}VLESS + TCP + TLS (经典直连)${PLAIN}"
    echo -e "      ${LIGHT_PURPLE}↳ 特性:${PLAIN} 需自备域名 / 全站真实伪装 / 自动申请证书"
    echo ""
    echo -e "  ${LIGHT_GREEN}[3]${PLAIN} ${LIGHT_RED}VLESS + WS + TLS (CDN 救星)${PLAIN}"
    echo -e "      ${LIGHT_PURPLE}↳ 特性:${PLAIN} 需自备域名 / 支持 Cloudflare / 拯救被墙 IP"
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
        systemctl stop sing-box vless-sub 2>/dev/null
        systemctl disable sing-box vless-sub 2>/dev/null
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
    if ! command -v jq >/dev/null; then red "  [错误] 缺失核心组件(jq)，请先执行安装部署 (选项 1)！"; sleep 2; return; fi
    clear; local cfg="/usr/local/etc/sing-box/config.json"
    if [[ ! -f $cfg ]]; then red "  未检测到配置文件！"; sleep 2; return; fi
    local old_sni=$(jq -r '.inbounds[0].tls.server_name' $cfg)
    echo ""; print_line; green "                  修改伪装域名 (SNI / 真实域名)              "; print_line; echo ""
    yellow "  当前配置的域名: $old_sni"; echo ""
    echo -en " ${LIGHT_YELLOW} ▶ 请输入新的域名 (留空取消): ${PLAIN}"; read new_sni
    if [[ -n "$new_sni" && "$new_sni" != "$old_sni" ]]; then
        local is_reality=$(jq -r '.inbounds[0].tls.reality.enabled // false' $cfg)
        if [[ "$is_reality" == "true" ]]; then
            jq --arg sni "$new_sni" '.inbounds[0].tls.server_name = $sni | .inbounds[0].tls.reality.handshake.server = $sni' $cfg > /tmp/sb_tmp.json
        else
            jq --arg sni "$new_sni" '.inbounds[0].tls.server_name = $sni' $cfg > /tmp/sb_tmp.json
            yellow "  [注意] 仅修改了配置中的伪装域名。若是真实域名变更，已有证书将不匹配，建议在主菜单选择重新安装！"
            sleep 3
        fi
        if [ -s /tmp/sb_tmp.json ]; then
            mv -f /tmp/sb_tmp.json $cfg
            green "  已更新域名为 $new_sni，正在重启并同步订阅..."
            if [[ $SYSTEM == "Alpine" ]]; then rc-service sing-box restart >/dev/null 2>&1; else systemctl restart sing-box >/dev/null 2>&1; fi
            generate_client_configs
            green "  更新完成！(建议前往客户端重新刷新订阅)"
        else
            red "  [错误] 配置文件解析失败！"
        fi
    else
        yellow "  操作已取消。"
    fi
    echo ""; echo -en " ${LIGHT_YELLOW} ▶ 按回车键返回主菜单... ${PLAIN}"; read temp
}

edit_config() {
    clear; local cfg="/usr/local/etc/sing-box/config.json"
    if [[ ! -f $cfg ]]; then red "  未检测到配置文件！"; sleep 2; return; fi
    echo ""; print_line; green "                  当前核心 JSON 配置                   "; print_line; echo ""
    cat $cfg; echo ""; print_line
    echo -en " ${LIGHT_YELLOW} ▶ 是否手动修改配置文件？(y/n) [默认: n]: ${PLAIN}"; read edit_choice
    if [[ "$edit_choice" == "y" || "$edit_choice" == "Y" ]]; then
        cp $cfg /tmp/config_backup.json
        if command -v nano >/dev/null; then nano $cfg; else vi $cfg; fi
        yellow "  正在校验语法..."
        if ! /usr/local/bin/sing-box check -c $cfg >/dev/null 2>&1; then
            red "  [错误] 语法错误！已回滚配置。"; mv /tmp/config_backup.json $cfg
        else
            green "  语法通过，正在重启同步..."; rm -f /tmp/config_backup.json
            if [[ $SYSTEM == "Alpine" ]]; then rc-service sing-box restart >/dev/null 2>&1; else systemctl restart sing-box >/dev/null 2>&1; fi
            generate_client_configs
            green "  重启同步完成！"
        fi
    fi
    echo ""; echo -en " ${LIGHT_YELLOW} ▶ 按回车键返回主菜单... ${PLAIN}"; read temp
}

# --- 升级：获取节点及智能一键导入链接 ---
showconf() {
    realip; local cfg="/usr/local/etc/sing-box/config.json"
    if [[ ! -f $cfg ]]; then red "  未检测到配置，请先安装！"; sleep 2; return; fi
    
    local sub_port=$(cat /usr/local/etc/sing-box/sub_port.meta)
    local sub_path=$(cat /usr/local/etc/sing-box/sub_path.meta)
    
    # 动态检测是否支持 HTTPS
    local proto="http"
    if [[ -f "/usr/local/etc/sing-box/cert/fullchain.cer" ]]; then proto="https"; fi
    
    local sub_url="${proto}://${ip}:${sub_port}/${sub_path}"
    [[ "$ip" == *":"* ]] && sub_url="${proto}://[${ip}]:${sub_port}/${sub_path}"
    
    # 如果不是 Reality 模式，说明配置了真实域名，优先用域名作为订阅地址
    local is_reality=$(jq -r '.inbounds[0].tls.reality.enabled // false' $cfg)
    if [[ "$is_reality" != "true" ]]; then
        local domain=$(jq -r '.inbounds[0].tls.server_name' $cfg)
        [[ -n "$domain" && "$domain" != "null" ]] && sub_url="${proto}://${domain}:${sub_port}/${sub_path}"
    fi

    local raw_url=$(cat "/var/www/vless/$sub_path/url.txt")
    
    # URL 编码，用于拼接一键导入 Scheme
    local safe_sub_url=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${sub_url}'))")
    
    clear; echo ""; print_line; green "                VLESS 全平台智能订阅               "; print_line; echo ""
    
    yellow "  ▶ [通用智能订阅链接] (请复制后在软件中手动添加订阅)"
    green  "    ${sub_url}"; echo ""
    
    yellow "  ▶ [一键导入快捷链接] (在手机/电脑浏览器中直接访问以下地址即可唤起 APP)"
    purple "    [Clash / Verge 一键导入]: "
    green  "    clash://install-config?url=${safe_sub_url}&name=VLESS-Sub"
    purple "    [Shadowrocket 一键导入]: "
    green  "    sub://${safe_sub_url}"
    purple "    [v2rayNG 一键导入]: "
    green  "    v2rayng://install-config?url=${safe_sub_url}"
    echo ""
    
    yellow "  ▶ [单节点直连链接] (适用无法使用订阅的极简客户端)"
    green  "    ${raw_url}"; echo ""
    
    if command -v qrencode > /dev/null; then 
        echo ""; purple "  提示：若二维码断层，请缩小终端字体"; echo ""
        qrencode -t ANSIUTF8 "$raw_url"
    else 
        curl -s -d "$raw_url" https://qrenco.de
    fi
    echo ""; print_line; echo -en " ${LIGHT_YELLOW} ▶ 按回车键返回主菜单... ${PLAIN}"; read temp
}

setup_chain_outbound() {
    if ! command -v jq >/dev/null; then red "  [错误] 缺失核心组件(jq)，请先执行安装部署 (选项 1)！"; sleep 2; return; fi
    clear; echo ""; print_line; green "                  配置静态住宅 IP 落地 (链式代理)                  "; print_line; echo ""
    local cfg="/usr/local/etc/sing-box/config.json"
    local tmp_cfg="/tmp/sb_tmp.json"
    
    if [[ ! -f $cfg ]]; then red "  [错误] 未检测到配置，请先安装服务！"; sleep 2; return; fi

    echo -e "  支持使用标准 URI 格式一键配置落地节点，实现原生 IP 解锁。"
    echo -e "  支持协议: ${LIGHT_PURPLE}socks5://, http://, https://${PLAIN}"
    echo -e "  格式示例: ${LIGHT_YELLOW}socks5://username:password@1.2.3.4:1080${PLAIN} (无密码可省去 user:pass@)"
    echo ""
    echo -e "  ${LIGHT_GREEN}[1]${PLAIN} ${LIGHT_YELLOW}一键导入代理 URI (Socks5/HTTP/HTTPS)${PLAIN}"
    echo -e "  ${LIGHT_GREEN}[2]${PLAIN} ${LIGHT_GREEN}测试当前落地 IP 连通性与归属地 🔍${PLAIN}"
    echo -e "  ${LIGHT_GREEN}[0]${PLAIN} ${LIGHT_RED}恢复直连 (撤销住宅 IP，恢复 Direct)${PLAIN}"
    echo ""
    echo -en " ${LIGHT_YELLOW} ▶ 请选择操作 [0-2]: ${PLAIN}"; read out_type

    if [[ "$out_type" == "0" ]]; then
        jq 'del(.route) | .outbounds = [{ "type": "direct", "tag": "direct" }] | if .inbounds[0].transport.type != "ws" then .inbounds[0].users[0].flow = "xtls-rprx-vision" else . end' "$cfg" > "$tmp_cfg"
        if [ -s "$tmp_cfg" ] && jq . "$tmp_cfg" >/dev/null 2>&1; then
            mv -f "$tmp_cfg" "$cfg"
            if [[ $SYSTEM == "Alpine" ]]; then rc-service sing-box restart >/dev/null 2>&1; else systemctl restart sing-box >/dev/null 2>&1; fi
            generate_client_configs
            green "  [✔] 已撤销住宅 IP 落地，恢复为 VPS 全局直连模式 (已重新开启 Vision 加速)！"
            purple "  💡 重要提示：节点配置已变，请在客户端【更新订阅】！"
            sleep 3; return
        else
            red "  [✘] 配置文件修改失败！"; sleep 2; return
        fi
    fi

    if [[ "$out_type" == "2" ]]; then
        echo ""; print_line
        local cur_type=$(jq -r '.outbounds[] | select(.tag == "proxy") | .type' "$cfg" 2>/dev/null)
        local is_tls=$(jq -r '.outbounds[] | select(.tag == "proxy") | .tls.enabled // false' "$cfg" 2>/dev/null)
        
        if [[ -z "$cur_type" ]]; then
            yellow "  当前未配置落地节点 (处于 VPS 直连模式)，无需测试。"
        else
            local cur_ip=$(jq -r '.outbounds[] | select(.tag == "proxy") | .server' "$cfg")
            local cur_port=$(jq -r '.outbounds[] | select(.tag == "proxy") | .server_port' "$cfg")
            local cur_user=$(jq -r '.outbounds[] | select(.tag == "proxy") | .username // empty' "$cfg")
            local cur_pass=$(jq -r '.outbounds[] | select(.tag == "proxy") | .password // empty' "$cfg")
            
            local proxy_url=""
            if [[ "$cur_type" == "socks" ]]; then
                [[ -n "$cur_user" ]] && proxy_url="socks5h://${cur_user}:${cur_pass}@${cur_ip}:${cur_port}" || proxy_url="socks5h://${cur_ip}:${cur_port}"
            elif [[ "$cur_type" == "http" ]]; then
                if [[ "$is_tls" == "true" ]]; then
                    [[ -n "$cur_user" ]] && proxy_url="https://${cur_user}:${cur_pass}@${cur_ip}:${cur_port}" || proxy_url="https://${cur_ip}:${cur_port}"
                else
                    [[ -n "$cur_user" ]] && proxy_url="http://${cur_user}:${cur_pass}@${cur_ip}:${cur_port}" || proxy_url="http://${cur_ip}:${cur_port}"
                fi
            else
                red "  当前配置的落地协议 ($cur_type) 不支持快捷测试。"
                sleep 2; return
            fi

            yellow "  正在通过代理连接测试网络 (Timeout: 10s)..."
            local test_ip=$(curl -x "$proxy_url" -sL -m 10 https://api.ipify.org 2>/dev/null)
            
            if [[ -n "$test_ip" && "$test_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                green "  [✔] 连通性测试成功！"
                yellow "  ▶ 代理入口地址: $cur_ip:$cur_port"
                yellow "  ▶ 实际出口 IP : $test_ip"
                
                local ip_info=$(curl -x "$proxy_url" -sL -m 10 "http://ip-api.com/json/$test_ip?lang=zh-CN" 2>/dev/null)
                local country=$(echo "$ip_info" | jq -r '.country // "未知"')
                local isp=$(echo "$ip_info" | jq -r '.isp // "未知"')
                purple "  ▶ 归属地信息  : $country | ISP: $isp"
            else
                red "  [✘] 测试失败！无法连接到该代理。"
                echo -e "      ${LIGHT_PURPLE}排错指南：${PLAIN}"
                echo "      1. 代理服务器宕机 / 额度耗尽 / IP未加白名单"
                echo "      2. URI 格式拼写错误 (特别是包含特殊字符的密码)"
                if [[ "$is_tls" == "true" && "$cur_type" == "http" ]]; then
                    yellow "      3. ⚠️ 注意: 您开启了 HTTPS 代理，部分旧系统 curl 版本过低可能导致测试误报，可直接到客户端连接测试。"
                fi
            fi
        fi
        echo ""; echo -en " ${LIGHT_YELLOW} ▶ 按回车键返回主菜单... ${PLAIN}"; read temp
        return
    fi

    if [[ "$out_type" == "1" ]]; then
        echo -en " ${LIGHT_YELLOW} ▶ 请粘贴代理 URI: ${PLAIN}"; read proxy_uri
        
        [[ -z "$proxy_uri" ]] && { red "  [错误] 链接不能为空！操作取消。"; sleep 2; return; }

        local proto=$(echo "$proxy_uri" | awk -F'://' '{print $1}' | tr '[:upper:]' '[:lower:]')
        local rest=$(echo "$proxy_uri" | awk -F'://' '{print $2}')
        
        if [[ -z "$rest" || -z "$proto" ]]; then
            red "  [错误] 链接格式不正确！请包含协议头 (如 socks5://)。"; sleep 2; return
        fi

        local out_user="" out_pass="" out_host="" out_port=""
        if [[ "$rest" == *"@"* ]]; then
            local cred=$(echo "$rest" | awk -F'@' '{print $1}')
            local hostport=$(echo "$rest" | awk -F'@' '{print $2}')
            out_user=$(echo "$cred" | awk -F':' '{print $1}')
            out_pass=$(echo "$cred" | awk -F':' '{print $2}')
            out_host=$(echo "$hostport" | awk -F':' '{print $1}')
            out_port=$(echo "$hostport" | awk -F':' '{print $2}' | tr -d '/')
        else
            out_host=$(echo "$rest" | awk -F':' '{print $1}')
            out_port=$(echo "$rest" | awk -F':' '{print $2}' | tr -d '/')
        fi

        if [[ -z "$out_host" || -z "$out_port" ]]; then
            red "  [错误] 无法解析出服务器 IP/域名 或 端口！"; sleep 2; return
        fi

        local sb_type=""
        local enable_tls="false"

        if [[ "$proto" == "socks5" || "$proto" == "socks" ]]; then
            sb_type="socks"
        elif [[ "$proto" == "http" ]]; then
            sb_type="http"
        elif [[ "$proto" == "https" ]]; then
            sb_type="http"
            enable_tls="true"
        else
            red "  [错误] 不支持的协议: $proto (仅支持 socks5, http, https)"; sleep 2; return
        fi

        green "  [✔] 解析成功: 协议=${proto}, 地址=${out_host}, 端口=${out_port}, 用户=${out_user:-无}"

        if [[ "$sb_type" == "socks" ]]; then
            if [[ -n "$out_user" ]]; then
                jq --arg ip "$out_host" --arg port "$out_port" --arg user "$out_user" --arg pass "$out_pass" \
                'del(.inbounds[0].users[0].flow) | .outbounds = [{ "type": "socks", "tag": "proxy", "server": $ip, "server_port": ($port|tonumber), "version": "5", "username": $user, "password": $pass }, {"type":"direct", "tag":"direct"}]' \
                "$cfg" > "$tmp_cfg"
            else
                jq --arg ip "$out_host" --arg port "$out_port" \
                'del(.inbounds[0].users[0].flow) | .outbounds = [{ "type": "socks", "tag": "proxy", "server": $ip, "server_port": ($port|tonumber), "version": "5" }, {"type":"direct", "tag":"direct"}]' \
                "$cfg" > "$tmp_cfg"
            fi
        elif [[ "$sb_type" == "http" ]]; then
            if [[ -n "$out_user" ]]; then
                jq --arg ip "$out_host" --arg port "$out_port" --arg user "$out_user" --arg pass "$out_pass" \
                'del(.inbounds[0].users[0].flow) | .outbounds = [{ "type": "http", "tag": "proxy", "server": $ip, "server_port": ($port|tonumber), "username": $user, "password": $pass }, {"type":"direct", "tag":"direct"}]' \
                "$cfg" > "$tmp_cfg"
            else
                jq --arg ip "$out_host" --arg port "$out_port" \
                'del(.inbounds[0].users[0].flow) | .outbounds = [{ "type": "http", "tag": "proxy", "server": $ip, "server_port": ($port|tonumber) }, {"type":"direct", "tag":"direct"}]' \
                "$cfg" > "$tmp_cfg"
            fi
        fi

        if [[ "$enable_tls" == "true" ]]; then
            jq '.outbounds[0] += {"tls": {"enabled": true}}' "$tmp_cfg" > "${tmp_cfg}.tls"
            mv -f "${tmp_cfg}.tls" "$tmp_cfg"
        fi

        echo ""; print_line
        echo -e "  是否开启【流媒体与 AI 智能分流】？"
        echo -en " ${LIGHT_YELLOW} ▶ 开启分流？(y/n) [回车默认 n (全局走代理)]: ${PLAIN}"; read enable_route
        
        if [[ "$enable_route" == "y" || "$enable_route" == "Y" ]]; then
            local route_json='{
                "rules": [
                    { "domain_suffix": [".netflix.com", ".nflxvideo.net", ".nflximg.net", ".openai.com", ".chatgpt.com", ".disneyplus.com", ".dssott.com", ".ipify.org"], "domain_keyword": ["netflix", "openai", "disney"], "outbound": "proxy" }
                ],
                "final": "direct"
            }'
            jq --argjson route "$route_json" '.route = $route' "$tmp_cfg" > "${tmp_cfg}.2"
            mv -f "${tmp_cfg}.2" "$tmp_cfg"
            green "  [✔] 已附加智能分流规则！"
        else
            jq '.route = {"final": "proxy"}' "$tmp_cfg" > "${tmp_cfg}.2"
            mv -f "${tmp_cfg}.2" "$tmp_cfg"
            yellow "  [!] 已设置为【全局强制路由】至住宅 IP。"
        fi

        if [ -s "$tmp_cfg" ] && jq . "$tmp_cfg" >/dev/null 2>&1; then
            mv -f "$tmp_cfg" "$cfg"
            if [[ $SYSTEM == "Alpine" ]]; then rc-service sing-box restart >/dev/null 2>&1; else systemctl restart sing-box >/dev/null 2>&1; fi
            generate_client_configs
            echo ""; print_line
            green "  🎉 代理落地节点配置完成！"
            purple "  💡 重要提示：请务必在您的代理客户端 (v2rayN/Clash 等) 中【更新一次订阅】！"
            sleep 4
        else
            red "  [错误] 配置文件最终写入失败！"
            rm -f "$tmp_cfg"; sleep 2
        fi
    else
        red "  无效的选择！操作取消。"; sleep 2; return
    fi
}

enable_bbr() {
    echo ""; print_line
    if grep -q "bbr" /etc/sysctl.d/99-bbr.conf 2>/dev/null || grep -q "bbr" /etc/sysctl.conf 2>/dev/null; then
        green "  系统已开启 BBR，无需重复配置！"; sleep 2; return
    fi
    mkdir -p /etc/sysctl.d
    cat << EOF >> /etc/sysctl.d/99-bbr.conf
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
    sysctl --system >/dev/null 2>&1
    green "  BBR 拥塞控制与 TCP 底层调优开启成功！"; sleep 2
}

check_keys() {
    clear; echo ""; print_line; green "                 核心安全参数与凭证状态              "; print_line; echo ""
    local cfg="/usr/local/etc/sing-box/config.json"
    if [[ ! -f $cfg ]]; then red "  未检测到凭证数据，请先安装服务！"; sleep 2; return; fi
    
    local is_reality=$(jq -r '.inbounds[0].tls.reality.enabled // false' $cfg)
    yellow "  ▶ UUID 识别码 : $(jq -r '.inbounds[0].users[0].uuid' $cfg)"
    yellow "  ▶ 目标域名(SNI): $(jq -r '.inbounds[0].tls.server_name' $cfg)"
    
    if [[ "$is_reality" == "true" ]]; then
        yellow "  ▶ 节点短 ID(Sid): $(jq -r '.inbounds[0].tls.reality.short_id[0]' $cfg)"
        purple "  ▶ Reality 私钥: 已安全存储于 config.json 中"
    else
        yellow "  ▶ 证书验证模式: 本地证书验证 (acme.sh 接管)"
    fi
    echo ""; green "  状态: [✔] 核心参数读取正常。"; echo ""
    echo -en " ${LIGHT_YELLOW} ▶ 按回车键返回主菜单... ${PLAIN}"; read temp
}

# =================================================================
#  7. 交互主菜单
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
        2 ) clean_env; red "  已彻底安全卸载并清理环境！"; sleep 1; exit 0 ;;
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
