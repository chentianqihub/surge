#!/bin/bash

# 确保以 root 权限运行
if [ "$EUID" -ne 0 ]; then
  echo "❌ 请使用 sudo 权限运行此脚本 (例如: sudo bash clean_sys.sh)"
  exit 1
fi

echo "开始系统清理任务..."
echo "-----------------------------------"

TOTAL_FREED=0

# 辅助函数：将字节精确转换为 MB (保留两位小数)
bytes_to_mb() {
    awk "BEGIN {printf \"%.2f\", $1 / 1048576}"
}

# 1. 清理 Journal 日志 (保留最近 100MB)
echo "⏳ [1/4] 正在清理 Journal 日志..."
J_SIZE_BEFORE=$(du -sb /var/log/journal 2>/dev/null | awk '{print $1}')
J_SIZE_BEFORE=${J_SIZE_BEFORE:-0}

journalctl --vacuum-size=100M >/dev/null 2>&1

J_SIZE_AFTER=$(du -sb /var/log/journal 2>/dev/null | awk '{print $1}')
J_SIZE_AFTER=${J_SIZE_AFTER:-0}

J_FREED=$((J_SIZE_BEFORE - J_SIZE_AFTER))
[ $J_FREED -lt 0 ] && J_FREED=0
TOTAL_FREED=$((TOTAL_FREED + J_FREED))

echo "✅ Journal 日志清理完成，释放空间: $(bytes_to_mb $J_FREED) MB"
echo "-----------------------------------"

# 2. 清理旧的系统日志 (*.gz, *.1)
echo "⏳ [2/4] 正在清理旧的归档系统日志..."
OLD_LOGS=$(find /var/log -maxdepth 1 -type f \( -name "*.gz" -o -name "*.1" \))

if [ -n "$OLD_LOGS" ]; then
    L_FREED=$(echo "$OLD_LOGS" | xargs du -sb 2>/dev/null | awk '{sum+=$1} END {print sum}')
    L_FREED=${L_FREED:-0}
    echo "$OLD_LOGS" | xargs rm -f
else
    L_FREED=0
fi

TOTAL_FREED=$((TOTAL_FREED + L_FREED))
echo "✅ 旧系统日志清理完成，释放空间: $(bytes_to_mb $L_FREED) MB"
echo "-----------------------------------"

# 3. 清理 APT 缓存 (/var/cache/apt)
echo "⏳ [3/4] 正在清理软件包缓存..."
C_SIZE_BEFORE=$(du -sb /var/cache/apt/archives 2>/dev/null | awk '{print $1}')
C_SIZE_BEFORE=${C_SIZE_BEFORE:-0}

apt-get clean >/dev/null 2>&1
apt-get autoclean >/dev/null 2>&1

C_SIZE_AFTER=$(du -sb /var/cache/apt/archives 2>/dev/null | awk '{print $1}')
C_SIZE_AFTER=${C_SIZE_AFTER:-0}

C_FREED=$((C_SIZE_BEFORE - C_SIZE_AFTER))
[ $C_FREED -lt 0 ] && C_FREED=0
TOTAL_FREED=$((TOTAL_FREED + C_FREED))

echo "✅ 软件包缓存清理完成，释放空间: $(bytes_to_mb $C_FREED) MB"
echo "-----------------------------------"

# 4. 清理 Docker 容器日志 (*-json.log)
echo "⏳ [4/4] 正在清理 Docker 容器运行日志..."
D_FREED=0
if [ -d "/var/lib/docker/containers" ]; then
    D_SIZE_BEFORE=$(find /var/lib/docker/containers -type f -name "*-json.log" -exec du -sb {} + 2>/dev/null | awk '{sum+=$1} END {print sum}')
    D_SIZE_BEFORE=${D_SIZE_BEFORE:-0}

    # 使用 truncate 清零日志而不是删除文件，避免容器报错
    find /var/lib/docker/containers -type f -name "*-json.log" -exec truncate -s 0 {} + 2>/dev/null

    D_SIZE_AFTER=$(find /var/lib/docker/containers -type f -name "*-json.log" -exec du -sb {} + 2>/dev/null | awk '{sum+=$1} END {print sum}')
    D_SIZE_AFTER=${D_SIZE_AFTER:-0}

    D_FREED=$((D_SIZE_BEFORE - D_SIZE_AFTER))
    [ $D_FREED -lt 0 ] && D_FREED=0
fi

TOTAL_FREED=$((TOTAL_FREED + D_FREED))
echo "✅ Docker 容器日志清理完成，释放空间: $(bytes_to_mb $D_FREED) MB"
echo "-----------------------------------"

# 汇总
echo "🎉 清理总计释放空间: $(bytes_to_mb $TOTAL_FREED) MB"
