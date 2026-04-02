# Keepalived一键安装命令，快捷启动：ka

```
curl -fsSL https://raw.githubusercontent.com/creval88/script/refs/heads/main/Keepalived/keepalived.sh -o /usr/bin/ka || wget -qO /usr/bin/ka https://raw.githubusercontent.com/creval88/script/refs/heads/main/Keepalived/keepalived.sh && chmod +x /usr/bin/ka && ka
```
记得在Mosdns，的域名重定向设置 ai.mosdns.mos 10.10.88.88
