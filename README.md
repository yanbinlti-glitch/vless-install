# 🌟 VLESS 多模式全能部署与管理脚本 (修复升级版)

基于 `sing-box` 核心构建的极简、高效、全能的 VLESS 节点一键部署脚本。专为现代网络环境设计，提供高度自动化的安装体验和智能化的客户端订阅分发。

🔗 **项目来源**: [哆啦的Github库](https://github.com/yanbinlti-glitch)

---

## ✨ 核心特性

* 🚀 **多协议完美支持**
    * **VLESS + TCP + Reality**: （强烈推荐）无需域名，防主动探测极佳，适合所有裸机 VPS。
    * **VLESS + TCP + TLS**: 经典直连模式，自动申请 ACME 证书，全站真实伪装。
    * **VLESS + WS + TLS**: 拯救被墙 IP 的 CDN 救星模式，完美兼容 Cloudflare 小黄云。
* 📦 **极致轻量且现代**
    * 采用地表最强的 `sing-box` 核心，性能卓越，资源占用远低于传统 Xray-core。
* 🔗 **全平台智能订阅下发**
    * 内置轻量级 Python 订阅服务器。
    * **自动识别客户端 UA**，为 Clash Meta (Mihomo)、v2rayN、Shadowrocket 等自动下发 YAML 规则或 Base64 订阅。
* 🌍 **链式代理 (住宅 IP 落地)**
    * 支持一键导入 `socks5://`, `http://`, `https://` 代理 URI。
    * 轻松实现静态住宅 IP / 原生 IP 落地，完美解锁 Netflix、ChatGPT、Disney+ 等流媒体与 AI 服务。
* 🛡️ **极简运维**
    * 纯自动化依赖安装、防火墙端口放行与清理。
    * 一键开启 BBR 拥塞控制调优。
    * 全局快捷命令 `vvv`，随时随地唤出管理菜单。

---

## 💻 支持的操作系统

脚本已内置完善的系统判定逻辑，支持以下主流 Linux 发行版（需 `root` 权限）：

* **Debian** 9+
* **Ubuntu** 18.04+
* **CentOS / RedHat / AlmaLinux / RockyLinux** 7+
* **Alpine Linux** (原生兼容 rc-service)
* **Fedora** / **Amazon Linux**

---

## 🚀 一键部署启动

请在登录 VPS 后（确保具有 `root` 权限），直接复制并运行以下**一键安装命令**：

```bash
wget -O vless.sh [https://raw.githubusercontent.com/yanbinlti-glitch/YOUR_REPO_NAME/main/vless.sh](https://raw.githubusercontent.com/yanbinlti-glitch/YOUR_REPO_NAME/main/vless.sh) && chmod +x vless.sh && sudo ./vless.sh
