#!/bin/bash

# 提示用户输入NUM值
read -e -p "请输入NUM值（>=2）: " num

# 检查是否输入了NUM值以及NUM值是否大于等于2
if [[ -z "$num" || "$num" -lt 2 ]]; then
  echo "错误: 您没有输入有效的NUM值，脚本将退出。"
  exit 1
fi

# 获取系统架构
arch=$(dpkg --print-architecture)

# 生成随机PSK
psk=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)
# 输出PSK并添加颜色（黄色）
echo -e "\033[33mPSK: ${psk}\033[0m"
# 输出NUM并添加颜色（黄色）
echo -e "\033[33mNUM: ${num}\033[0m"

# 下载并解压Snell Server
wget --no-check-certificate -N "https://dl.nssurge.com/snell/snell-server-v4.0.1-linux-${arch}.zip" && \
unzip snell-server-v4.0.1-linux-${arch}.zip && \
rm snell-server-v4.0.1-linux-*.zip

# 重命名并移动Snell Server
mv snell-server snell-server-${num}
sudo mv snell-server-${num} /usr/local/bin
chmod +x /usr/local/bin/snell-server-${num}

# 创建配置目录并生成配置文件
sudo mkdir /etc/snell-${num}
sudo tee /etc/snell-${num}/config.conf > /dev/null <<EOF
[snell-server]
listen = ::0:2346
ipv6 = true
psk= ${psk}
obfs = off              # obfs = http
obfs-host = icloud.com
tfo = true
version = 4
EOF

# 创建systemd服务文件
sudo tee /etc/systemd/system/snell-server-${num}.service > /dev/null <<EOF
[Unit]
Description= Snell Service
After=network-online.target
Wants=network-online.target systemd-networkd-wait-online.service

[Service]
LimitNOFILE=32767 
Type=simple
User=root
Restart=on-failure
RestartSec=5s
ExecStartPre=/bin/sh -c ulimit -n 51200
ExecStart=/usr/local/bin/snell-server-${num} -c /etc/snell-${num}/config.conf

[Install]
WantedBy=multi-user.target
EOF

# 重新加载systemd守护进程并启动服务
sudo systemctl daemon-reload
sudo systemctl enable --now snell-server-${num}
sudo systemctl status snell-server-${num}
