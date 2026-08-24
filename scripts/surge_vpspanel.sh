#!/bin/bash

# 确保脚本以 root 权限运行
if [ "$EUID" -ne 0 ]; then
  echo "请以 root 权限运行此脚本 (Please run as root)"
  exit 1
fi

echo "1. 正在更新软件包列表并安装依赖 (Python3, pip, venv)..."
apt update
apt install -y python3 python3-pip python3-venv

# 定义工作目录和路径
WORKDIR="/root"
VENV_DIR="$WORKDIR/servertraffic_venv"
PY_SCRIPT="$WORKDIR/servertraffic.py"
SERVICE_FILE="/etc/systemd/system/servertraffic.service"

echo "2. 创建 Python 虚拟环境..."
# 如果已存在则跳过
if [ ! -d "$VENV_DIR" ]; then
    python3 -m venv $VENV_DIR
fi

echo "3. 在虚拟环境中安装 psutil..."
$VENV_DIR/bin/pip install psutil

echo "4. 生成 Python 监控脚本..."
cat << 'EOF' > $PY_SCRIPT
#!/usr/bin/env python3
# Sestea

import http.server
import socketserver
import json
import time
import psutil

# The port number of the local HTTP server, which can be modified
port = 7122

class RequestHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.end_headers()

        # Limit the HTTP server to one request per second
        time.sleep(1)

        # Obtain CPU/MEM usage and network traffic info
        cpu_usage = psutil.cpu_percent()
        mem_usage = psutil.virtual_memory().percent
        bytes_sent = psutil.net_io_counters().bytes_sent
        bytes_recv = psutil.net_io_counters().bytes_recv
        bytes_total = bytes_sent + bytes_recv

        # Get UTC timestamp and uptime
        utc_timestamp = int(time.time())
        uptime = int(time.time() - psutil.boot_time())

        # Get the last statistics time
        last_time = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime())

        # Construct JSON dictionary
        response_dict = {
            "utc_timestamp": utc_timestamp,
            "uptime": uptime,
            "cpu_usage": cpu_usage,
            "mem_usage": mem_usage,
            "bytes_sent": str(bytes_sent),
            "bytes_recv": str(bytes_recv),
            "bytes_total": str(bytes_total),
            "last_time": last_time
        }

        # Convert JSON dictionary to JSON string
        response_json = json.dumps(response_dict).encode('utf-8')
        self.wfile.write(response_json)

# 允许端口复用，防止重启服务时报 Address already in use
socketserver.ThreadingTCPServer.allow_reuse_address = True

with socketserver.ThreadingTCPServer(("", port), RequestHandler) as httpd:
    try:
        print(f"Serving at port {port}")
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("KeyboardInterrupt is captured, program exited")
EOF

echo "5. 生成 Systemd 服务文件..."
cat << EOF > $SERVICE_FILE
[Unit]
Description=Server Traffic Monitor
After=network.target

[Service]
Type=simple
WorkingDirectory=$WORKDIR
User=root
# 使用虚拟环境内的 python3 执行脚本
ExecStart=$VENV_DIR/bin/python3 $PY_SCRIPT
Restart=always

[Install]
WantedBy=multi-user.target
EOF

echo "6. 重新加载 systemd 并启动服务..."
systemctl daemon-reload
systemctl enable servertraffic.service
systemctl restart servertraffic.service

echo ""
echo "=========================================================="
echo "安装完成！"
echo "监控服务已在虚拟环境中运行，并已设置为开机自启。"
echo "请确保您的服务器防火墙 / 安全组已放行 7122 端口。"
echo "=========================================================="
echo " - 查看服务状态: sudo systemctl status servertraffic.service"
echo " - 查看服务日志: journalctl -u servertraffic.service -n 50 --no-pager"
echo " - 测试数据返回: curl http://127.0.0.1:7122"
echo "=========================================================="
