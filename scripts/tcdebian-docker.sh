#!/bin/bash

# 设置遇到错误即停止执行
set -e

echo "========================================="
echo "  开始安装并配置 Docker (Debian 腾讯云源)"
echo "========================================="

echo ">>> 1. 更新软件包列表并安装必要依赖..."
sudo apt-get update
sudo apt-get install ca-certificates curl -y

echo ">>> 2. 添加 Docker 的 GPG 密钥..."
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://mirrors.cloud.tencent.com/docker-ce/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo ">>> 3. 配置 Docker 的 apt 软件源..."
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://mirrors.cloud.tencent.com/docker-ce/linux/debian/ \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

echo ">>> 4. 再次更新软件包列表..."
sudo apt-get update

echo ">>> 5. 安装 Docker 相关组件..."
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y

echo ">>> 6. 启动 Docker 并设置开机自启..."
sudo systemctl start docker
sudo systemctl enable docker

echo ">>> 7. 配置 Docker 镜像加速器 (腾讯云内部源)..."
# 确保配置目录存在
sudo mkdir -p /etc/docker
# 使用 tee 命令将 JSON 内容直接写入文件
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
echo "  您可以尝试执行 docker pull hello-world 来测试拉取镜像"
echo "========================================="

