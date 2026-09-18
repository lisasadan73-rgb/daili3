# Proxy One-Click（Xray Reality + 订阅 + Telegram 代理）

在新服务器上一键部署与当前节点同类的代理栈：

- **3 条** VLESS + Reality（Vision）：对外端口 `443` / `8443` / `2053`
- **订阅链接**（v2rayN 等）：`http://IP:2080/sub/<token>`
- **Telegram MTProto**（mtg）：`3128`
- **Telegram SOCKS5**：`10808`
- Nginx stream SNI：公网 `443` → 本机 Xray `11443`

每次安装都会**重新生成密钥**，不要把运行后的 `secrets.env` / `CLIENT_INFO.txt` 推到公开仓库。

## 要求

- Debian / Ubuntu（root）
- 能访问 GitHub（下载 Xray、mtg）
- 云厂商安全组放行：`443, 8443, 2053, 3128, 2080, 10808`

## 一键安装

把本仓库弄到新机器后：

```bash
cd proxy-oneclick   # 或你的仓库目录名
bash install.sh
```

可选环境变量：

```bash
# 指定公网 IP（自动检测失败时）
OVERRIDE_PUBLIC_IP=1.2.3.4 bash install.sh

# 节点名称前缀（默认 Node → Node-Reality-443）
NODE_PREFIX=LA bash install.sh

# 安装目录（默认 /root/proxy-setup）
APP_DIR=/opt/proxy-setup bash install.sh

# 不改 nginx（已有 443 业务时）
SKIP_NGINX=1 bash install.sh
```

装完会打印订阅、三条 VLESS、Telegram 链接，并写入：

- `/root/proxy-setup/CLIENT_INFO.txt`
- `/root/proxy-setup/secrets.env`

## 上传到 GitHub（建议 Private）

本仓库**只提交脚本与说明**，不要提交任何密钥文件。

```bash
# 在本机（有 git / gh 的机器上）
cd proxy-oneclick
git init -b main
git add install.sh uninstall.sh README.md .gitignore
git commit -m "Add one-click proxy installer"
gh auth login
gh repo create proxy-oneclick --private --source=. --remote=origin --push
```

新服务器用法：

```bash
# Private 仓库需带 token，或用 SSH
git clone git@github.com:你的用户名/proxy-oneclick.git
cd proxy-oneclick
bash install.sh
```

没有 git 时，也可打包上传：

```bash
tar -czf proxy-oneclick.tar.gz install.sh uninstall.sh README.md .gitignore
# scp 到新机后解压再 bash install.sh
```

## 卸载

```bash
bash uninstall.sh
# 连同官方 Xray 一起卸：
REMOVE_XRAY=1 bash uninstall.sh
```

## 注意

1. **仓库请设为 Private**；即使用 Private，也只提交脚本，密钥只留在服务器。
2. 若机器上已有占用 `443` 的网站，先评估再装，或使用 `SKIP_NGINX=1` 并自行把流量转到 `127.0.0.1:11443`。
3. 本脚本会覆盖 `/usr/local/etc/xray/config.json` 以及 mtg / 订阅相关 systemd 单元。
