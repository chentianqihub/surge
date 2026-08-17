#!/bin/bash

# 设置遇到错误即停止执行
set -e

# ==========================================
# 1. 系统识别
# ==========================================
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID=$ID
    CODENAME=$VERSION_CODENAME
else
    echo "无法检测到操作系统信息 (找不到 /etc/os-release)。"
    exit 1
fi

# 判断是否为 Ubuntu 或 Debian
if [ "$OS_ID" != "ubuntu" ] && [ "$OS_ID" != "debian" ]; then
    echo "错误：此脚本仅支持 Ubuntu 或 Debian 系统。当前系统识别为：$OS_ID"
    exit 1
fi

echo "========================================="
echo "  检测到系统为：$OS_ID ($CODENAME)"
echo "  开始安装并配置 Docker (腾讯云源)"
echo "========================================="

# ==========================================
# 2. 安装并配置 Docker
# ==========================================
echo ">>> 1. 更新软件包列表并安装必要依赖..."
sudo apt-get update
sudo apt-get install ca-certificates curl -y

echo ">>> 2. 添加 Docker 的 GPG 密钥..."
sudo install -m 0755 -d /etc/apt/keyrings
# 这里的 URL 中使用了 ${OS_ID} 变量，根据系统自动变成 ubuntu 或 debian
sudo curl -fsSL "https://mirrors.cloud.tencent.com/docker-ce/linux/${OS_ID}/gpg" -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo ">>> 3. 配置 Docker 的 apt 软件源..."
# 同样使用 ${OS_ID} 和 ${CODENAME} 变量
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://mirrors.cloud.tencent.com/docker-ce/linux/${OS_ID}/ \
  ${CODENAME} stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

echo ">>> 4. 再次更新软件包列表..."
sudo apt-get update

echo ">>> 5. 安装 Docker 相关组件..."
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y

echo ">>> 6. 启动 Docker 并设置开机自启..."
sudo systemctl start docker
sudo systemctl enable docker

# ==========================================
# 3. 配置镜像加速器
# ==========================================
echo ">>> 7. 配置 Docker 镜像加速器 (腾讯云内部源)..."
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json > /dev/null <<EOF
{
    "registry-mirrors": [
        "https://mirror.ccs.tencentyun.com"
    ]
}
EOF

echo ">>> 8. 重启 Docker 服务使配置生效..."
sudo systemctl daemon-reload
sudo systemctl restart docker

echo ">>> 9. 检查镜像源配置结果..."
echo "当前配置的 Registry Mirrors 为："
sudo docker info | grep "Registry Mirrors" -A 1

echo "========================================="
echo "  Docker 安装与配置已全部完成！"
echo "========================================="
