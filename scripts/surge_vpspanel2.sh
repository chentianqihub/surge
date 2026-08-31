#!/bin/bash

# 确保脚本以 root 权限运行
if [ "$EUID" -ne 0 ]; then
  echo "请以 root 权限运行此脚本 (Please run as root)"
  exit 1
fi

echo "1. 正在更新软件包列表并安装依赖 (Python3, pip, venv, curl, jq)..."
apt update
apt install -y python3 python3-pip python3-venv curl jq

# 定义工作目录和路径
WORKDIR="/root"
VENV_DIR="$WORKDIR/servertraffic_venv"
PY_SCRIPT="$WORKDIR/servertraffic2.py"
SERVICE_FILE="/etc/systemd/system/servertraffic2.service"

echo "2. 创建 Python 虚拟环境..."
# 如果已存在则跳过
if [ ! -d "$VENV_DIR" ]; then
    python3 -m venv $VENV_DIR
fi

echo "3. 在虚拟环境中安装 psutil..."
$VENV_DIR/bin/pip install psutil

echo "4. 正在下载 Python 监控脚本..."
curl -sSL -o $PY_SCRIPT https://raw.githubusercontent.com/chentianqihub/surge/main/scripts/servertraffic2.py

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
systemctl enable servertraffic2.service
systemctl restart servertraffic2.service

echo ""
echo "=========================================================="
echo "安装完成！"
echo "监控服务已在虚拟环境中运行，并已设置为开机自启。"
echo "请确保您的服务器防火墙 / 安全组已放行 7133 端口（或您在脚本中设置的端口）。"
echo "=========================================================="
echo " - 查看服务状态: sudo systemctl status servertraffic2.service"
echo " - 查看服务日志: journalctl -u servertraffic2.service -n 50 --no-pager"
echo " - 测试数据返回: curl -s -A \"Surge/iOS\" -H \"X-CatVPS-Auth: Password\" http://127.0.0.1:7133/vpsinfo2026 | jq"
echo "=========================================================="
