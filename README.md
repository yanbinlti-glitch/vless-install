# 🚀 VLESS-Reality 一键部署与管理脚本 (电竞加固版)

![Bash](https://img.shields.io/badge/Language-Bash-4EAA25?style=flat-square&logo=gnu-bash)
![Core](https://img.shields.io/badge/Core-sing--box-blue?style=flat-square)
![Protocol](https://img.shields.io/badge/Protocol-VLESS--Reality-orange?style=flat-square)
![License](https://img.shields.io/badge/License-MIT-yellow?style=flat-square)

基于最现代化的 **sing-box** 核心打造，专为**游戏加速**与**高强度网络审查环境**设计的纯 TCP 代理一键部署脚本。

如果你的网络环境（如长城宽带、校园网、公司内网）对 UDP 协议进行了严厉的限速（QoS）或阻断，导致 Hysteria 2 / TUIC 等协议断流卡顿，那么本脚本提供的 **VLESS-TCP-XTLS-Reality** 方案将是你极其稳定、免维护的终极选择。

---

## ✨ 核心亮点

- 🛡️ **极致防封锁 (Reality)**：无需购买域名，无需申请 SSL 证书！直接“偷取”微软、苹果等大厂域名的 TLS 特征，将流量完美伪装成正常的网页浏览，抗主动探测能力拉满。
- ⚡ **现代化核心 (sing-box)**：抛弃老旧架构，采用目前最轻量、内存控制极佳的通用代理平台 `sing-box` 作为底层支撑。
- 🎮 **电竞级 TCP 优化**：内置 BBR 拥塞控制与 TCP 底层缓冲区调优功能，有效降低跨国 TCP 握手延迟与丢包率。
- 🔗 **内建智能订阅分发**：无需额外安装 Nginx！自带超轻量级 Python 多线程 Web 服务（内置自签 TLS 加密），一键生成并下发 `Clash Meta` / `Verge` 格式的订阅链接。
- 🛠️ **极简运维体验**：精美的彩色 UI 交互，支持快捷键 `vvv` 一键唤出菜单；支持动态热更新 Reality 伪装域名 (SNI)。

---

## 📦 支持的系统

脚本已通过底层重构，完美兼容主流的 Linux 发行版，支持 `amd64` / `arm64` 架构：

- **Debian** 10+
- **Ubuntu** 18.04+
- **CentOS / AlmaLinux / RockyLinux** 7+
- **Alpine Linux** (针对 LXC 容器与小内存轻量机型特别优化，支持 OpenRC)

---

## 🚀 一键安装指南

请使用 `root` 用户登录你的 VPS，然后复制并运行以下命令即可一键安装部署：

```bash
wget -N --no-check-certificate https://raw.githubusercontent.com/yanbinlti-glitch/vless-install/main/vless.sh && sed -i 's/\r$//' vless.sh && bash vless.sh
