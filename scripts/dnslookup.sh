#!/bin/bash

DNSLOOKUP_VERSION=$(curl -s "https://api.github.com/repos/ameshkov/dnslookup/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
DOWNLOAD_URL="https://github.com/ameshkov/dnslookup/releases/download/${DNSLOOKUP_VERSION}/dnslookup-linux-amd64-${DNSLOOKUP_VERSION}.tar.gz"
TAR_FILE="dnslookup-linux-amd64-${DNSLOOKUP_VERSION}.tar.gz"
EXTRACT_DIR="linux-amd64"
BIN_DIR="/usr/local/bin"
BIN_FILE="$BIN_DIR/dnslookup"
GRE='\033[0;32m'
NC='\033[0m'   # (重置颜色)

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
FIRST_LINE=$(dnslookup --help | head -n 1)
if [ -z "$FIRST_LINE" ]; then
    echo "Error: dnslookup installation failed"
    exit 1
else
    echo -e "${GRE}${FIRST_LINE}${NC}"
    echo "dnslookup installed successfully"
fi
