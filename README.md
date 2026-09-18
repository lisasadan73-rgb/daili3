# daili3 一键脚本

Xray VLESS+Reality（3 节点）+ 订阅链接 + Telegram MTProto / SOCKS5  
风格类似 [mack-a/v2ray-agent](https://github.com/mack-a/v2ray-agent)：**一行命令安装**。

> **要用下面的 wget 一键命令，仓库必须设为 Public（公开）。**  
> 私有仓库无法直接 `raw.githubusercontent.com` 下载。  
> 脚本里**不含**密钥，每次安装会在新机器上重新生成。

## 一键安装（推荐）

```bash
wget -P /root -N --no-check-certificate "https://raw.githubusercontent.com/lisasadan73-rgb/daili3/main/install.sh" && chmod 700 /root/install.sh && /root/install.sh
```

或用 curl：

```bash
curl -fsSL "https://raw.githubusercontent.com/lisasadan73-rgb/daili3/main/install.sh" -o /root/install.sh && chmod 700 /root/install.sh && /root/install.sh
```

装完会打印：订阅 URL、3 条 VLESS、Telegram 代理信息。  
备份文件在：`/root/proxy-setup/CLIENT_INFO.txt`

## 安装后有什么

| 项目 | 说明 |
|------|------|
| Reality 节点 | 端口 `443` / `8443` / `2053` |
| 订阅 | `http://IP:2080/sub/<随机token>` |
| Telegram MTProto | `3128` |
| Telegram SOCKS5 | `10808` |
| Nginx | 公网 443 SNI 转发到本机 Xray |

## 可选参数

```bash
OVERRIDE_PUBLIC_IP=1.2.3.4 bash /root/install.sh
NODE_PREFIX=LA bash /root/install.sh
APP_DIR=/opt/proxy-setup bash /root/install.sh
SKIP_NGINX=1 bash /root/install.sh
```

## 要求

- Debian / Ubuntu，root
- 能访问 GitHub（下载 Xray、mtg）
- 安全组放行：`443, 8443, 2053, 3128, 2080, 10808`

## 卸载

```bash
wget -P /root -N --no-check-certificate "https://raw.githubusercontent.com/lisasadan73-rgb/daili3/main/uninstall.sh" && chmod 700 /root/uninstall.sh && /root/uninstall.sh
```

连同 Xray 一起卸：

```bash
REMOVE_XRAY=1 bash /root/uninstall.sh
```

## 把仓库改成公开（才能 wget）

1. 打开 https://github.com/lisasadan73-rgb/daili3/settings  
2. 拉到最下 **Danger Zone** → **Change visibility** → **Public**  
3. 改完后，新服务器直接跑上面的一键命令即可

## 注意

- 脚本会覆盖本机 `/usr/local/etc/xray/config.json` 以及 mtg / 订阅相关 systemd
- 已有网站占用 443 时先评估，或使用 `SKIP_NGINX=1`
- 不要把服务器上生成的 `secrets.env` / `CLIENT_INFO.txt` 再提交回 GitHub
