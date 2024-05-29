#!/bin/bash

# 检查是否以 root 身份运行
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root. Please switch to root user or use sudo."
    exit 1
fi

# 获取用户输入的密码，并进行二次确认
while true; do
    read -sp "Enter new root password: " root_password
    echo
    read -sp "Confirm new root password: " confirm_password
    echo
    if [ "$root_password" == "$confirm_password" ]; then
        break
    else
        echo "Passwords do not match. Please try again."
    fi
done

# 修改 root 用户的密码
echo "root:$root_password" | sudo chpasswd || { echo "Failed to change root password"; exit 1; }

# 备份 SSH 配置文件
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak || { echo "Failed to backup SSH configuration"; exit 1; }

# 修改 SSH 配置以允许 root 登录和启用密码认证
sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/g' /etc/ssh/sshd_config || { echo "Failed to update PermitRootLogin"; exit 1; }
sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/g' /etc/ssh/sshd_config || { echo "Failed to update PasswordAuthentication"; exit 1; }

# 检查系统是否为 Ubuntu
if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [ "$ID" == "ubuntu" ]; then
        # 修改 ChallengeResponseAuthentication 为 yes（如果存在）
        sudo sed -i 's/^#\?ChallengeResponseAuthentication.*/ChallengeResponseAuthentication yes/g' /etc/ssh/sshd_config || { echo "Failed to update ChallengeResponseAuthentication"; exit 1; }
    fi
fi

# 重启 SSH 服务
sudo service ssh restart || { echo "Failed to restart SSH service"; exit 1; }

echo "Password changed successfully and SSH configuration updated."

