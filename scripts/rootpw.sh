#!/bin/bash

# 设置 root 用户新密码（建议从输入获取密码）
read -sp "Enter new root password: " root_password
echo "root:$root_password" | sudo chpasswd || { echo "Failed to change root password"; exit 1; }

# 备份 SSH 配置文件
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak || { echo "Failed to backup SSH configuration"; exit 1; }

# 修改 SSH 配置以允许 root 登录和启用密码认证
sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/g' /etc/ssh/sshd_config || { echo "Failed to update PermitRootLogin"; exit 1; }
sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/g' /etc/ssh/sshd_config || { echo "Failed to update PasswordAuthentication"; exit 1; }

# 重启 SSH 服务
sudo service ssh restart || { echo "Failed to restart SSH service"; exit 1; }

echo "Password changed successfully and SSH configuration updated."
