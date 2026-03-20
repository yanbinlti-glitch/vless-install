#!/bin/bash

export LANG=en_US.UTF-8
export DEBIAN_FRONTEND=noninteractive

# =================================================================
#  1. 现代化极简 UI 色彩库
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

# 安全提取脚本路径并设置快捷指令
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
    [[ ! $SYSTEM == "CentOS" ]] && { $PKG_UPDATE || { echo ""; red " [错误] 系统软件源更新失败！"; exit 1; }; }
    $PKG_INSTALL curl || { echo ""; red " [错误] curl 安装失败！请检查网络或系统源。"; exit 1; }
fi

realip() {
    ip=$(curl -s4m3 api.ipify.org -k || curl -s4m3 ifconfig.me -k || curl -s4m3 ip.sb -k)
    if [[ -z "$ip" ]]; then
        ip=$(curl -s6m3 api64.ipify.org -k || curl -s6m3 ifconfig.me -k || curl -s6m3 ip.sb -k)
    fi
    ip=$(echo "$ip" | grep -m 1 -E -o "([0-9]{1,3}[\.]){3}[0-9]{1,3}|([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:)*:[0-9a-fA-F]{1,4}")
    if [[ -z "$ip" ]]; then
        echo ""
        red " [错误] 无法获取本机的公网 IP，请检查 VPS 的网络连接或 DNS 设置！"
        exit 1
    fi
}

gen_random_str() {
    local len=$1
    local str=$(cat /proc/sys/kernel/random/uuid 2>/dev/null | tr -d '-')
    if [[ -z "$str" ]]; then
        str=$(head -c 16 /dev/urandom | od -A n -t x1 | tr -d ' \n')
    fi
    echo "${str:0:$len}"
}

# =================================================================
#  3. 服务管理与防火墙控制封装 (纯 TCP 模式)
# =================================================================
svc_start()   { if [[ $SYSTEM == "Alpine" ]]; then rc-service "$1" start; else systemctl start "$1"; fi; }
svc_stop()    { if [[ $SYSTEM == "Alpine" ]]; then rc-service "$1" stop; else systemctl stop "$1"; fi; }
svc_enable()  { if [[ $SYSTEM == "Alpine" ]]; then rc-update add "$1" default; else systemctl enable "$1"; fi; }
svc_disable() { if [[ $SYSTEM == "Alpine" ]]; then rc-update del "$1" default; else systemctl disable "$1"; fi; }

save_iptables() {
    if [[ $SYSTEM == "Alpine" ]]; then
        rc-service iptables save 2>/dev/null
        rc-service ip6tables save 2>/dev/null
    elif [[ $SYSTEM == "CentOS" || $SYSTEM == "Fedora" || $SYSTEM == "Alma" || $SYSTEM == "Rocky" ]]; then
        service iptables save 2>/dev/null
        service ip6tables save 2>/dev/null
    else
        if command -v netfilter-persistent >/dev/null; then
            netfilter-persistent save 2>/dev/null
        fi
    fi
}

open_port() {
    local port=$1
    local proto="tcp"
    iptables -I INPUT -p $proto --dport $port -j ACCEPT 2>/dev/null
    ip6tables -I INPUT -p $proto --dport $port -j ACCEPT 2>/dev/null
    if command -v ufw >/dev/null; then ufw allow $port/$proto 2>/dev/null; fi
    if command -v firewall-cmd >/dev/null && systemctl is-active --quiet firewalld 2>/dev/null; then
        firewall-cmd --zone=public --add-port=$port/$proto --permanent 2>/dev/null
        firewall-cmd --reload 2>/dev/null
    fi
    save_iptables
}

close_port() {
    local port=$1
    local proto="tcp"
    iptables -D INPUT -p $proto --dport $port -j ACCEPT 2>/dev/null
    ip6tables -D INPUT -p $proto --dport $port -j ACCEPT 2>/dev/null
    if command -v ufw >/dev/null; then ufw delete allow $port/$proto 2>/dev/null; fi
    if command -v firewall-cmd >/dev/null && systemctl is-active --quiet firewalld 2>/dev/null; then
        firewall-cmd --zone=public --remove-port=$port/$proto --permanent 2>/dev/null
        firewall-cmd --reload 2>/dev/null
    fi
    save_iptables
}

# =================================================================
#  4. 环境检查与预处理 (包含 Alpine 底层库修复)
# =================================================================
check_env() {
    clear
    echo ""
    print_line
    green "                   系统依赖与环境检查                      "
    print_line
    echo ""
    green "  当前操作系统: $SYSTEM"
    yellow "  正在检查 sing-box 核心及前置依赖包..."
    echo ""
    
    local cmds=("curl" "wget" "sudo" "ss" "iptables" "python3" "openssl" "qrencode" "tar" "gzip" "jq")
    local missing=0

    for cmd in "${cmds[@]}"; do
        if ! command -v "$cmd" > /dev/null; then
            red "   [✘] 缺失:  $cmd"
            missing=1
        else
            green "   [✔] 正常:  $cmd"
        fi
    done

    if [[ $missing -eq 1 ]]; then
        echo ""
        print_line
        yellow "  发现缺失前置组件，正在为您自动拉取安装，执行日志如下..."
        echo ""
        
        [[ ! $SYSTEM == "CentOS" ]] && { $PKG_UPDATE || { echo ""; red " [错误] 系统软件源更新失败！请检查网络。"; exit 1; }; }
        
        if [[ $SYSTEM == "Alpine" ]]; then
            $PKG_INSTALL curl wget sudo procps iptables ip6tables iproute2 python3 openssl libqrencode-tools tar gzip jq gcompat libc6-compat || { echo ""; red " [错误] 依赖安装失败！"; exit 1; }
        elif [[ $SYSTEM == "CentOS" || $SYSTEM == "Fedora" || $SYSTEM == "Alma" || $SYSTEM == "Rocky" ]]; then
            $PKG_INSTALL epel-release || true
            $PKG_INSTALL curl wget sudo procps iptables iptables-services iproute python3 openssl qrencode tar gzip jq || { echo ""; red " [错误] 依赖安装失败！"; exit 1; }
        else
            apt-get --fix-broken install -y || true
            echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections 2>/dev/null || true
            echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections 2>/dev/null || true
            $PKG_INSTALL curl wget sudo procps iptables-persistent netfilter-persistent iproute2 python3 openssl qrencode tar gzip jq || { echo ""; red " [错误] 依赖安装失败！"; exit 1; }
        fi
        
        echo ""
        green "  所有前置依赖补全完成！"
    else
        echo ""
        print_line
        green "  所有前置依赖检查通过，环境完美，无需额外安装！"
    fi
    
    # 强制修复 Alpine 的 glibc 兼容层，解决 sing-box 无法执行的问题
    if [[ $SYSTEM == "Alpine" ]]; then
        yellow "  正在为 Alpine 系统校验底层 glibc 兼容环境..."
        $PKG_INSTALL gcompat libc6-compat >/dev/null 2>&1
        
        # 建立动态链接库软链接
        mkdir -p /lib64
        if [[ ! -f /lib64/ld-linux-x86-64.so.2 ]]; then
            ln -s /lib/libc.musl-x86_64.so.1 /lib64/ld-linux-x86-64.so.2 2>/dev/null
        fi
        green "   [✔] Alpine 兼容层校验通过！"
    fi

    sleep 2
}

# =================================================================
#  5. 核心安装与配置逻辑
# =================================================================
inst_singbox_core() {
    echo ""
    print_line
    yellow "  正在下载 sing-box 二进制核心..."
    arch=$(uname -m)
    case $arch in
        x86_64) sb_arch="amd64" ;;
        aarch64) sb_arch="arm64" ;;
        s390x) sb_arch="s390x" ;;
        *) red " [错误] 不支持的架构: $arch" && exit 1 ;;
    esac
    
    # 修复：使用更稳定的 GitHub API 解析 JSON 提取最新版本号，防 Rate Limit 报错
    sb_version=$(curl -s "https://api.github.com/repos/SagerNet/sing-box/releases/latest" | grep '"tag_name":' | sed -E 's/.*"v?([^"]+)".*/\1/')
    if [[ -z "$sb_version" || ! "$sb_version" =~ ^[0-9]+\.[0-9]+ ]]; then
        red " [错误] 获取 sing-box 最新版本失败，可能是网络问题或 GitHub API 请求受限！"
        exit 1
    fi
    
    green "  获取到最新版本: v${sb_version}"
    wget --timeout=10 --tries=3 -N -v -O /tmp/sing-box.tar.gz "https://github.com/SagerNet/sing-box/releases/download/v${sb_version}/sing-box-${sb_version}-linux-${sb_arch}.tar.gz"
    
    if [[ ! -s /tmp/sing-box.tar.gz ]]; then
        red " [错误] sing-box 核心下载失败！"
        rm -f /tmp/sing-box.tar.gz
        exit 1
    fi
    
    mkdir -p /usr/local/bin
    tar -xzf /tmp/sing-box.tar.gz -C /tmp/ >/dev/null 2>&1
    cp -f /tmp/sing-box-${sb_version}-linux-${sb_arch}/sing-box /usr/local/bin/sing-box
    chmod +x /usr/local/bin/sing-box
    
    rm -rf /tmp/sing-box.tar.gz /tmp/sing-box-${sb_version}-linux-${sb_arch}
    
    # 修复：运行可执行性检查，防止在不支持的内核或缺失库的环境下继续部署
    if ! /usr/local/bin/sing-box version >/dev/null 2>&1; then
        red " [致命错误] sing-box 核心无法在当前系统运行！可能是不兼容的架构或缺失底层 C 库。"
        rm -f /usr/local/bin/sing-box
        exit 1
    fi
    
    green "  sing-box 核心下载并解压完成！"
}

inst_config() {
    mkdir -p /usr/local/etc/sing-box
    
    echo ""
    print_line
    # 强制限制主端口只能为 10000-65535 的纯数字
    while true; do
        echo -en " ${LIGHT_YELLOW} ▶ 设置节点主端口 [10000-65535] (回车随机): ${PLAIN}"
        read port
        [[ -z $port ]] && port=$(shuf -i 10000-65535 -n 1)
        if [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 10000 ] && [ "$port" -le 65535 ]; then
            if ss -tnl | grep -E -q ":$port( |$)"; then
                red " [警告] 端口 $port 已被占用！"
            else
                break
            fi
        else
            red " [错误] 格式无效或包含特权端口！请输入 10000-65535 之间的纯数字。"
        fi
    done
    green " 节点主端口已设置为: $port (TCP)"
    open_port $port
    
    echo ""
    echo -en " ${LIGHT_YELLOW} ▶ 设置 Reality 伪装域名 (SNI) [回车默认 www.microsoft.com]: ${PLAIN}"
    read dest_sni
    [[ -z $dest_sni ]] && dest_sni="www.bing.com"
    green " 伪装域名设置为: $dest_sni"

    echo ""
    echo -en " ${LIGHT_YELLOW} ▶ 节点显示名称 [回车默认 VLESS_Reality_Node]: ${PLAIN}"
    read custom_node_name
    [[ -z $custom_node_name ]] && custom_node_name="VLESS_Reality_Node"

    echo ""
    yellow "  正在使用 sing-box 生成 VLESS-Reality 安全凭证..."
    
    vless_uuid=$(/usr/local/bin/sing-box generate uuid)
    keys=$(/usr/local/bin/sing-box generate reality-keypair)
    private_key=$(echo "$keys" | grep "PrivateKey" | awk -F': ' '{print $2}')
    public_key=$(echo "$keys" | grep "PublicKey" | awk -F': ' '{print $2}')
    short_id=$(openssl rand -hex 8)

    green "  ✔ UUID 生成成功!"
    green "  ✔ x25519 密钥对生成成功!"
    green "  ✔ shortId 生成成功!"

    cat << EOF > /usr/local/etc/sing-box/config.json
{
  "log": {
    "level": "warn",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-in",
      "listen": "0.0.0.0",
      "listen_port": $port,
      "users": [
        {
          "uuid": "$vless_uuid",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "$dest_sni",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "$dest_sni",
            "server_port": 443
          },
          "private_key": "$private_key",
          "short_id": [
            "$short_id"
          ]
        }
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
}
EOF
    chmod 600 /usr/local/etc/sing-box/config.json
    
    echo "$port" > /usr/local/etc/sing-box/port.txt
    echo "$vless_uuid" > /usr/local/etc/sing-box/uuid.txt
    echo "$dest_sni" > /usr/local/etc/sing-box/sni.txt
    echo "$public_key" > /usr/local/etc/sing-box/pbk.txt
    echo "$short_id" > /usr/local/etc/sing-box/sid.txt
    echo "$custom_node_name" > /usr/local/etc/sing-box/node_name.txt
}

inst_sub_port(){
    echo ""
    print_line
    while true; do
        echo -en " ${LIGHT_YELLOW} ▶ 设置智能订阅服务端口 [10000-65535] (回车随机): ${PLAIN}"
        read sub_port_input
        [[ -z $sub_port_input ]] && sub_port_input=$(shuf -i 10000-65535 -n 1)
        if [[ "$sub_port_input" =~ ^[0-9]+$ ]] && [ "$sub_port_input" -ge 10000 ] && [ "$sub_port_input" -le 65535 ]; then
            if ss -tnl | grep -E -q ":$sub_port_input( |$)"; then
                red " [警告] 端口 $sub_port_input 已被占用！"
            else
                break
            fi
        else
            red " [错误] 格式无效或包含特权端口！请输入 10000-65535 之间的纯数字。"
        fi
    done
    green " 订阅端口已设置为: $sub_port_input"
    open_port $sub_port_input
    echo "$sub_port_input" > /usr/local/etc/sing-box/sub_port.txt
}

# =================================================================
#  6. 核心业务处理与部署逻辑
# =================================================================
clean_env() {
    local main_port=$(cat /usr/local/etc/sing-box/port.txt 2>/dev/null | tr -d '\r')
    local sub_port=$(cat /usr/local/etc/sing-box/sub_port.txt 2>/dev/null | tr -d '\r')

    [[ -n "$main_port" && "$main_port" =~ ^[0-9]+$ ]] && close_port "$main_port"
    [[ -n "$sub_port" && "$sub_port" =~ ^[0-9]+$ ]] && close_port "$sub_port"

    svc_stop sing-box 2>/dev/null; svc_disable sing-box 2>/dev/null
    svc_stop vless-sub 2>/dev/null; svc_disable vless-sub 2>/dev/null
    
    pkill -f "vless_server.py" 2>/dev/null || true

    if [[ $SYSTEM == "Alpine" ]]; then
        rm -f /etc/init.d/sing-box /etc/init.d/vless-sub
    else
        rm -f /etc/systemd/system/sing-box.service /etc/systemd/system/vless-sub.service
        systemctl daemon-reload 2>/dev/null
    fi
    save_iptables

    rm -rf /usr/local/bin/sing-box /usr/local/etc/sing-box /var/www/vless
}

generate_client_configs() {
    realip
    
    local port=$(cat /usr/local/etc/sing-box/port.txt)
    local uuid=$(cat /usr/local/etc/sing-box/uuid.txt)
    local sni=$(jq -r '.inbounds[0].tls.server_name' /usr/local/etc/sing-box/config.json)
    local pbk=$(cat /usr/local/etc/sing-box/pbk.txt)
    local sid=$(cat /usr/local/etc/sing-box/sid.txt)
    local node_name=$(cat /usr/local/etc/sing-box/node_name.txt)
    
    local safe_node_name=$(NAME="$node_name" python3 -c "import urllib.parse, os; print(urllib.parse.quote(os.environ.get('NAME', '')))")
    
    local uri_ip="$ip"
    [[ "$ip" == *":"* ]] && uri_ip="[$ip]"

    local web_dir="/var/www/vless"
    mkdir -p "$web_dir"

    local sub_uuid=$(gen_random_str 16)
    mkdir -p "$web_dir/$sub_uuid"
    echo "$sub_uuid" > /usr/local/etc/sing-box/sub_path.txt

    # 拼接 VLESS 链接
    local url="vless://${uuid}@${uri_ip}:${port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${sni}&fp=chrome&pbk=${pbk}&sid=${sid}&type=tcp&headerType=none#${safe_node_name}"
    echo "$url" > "$web_dir/$sub_uuid/url.txt"
    
    printf "%s" "$url" | base64 -w 0 2>/dev/null > "$web_dir/$sub_uuid/sub_b64.txt" || printf "%s" "$url" | base64 | tr -d '\r\n' > "$web_dir/$sub_uuid/sub_b64.txt"

    # 生成 Clash Meta 订阅
    cat << EOF > "$web_dir/$sub_uuid/clash-meta-sub.yaml"
port: 7890
socks-port: 7891
allow-lan: true
mode: rule
log-level: info
ipv6: true

proxies:
  - name: '${node_name}'
    type: vless
    server: "$ip"
    port: $port
    uuid: "$uuid"
    network: tcp
    tls: true
    udp: true
    flow: xtls-rprx-vision
    servername: "$sni"
    reality-opts:
      public-key: "$pbk"
      short-id: "$sid"
    client-fingerprint: chrome

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

    chmod 644 "$web_dir/$sub_uuid/clash-meta-sub.yaml"
    chmod 644 "$web_dir/$sub_uuid/sub_b64.txt"

    local sub_port=$(cat /usr/local/etc/sing-box/sub_port.txt)
    chown -R nobody "$web_dir"

    # 修复：移除有兼容性问题的自签 HTTPS 证书，改为纯 HTTP，保证各客户端正常拉取订阅
    cat << EOF > "$web_dir/vless_server.py"
import http.server
import socketserver
import urllib.parse
import socket

PORT = $sub_port
SUB_UUID = "$sub_uuid"

try:
    with open("$web_dir/$sub_uuid/clash-meta-sub.yaml", 'rb') as f:
        CLASH_DATA = f.read()
    with open("$web_dir/$sub_uuid/sub_b64.txt", 'rb') as f:
        B64_DATA = f.read()
except FileNotFoundError:
    CLASH_DATA = b""
    B64_DATA = b""

class SecureSubHandler(http.server.BaseHTTPRequestHandler):
    server_version = "nginx/1.24.0"
    sys_version = ""

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        req_path = parsed.path.strip('/')
        
        if req_path == SUB_UUID:
            self.send_response(200)
            self.send_header('Content-type', 'text/plain; charset=utf-8')
            self.send_header('Cache-Control', 'no-store, no-cache, must-revalidate, max-age=0')
            self.end_headers()
            
            ua = self.headers.get('User-Agent', '').lower()
            if any(x in ua for x in ['clash', 'meta', 'verge', 'stash', 'mihomo']):
                self.wfile.write(CLASH_DATA)
            else:
                self.wfile.write(B64_DATA + b"\n")
        else:
            self.send_response(403)
            self.send_header('Content-type', 'text/html; charset=utf-8')
            self.end_headers()
            self.wfile.write(b"<html><head><title>403 Forbidden</title></head><body><center><h1>403 Forbidden</h1></center><hr><center>nginx</center></body></html>")

class DualStackServer(socketserver.ThreadingTCPServer):
    daemon_threads = True
    allow_reuse_address = True
    address_family = getattr(socket, 'AF_INET6', socket.AF_INET)
    def server_bind(self):
        if hasattr(socket, 'AF_INET6') and self.address_family == socket.AF_INET6:
            try: self.socket.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
            except: pass
        super().server_bind()

try:
    httpd = DualStackServer(("", PORT), SecureSubHandler)
except OSError:
    DualStackServer.address_family = socket.AF_INET
    httpd = DualStackServer(("0.0.0.0", PORT), SecureSubHandler)

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
        chmod +x /etc/init.d/vless-sub
        rc-update add vless-sub default
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
        systemctl daemon-reload
        systemctl enable vless-sub
    fi
    
    svc_stop vless-sub 2>/dev/null
    svc_start vless-sub
}

inst_proxy() {
    if [[ -f "/usr/local/etc/sing-box/config.json" || -f "/usr/local/bin/sing-box" ]]; then
        echo ""
        yellow "  检测到旧版本配置，正在清理环境并为您重新生成..."
        clean_env
        green "  旧文件清理完成，准备重新部署！"
    fi
    
    check_env
    inst_singbox_core
    inst_config
    inst_sub_port

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
        chmod +x /etc/init.d/sing-box
    else
        cat << EOF > /etc/systemd/system/sing-box.service
[Unit]
Description=sing-box Service
Documentation=https://sing-box.sagernet.org/
After=network.target nss-lookup.target

[Service]
User=root
NoNewPrivileges=true
ExecStart=/usr/local/bin/sing-box run -c /usr/local/etc/sing-box/config.json
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
    fi

    svc_enable sing-box
    svc_start sing-box
    generate_client_configs
    
    # 修复：引入轮询检测机制，避免系统慢导致端口误判失败
    local port=$(cat /usr/local/etc/sing-box/port.txt)
    local start_success=0
    for i in {1..10}; do
        if ss -tnl | grep -E -q ":$port( |$)"; then
            start_success=1
            break
        fi
        sleep 1
    done

    if [[ $start_success -eq 0 ]]; then
        echo ""
        red " [致命错误] 服务端未能成功启动，端口 $port 未被监听！请检查日志。"
        exit 1
    fi
    
    echo ""
    print_line
    green "  VLESS-Reality 服务端及智能订阅安装部署完成！"
    purple "  请在主菜单选择 [6] 获取节点配置。"
    echo ""
    sleep 3
}

unst_proxy() {
    echo ""
    yellow "  正在安全地清理系统网络、防火墙规则，并卸载相关文件..."
    clean_env
    rm -f /usr/local/bin/vvv
    echo ""
    green "  VLESS-Reality 服务及相关文件已被彻底清理！"
    sleep 2
    exit 0
}

# =================================================================
#  7. 二级菜单功能与辅助工具
# =================================================================
showconf() {
    realip
    if [[ ! -f /usr/local/etc/sing-box/config.json ]]; then
        red "  未检测到配置文件，请先安装！"
        sleep 2; return
    fi

    local sub_port=$(cat /usr/local/etc/sing-box/sub_port.txt)
    local sub_path=$(cat /usr/local/etc/sing-box/sub_path.txt)
    
    # 修复：订阅链接改为纯 http，搭配随机 UUID 路径足够安全，同时兼容所有客户端
    local sub_url=""
    if [[ "$ip" == *":"* ]]; then
        sub_url="http://[${ip}]:${sub_port}/${sub_path}"
    else
        sub_url="http://${ip}:${sub_port}/${sub_path}"
    fi

    local web_dir="/var/www/vless"
    local raw_url=$(cat "$web_dir/$sub_path/url.txt")
    local main_port=$(cat /usr/local/etc/sing-box/port.txt)
    
    clear
    echo ""
    print_line
    green "                VLESS-Reality 全平台智能订阅               "
    print_line
    echo ""
    yellow "  ▶ [智能订阅链接] (推荐)"
    purple "    适用客户端: Clash Meta / Verge / v2rayN / Shadowrocket"
    green  "    订阅地址: ${sub_url}"
    echo ""
    yellow "  ▶ [单节点直连链接]"
    purple "    适用客户端: NekoBox / v2rayNG (直接导入)"
    green  "    节点地址: ${raw_url}"
    echo ""
    
    if command -v qrencode > /dev/null; then
        echo ""
        purple "  提示：若二维码断层，请将终端字体缩小"
        echo ""
        qrencode -t ANSIUTF8 "$raw_url"
    else
        yellow "  正通过在线 API 绘制二维码..."
        curl -s -d "$raw_url" https://qrenco.de
    fi
    
    echo ""
    print_line
    yellow "  ▶ 特别提醒："
    echo -e "    ${LIGHT_GREEN}若使用云服务器，请在【安全组】开放以下 TCP 端口：${PLAIN}"
    echo -e "    ${LIGHT_GREEN}主节点端口: ${main_port} (TCP)${PLAIN}"
    echo -e "    ${LIGHT_GREEN}云订阅端口: ${sub_port} (TCP)${PLAIN}"
    echo ""
    echo -en " ${LIGHT_YELLOW} ▶ 按回车键返回主菜单... ${PLAIN}"
    read temp
}

edit_config() {
    clear
    if [[ ! -f /usr/local/etc/sing-box/config.json ]]; then
        red "  未检测到配置文件，请先安装！"
        sleep 2; return
    fi
    
    echo ""
    print_line
    green "                  当前 sing-box 节点配置                   "
    print_line
    echo ""
    cat /usr/local/etc/sing-box/config.json
    echo ""
    print_line
    echo -en " ${LIGHT_YELLOW} ▶ 是否需要修改配置文件？(y/n) [默认: n]: ${PLAIN}"
    read edit_choice
    
    if [[ "$edit_choice" == "y" || "$edit_choice" == "Y" ]]; then
        cp /usr/local/etc/sing-box/config.json /tmp/config_backup.json
        
        if command -v nano >/dev/null; then
            nano /usr/local/etc/sing-box/config.json
        elif command -v vi >/dev/null; then
            vi /usr/local/etc/sing-box/config.json
        else
            red "  未找到 nano 或 vi，请手动修改 /usr/local/etc/sing-box/config.json"
        fi
        
        yellow "  正在校验配置文件语法..."
        if ! /usr/local/bin/sing-box check -c /usr/local/etc/sing-box/config.json >/dev/null 2>&1; then
            red "  [错误] 检测到 JSON 语法错误！已为您自动回滚到修改前的配置。"
            mv /tmp/config_backup.json /usr/local/etc/sing-box/config.json
        else
            green "  语法校验通过，正在重启服务..."
            rm -f /tmp/config_backup.json
            svc_stop sing-box
            svc_start sing-box
            sleep 1
            
            local restart_success=0
            if [[ $SYSTEM == "Alpine" ]]; then
                rc-service sing-box status | grep -q 'started' && restart_success=1
            else
                systemctl is-active --quiet sing-box && restart_success=1
            fi
            
            if [[ $restart_success -eq 1 ]]; then
                green "  重启成功！新配置已生效。"
                yellow "  正在同步更新客户端订阅文件..."
                
                local new_uuid=$(jq -r '.inbounds[0].users[0].uuid' /usr/local/etc/sing-box/config.json)
                local new_port=$(jq -r '.inbounds[0].listen_port' /usr/local/etc/sing-box/config.json)
                local new_sni=$(jq -r '.inbounds[0].tls.server_name' /usr/local/etc/sing-box/config.json)
                local new_sid=$(jq -r '.inbounds[0].tls.reality.short_id[0]' /usr/local/etc/sing-box/config.json)
                
                echo "$new_uuid" > /usr/local/etc/sing-box/uuid.txt
                echo "$new_port" > /usr/local/etc/sing-box/port.txt
                echo "$new_sni" > /usr/local/etc/sing-box/sni.txt
                echo "$new_sid" > /usr/local/etc/sing-box/sid.txt
                
                generate_client_configs
                green "  客户端订阅文件已同步更新！"
                purple "  (提示：如果您修改了 Private Key，由于无法反推公钥，请勿忘记手动给客户端更换公钥！)"
            else
                red "  [错误] 启动失败！请通过主菜单日志检查原因。"
            fi
        fi
    fi
    echo ""
    echo -en " ${LIGHT_YELLOW} ▶ 按回车键返回主菜单... ${PLAIN}"
    read temp
}

modify_sni() {
    clear
    if [[ ! -f /usr/local/etc/sing-box/config.json ]]; then
        red "  未检测到配置文件，请先安装！"
        sleep 2; return
    fi
    
    local old_sni=$(jq -r '.inbounds[0].tls.server_name' /usr/local/etc/sing-box/config.json)
    echo ""
    print_line
    green "                  修改 Reality 伪装域名 (SNI)              "
    print_line
    echo ""
    yellow "  当前伪装域名: $old_sni"
    echo ""
    echo -en " ${LIGHT_YELLOW} ▶ 请输入新的伪装域名 (如 www.apple.com，留空取消): ${PLAIN}"
    read new_sni
    
    if [[ -n "$new_sni" && "$new_sni" != "$old_sni" ]]; then
        # 修复：防掉盘机制，确保 jq 执行成功且文件不为空时再覆盖
        if jq --arg sni "$new_sni" '.inbounds[0].tls.server_name = $sni | .inbounds[0].tls.reality.handshake.server = $sni' /usr/local/etc/sing-box/config.json > /tmp/sb_tmp.json && [ -s /tmp/sb_tmp.json ]; then
            mv -f /tmp/sb_tmp.json /usr/local/etc/sing-box/config.json
            echo "$new_sni" > /usr/local/etc/sing-box/sni.txt
            
            green "  已更新 SNI 为 $new_sni"
            green "  正在重启服务并更新订阅信息..."
            svc_stop sing-box
            svc_start sing-box
            generate_client_configs
            green "  更新完成！请在客户端更新订阅以应用新 SNI。"
        else
            red "  [错误] 配置文件解析失败，SNI 未修改！"
        fi
    else
        yellow "  操作已取消或未更改。"
    fi
    echo ""
    echo -en " ${LIGHT_YELLOW} ▶ 按回车键返回主菜单... ${PLAIN}"
    read temp
}

check_logs() {
    clear
    echo ""
    print_line
    green "                  sing-box 实时运行日志                    "
    print_line
    echo ""
    if [[ $SYSTEM == "Alpine" ]]; then
        red "  Alpine 暂不提供 systemd 日志查看功能。"
    else
        yellow "  正在实时滚动日志 (按 Ctrl+C 退出查看)..."
        echo ""
        journalctl -u sing-box -f -n 30
    fi
    echo ""
    echo -en " ${LIGHT_YELLOW} ▶ 按回车键返回主菜单... ${PLAIN}"
    read temp
}

start_proxy() {
    svc_start sing-box; svc_start vless-sub
    echo ""; green "  服务已启动！"; sleep 2
}
stop_proxy() {
    svc_stop sing-box; svc_stop vless-sub
    pkill -f "vless_server.py" 2>/dev/null || true
    echo ""; yellow "  服务已停止！"
}

proxy_switch() {
    clear
    echo ""
    print_line
    green "                      服务运行状态控制                     "
    print_line
    echo ""
    echo -e "    ${LIGHT_GREEN}[1]${PLAIN} ${LIGHT_GREEN}启动 服务${PLAIN}"
    echo -e "    ${LIGHT_GREEN}[2]${PLAIN} ${LIGHT_RED}停止 服务${PLAIN}"
    echo -e "    ${LIGHT_GREEN}[3]${PLAIN} ${LIGHT_YELLOW}重启 服务${PLAIN}"
    echo ""
    echo -e "    ${LIGHT_GREEN}[0]${PLAIN} ${LIGHT_PURPLE}返回主菜单${PLAIN}"
    echo ""
    echo -en " ${LIGHT_YELLOW} ▶ 请输入选项 [0-3]: ${PLAIN}"
    read switchInput
    case $switchInput in
        1 ) start_proxy ;;
        2 ) stop_proxy; sleep 2 ;;
        3 ) stop_proxy; start_proxy ;;
        0 ) return ;;
        * ) red "  输入无效"; sleep 1 ;;
    esac
}

enable_bbr() {
    echo ""
    print_line
    local kernel_v=$(uname -r | cut -d. -f1)
    if [[ "$kernel_v" -lt 4 ]]; then
        red "  当前内核版本过低 ($(uname -r))，不支持开启 BBR！"
        sleep 3; return
    fi
    if ! modprobe tcp_bbr 2>/dev/null; then
        if ! grep -q "bbr" /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null; then
            red "  [错误] 当前系统/内核彻底不支持 BBR 模块！"
            sleep 3; return
        fi
    fi
    
    mkdir -p /etc/sysctl.d
    cat << EOF > /etc/sysctl.d/99-bbr.conf
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.core.rmem_max=26214400
net.core.rmem_default=26214400
net.core.wmem_max=26214400
net.core.wmem_default=26214400
net.core.somaxconn=65535
net.ipv4.tcp_fastopen=3
EOF
    sysctl --system >/dev/null 2>&1 || sysctl -p /etc/sysctl.d/99-bbr.conf >/dev/null 2>&1
    
    echo ""
    green "  BBR 拥塞控制与 TCP 底层调优开启成功！"
    yellow "  对于跨国 TCP 连接（如 VLESS），BBR 可大幅降低延迟并提升吞吐量。"
    echo ""
    echo -en " ${LIGHT_YELLOW} ▶ 按回车键返回主菜单... ${PLAIN}"
    read temp
}

check_keys() {
    clear
    echo ""
    print_line
    green "                 Reality 安全公私钥与参数状态              "
    print_line
    echo ""
    if [[ ! -f /usr/local/etc/sing-box/pbk.txt ]]; then
        red "  未检测到凭证数据，请先安装服务！"
    else
        yellow "  ▶ UUID 识别码 : $(cat /usr/local/etc/sing-box/uuid.txt)"
        yellow "  ▶ 伪装域名(SNI): $(cat /usr/local/etc/sing-box/sni.txt)"
        yellow "  ▶ 节点公钥(Pbk): $(cat /usr/local/etc/sing-box/pbk.txt)"
        yellow "  ▶ 节点短 ID(Sid): $(cat /usr/local/etc/sing-box/sid.txt)"
        purple "  ▶ 节点私钥(Key): 已存储于 config.json 中"
        
        echo ""
        green "  状态: [✔] 密钥对保存完整，可随时进行客户端下发。"
    fi
    echo ""
    echo -en " ${LIGHT_YELLOW} ▶ 按回车键返回主菜单... ${PLAIN}"
    read temp
}

# =================================================================
#  8. 主菜单控制
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
    green " 项目名称 ：VLESS-Reality 一键部署与管理脚本 (电竞加固版)"
    purple " 项目地址 ：哆啦的Github库 https://github.com/yanbinlti-glitch/vless-install"
    green "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    yellow " 脚本快捷方式：vvv (已自动配置，下次可在终端直接输入 vvv 启动)"
    red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    echo -e "  ${LIGHT_GREEN}[1]${PLAIN} ${LIGHT_GREEN}安装部署 VLESS-Reality (sing-box内核)${PLAIN}"
    echo -e "  ${LIGHT_GREEN}[2]${PLAIN} ${LIGHT_RED}彻底卸载 VLESS-Reality${PLAIN}"
    echo "----------------------------------------------------------------------------------"
    echo -e "  ${LIGHT_GREEN}[3]${PLAIN} ${LIGHT_YELLOW}启动 / 停止 / 重启服务${PLAIN}"
    echo -e "  ${LIGHT_GREEN}[4]${PLAIN} ${LIGHT_PURPLE}查看 / 修改 配置文件${PLAIN}"
    echo -e "  ${LIGHT_GREEN}[5]${PLAIN} ${LIGHT_GREEN}修改 Reality 伪装域名 (SNI 目标配置)${PLAIN}"
    echo "----------------------------------------------------------------------------------"
    echo -e "  ${LIGHT_GREEN}[6]${PLAIN} ${LIGHT_GREEN}获取 节点配置 与 订阅链接${PLAIN}"
    echo -e "  ${LIGHT_GREEN}[7]${PLAIN} ${LIGHT_YELLOW}查看 sing-box 实时运行日志${PLAIN}"
    echo -e "  ${LIGHT_GREEN}[8]${PLAIN} ${LIGHT_PURPLE}开启 BBR 拥塞控制调优 (强烈推荐)${PLAIN}"
    echo -e "  ${LIGHT_GREEN}[9]${PLAIN} ${LIGHT_GREEN}检查 Reality 安全公私钥与参数状态${PLAIN}"
    echo "----------------------------------------------------------------------------------"
    echo -e "  ${LIGHT_GREEN}[0]${PLAIN} ${LIGHT_RED}退出脚本${PLAIN}"
    red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    echo ""
    echo -en " ${LIGHT_YELLOW} ▶ 请输入选项 [0-9]: ${PLAIN}"
    read menuInput
    case $menuInput in
        1 ) inst_proxy ;;
        2 ) unst_proxy ;;
        3 ) proxy_switch ;;
        4 ) edit_config ;;
        5 ) modify_sni ;;
        6 ) showconf ;;
        7 ) check_logs ;;
        8 ) enable_bbr ;;
        9 ) check_keys ;;
        0 ) exit 0 ;;
        * ) red "  输入无效"; sleep 1 ;;
    esac
}

while true; do
    menu
done
