#!/bin/bash

# 定义变量
DOWNLOAD_URL="https://github.com/ameshkov/dnslookup/releases/download/v1.10.1/dnslookup-linux-amd64-v1.10.1.tar.gz"
TAR_FILE="dnslookup-linux-amd64-v1.10.1.tar.gz"
EXTRACT_DIR="linux-amd64"
BIN_DIR="/usr/local/bin"
BIN_FILE="$BIN_DIR/dnslookup"

# 下载文件
echo "Downloading $TAR_FILE..."
if ! wget "$DOWNLOAD_URL"; then
    echo "Error: Failed to download $TAR_FILE"
    exit 1
fi

# 解压文件
echo "Extracting $TAR_FILE..."
if ! tar xvf "$TAR_FILE"; then
    echo "Error: Failed to extract $TAR_FILE"
    rm -f "$TAR_FILE"
    exit 1
fi

# 移动二进制文件
echo "Moving dnslookup to $BIN_DIR..."
if ! sudo mv "$EXTRACT_DIR/dnslookup" "$BIN_FILE"; then
    echo "Error: Failed to move dnslookup to $BIN_DIR"
    rm -f "$TAR_FILE"
    rm -rf "$EXTRACT_DIR"
    exit 1
fi

# 刷新 Shell 缓存
hash -r

# 删除临时文件
echo "Cleaning up..."
rm -f "$TAR_FILE"
rm -rf "$EXTRACT_DIR"

# 检查安装是否成功并输出第一行内容
echo "Verifying installation..."
FIRST_LINE=$(dnslookup --help 2>&1 | head -n 1)
if [ -z "$FIRST_LINE" ]; then
    echo "Error: dnslookup installation failed"
    exit 1
else
    echo "$FIRST_LINE"
    echo "dnslookup installed successfully"
fi
