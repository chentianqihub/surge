#!/bin/bash

# 提示用户输入SER值，并确保其大于等于2
read -e -p "请输入SER值(>=2): " SER
if ! [[ "$SER" =~ ^[0-9]+$ ]] || [ "$SER" -lt 2 ]; then
  echo "错误: SER值必须大于等于2"
  exit 1
fi

# 提示用户输入LISTEN值，并确保其是有效的端口号
read -e -p "请输入LISTEN值: " listen
if ! [[ "$listen" =~ ^[0-9]+$ ]] || [ "$listen" -lt 1 ] || [ "$listen" -gt 65535 ]; then
  echo "错误: LISTEN值必须是1到65535之间的数字"
  exit 1
fi

# 提示用户输入SERVER值，并确保其是有效的端口号
read -e -p "请输入SERVER值: " server
if ! [[ "$server" =~ ^[0-9]+$ ]] || [ "$server" -lt 1 ] || [ "$server" -gt 65535 ]; then
  echo "错误: SERVER值必须是1到65535之间的数字"
  exit 1
fi

# 输出用户输入的值并添加颜色（黄色）
echo -e "\033[33mSER: ${SER}\033[0m"
echo -e "\033[33mLISTEN: ${listen}\033[0m"
echo -e "\033[33mSERVER: ${server}\033[0m"

# 下载shadow-tls并检查是否成功
url="https://github.com/ihciah/shadow-tls/releases/download/v0.2.23/shadow-tls-x86_64-unknown-linux-musl"
destination="/usr/local/bin/shadow-tls-${SER}"
if ! wget "$url" -O "$destination"; then
  echo "错误: 下载 shadow-tls 失败"
  exit 1
fi

# 设置可执行权限
chmod +x "$destination"

# 创建systemd服务文件
service_file="/etc/systemd/system/shadow-tls-${SER}.service"
sudo tee "$service_file" > /dev/null <<EOF
[Unit]
Description=Shadow-TLS Server Service
Documentation=man:sstls-server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$destination --v3 server --listen 0.0.0.0:${listen} --server 127.0.0.1:${server} --tls mensura.cdn-apple.com --password JsJeWtjiUyJ5yeto
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=shadow-tls

[Install]
WantedBy=multi-user.target
EOF

# 重新加载systemd守护进程并启动服务
sudo systemctl daemon-reload
sudo systemctl enable shadow-tls-${SER}.service

# 启动服务并检查状态
if sudo systemctl start shadow-tls-${SER}.service; then
  sudo systemctl status shadow-tls-${SER}.service
else
  echo "错误: 启动 shadow-tls 服务失败"
  exit 1
fi
