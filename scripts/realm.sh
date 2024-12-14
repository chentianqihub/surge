#!/bin/bash

red="\033[0;31m"
green="\033[0;32m"
yellow="\033[0;33m"
plain="\033[0m"
Info="${green}[信息]${plain}"
Error="${red}[错误]${plain}"
sh_ver="1.0"
FOLDER="/root/realm"
FILE="/root/realm/realm"
config_file="/root/realm/config.toml"

# 检查realm是否已安装
if [ -f "${FILE}" ]; then
    realm_status="已安装"
    realm_status_color="\033[0;32m" # 绿色
else
    realm_status="未安装"
    realm_status_color="\033[0;31m" # 红色
fi

# 检查realm服务状态
check_realm_service_status() {
    if systemctl is-active --quiet realm; then
        echo -e "\033[0;32m启用\033[0m" # 绿色
    else
        echo -e "\033[0;31m未启用\033[0m" # 红色
    fi
}

# 显示菜单的函数
show_menu() {
    clear
    echo -e " realm一键转发脚本 ${red}[v${sh_ver}]${plain}"
    echo "——————————————————"
    echo " 1. 安装 realm"
    echo "——————————————————"
    echo " 2. 添加 realm 转发规则"
    echo " 3. 查看 realm 转发规则"
    echo " 4. 删除 realm 转发规则"
    echo "——————————————————"
    echo " 5. 启动 realm 服务"
    echo " 6. 停止 realm 服务"
    echo " 7. 重启 realm 服务"
    echo "——————————————————"
    echo " 8. 卸载 realm"
    echo "——————————————————"
    echo " 9. 定时重启任务"
    echo "——————————————————"
    echo "10. 更新脚本"
    echo " 0. 退出脚本"
    echo "——————————————————"
    echo " "
    echo -e "realm 状态: ${realm_status_color}${realm_status}${plain}"
    echo -n "realm 转发状态: "
    check_realm_service_status
}

# 部署环境的函数
deploy_realm() {
    [[ -e ${FILE} ]] && echo -e "${Error} 检测到 realm 已安装, 请先卸载再进行安装 !" && exit 1
    mkdir -p ${FOLDER}
    cd ${FOLDER}
    version=$(curl -s https://api.github.com/repos/zhboner/realm/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

    if [ -z "$version" ]; then
        echo "获取realm版本号失败 !"
        return 1
    else
        echo "当前最新版本为: ${version}"
    fi

    arch=$(uname -m)
    os=$(uname -s | tr '[:upper:]' '[:lower:]')

    case "$arch-$os" in
        x86_64-linux)
            releases="realm-x86_64-unknown-linux-gnu"
            ;;
        x86_64-darwin)
            releases="realm-x86_64-apple-darwin"
            ;;
        aarch64-linux)
            releases="realm-aarch64-unknown-linux-gnu"
            ;;
        aarch64-darwin)
            releases="realm-aarch64-apple-darwin"
            ;;
        arm-linux)
            releases="realm-arm-unknown-linux-gnueabi"
            ;;
        armv7-linux)
            releases="realm-armv7-unknown-linux-gnueabi"
            ;;
        *)
            echo "不支持的架构: $arch-$os"
            return
            ;;
    esac
    
    download_url="https://github.com/zhboner/realm/releases/download/${version}/${releases}.tar.gz"
    wget -O realm.tar.gz "$download_url"
    tar -xvf realm.tar.gz
    rm realm.tar.gz
    chmod +x realm
    # 创建服务文件
    echo "[Unit]
Description=realm
After=network-online.target
Wants=network-online.target systemd-networkd-wait-online.service

[Service]
Type=simple
User=root
Restart=on-failure
RestartSec=5s
DynamicUser=true
WorkingDirectory=/root/realm
ExecStart=/root/realm/realm -c ${config_file}

[Install]
WantedBy=multi-user.target" > /etc/systemd/system/realm.service
    systemctl daemon-reload

    # 服务启动后，检查config.toml是否存在，如果不存在则创建
    if [ ! -f ${config_file} ]; then
        touch ${config_file}
    fi

# 检查 config.toml 中是否已经包含 [network] 配置块
    network_count=$(grep -c '^\[network\]' ${config_file})

    if [ "$network_count" -eq 0 ]; then
    # 如果没有找到 [network]，将其添加到文件顶部
    echo "[network]
no_tcp = false
use_udp = true
" | cat - ${config_file} > temp && mv temp ${config_file}
    echo -e "${green}[network] 配置已添加到 config.toml 文件${plain}"
    
    elif [ "$network_count" -gt 1 ]; then
    # 如果找到多个 [network]，删除多余的配置块，只保留第一个
    sed -i '0,/^\[\[endpoints\]\]/{//!d}' /${config_file}
    echo "[network]
no_tcp = false
use_udp = true
" | cat - ${config_file} > temp && mv temp ${config_file}
    echo -e "${green}多余的 [network] 配置已删除${plain}"
    else
    echo -e "${green}[network] 配置已存在, 跳过添加${plain}"
    fi

    # 更新realm状态变量
    realm_status="已安装"
    realm_status_color="\033[0;32m" # 绿色
    echo -e "${green}部署完成 !${plain}"
}

# 卸载realm
uninstall_realm() {
    systemctl stop realm
    systemctl disable realm
    rm -rf /etc/systemd/system/realm.service
    systemctl daemon-reload
    rm -rf ${FOLDER}
    #rm -rf "$(pwd)"/realm.sh
    sed -i '/realm/d' /etc/crontab
    echo -e "${Info} realm 卸载完成 !"
    # 更新realm状态变量
    realm_status="未安装"
    realm_status_color="\033[0;31m" # 红色
}

# 删除转发规则的函数
delete_forward() {
  echo -e "                   当前 Realm 转发规则                   "
  echo -e "--------------------------------------------------------"
  printf "%-5s| %-15s| %-35s| %-20s\n" "序号" "本地地址:端口 " "    目的地地址:端口 " "备注"
  echo -e "--------------------------------------------------------"
    local IFS=$'\n' # 设置IFS仅以换行符作为分隔符
    # 搜索所有包含 [[endpoints]] 的行，表示转发规则的起始行
    local lines=($(grep -n '^\[\[endpoints\]\]' ${config_file}))
    
    if [ ${#lines[@]} -eq 0 ]; then
        echo "没有发现任何转发规则。"
        return
    fi

    local index=1
    for line in "${lines[@]}"; do
        local line_number=$(echo $line | cut -d ':' -f 1)
        local remark_line=$((line_number + 1))
        local listen_line=$((line_number + 2))
        local remote_line=$((line_number + 3))

        local remark=$(sed -n "${remark_line}p" ${config_file} | grep "^# 备注:" | cut -d ':' -f 2)
        local listen_info=$(sed -n "${listen_line}p" ${config_file} | cut -d '"' -f 2)
        local remote_info=$(sed -n "${remote_line}p" ${config_file} | cut -d '"' -f 2)

        local listen_ip_port=$listen_info
        local remote_ip_port=$remote_info

    printf "%-4s| %-14s| %-28s| %-20s\n" " $index" "$listen_info" "$remote_info" "$remark"
    echo -e "--------------------------------------------------------"
        let index+=1
    done


    echo "请输入要删除的转发规则序号，直接按回车返回主菜单。"
    read -p "选择: " choice
    if [ -z "$choice" ]; then
        echo "返回主菜单。"
        return
    fi

    if ! [[ $choice =~ ^[0-9]+$ ]]; then
        echo "无效输入，请输入数字。"
        return
    fi

    if [ $choice -lt 1 ] || [ $choice -gt ${#lines[@]} ]; then
        echo "选择超出范围，请输入有效序号。"
        return
  fi

  local chosen_line=${lines[$((choice-1))]}
  local start_line=$(echo $chosen_line | cut -d ':' -f 1)

  # 找到下一个 [[endpoints]] 行，确定删除范围的结束行
  local next_endpoints_line=$(grep -n '^\[\[endpoints\]\]' ${config_file} | grep -A 1 "^$start_line:" | tail -n 1 | cut -d ':' -f 1)

  if [ -z "$next_endpoints_line" ] || [ "$next_endpoints_line" -le "$start_line" ]; then
    # 如果没有找到下一个 [[endpoints]]，则删除到文件末尾
    end_line=$(wc -l < ${config_file})
  else
    # 如果找到了下一个 [[endpoints]]，则删除到它的前一行
    end_line=$((next_endpoints_line - 1))
  fi

  # 使用 sed 删除指定行范围的内容
  sed -i "${start_line},${end_line}d" ${config_file}

  # 检查并删除可能多余的空行
  sed -i '/^\s*$/d' ${config_file}

  echo "转发规则及其备注已删除。"

  # 重启服务
  sudo systemctl restart realm.service
}

# 查看转发规则
show_all_conf() {
  echo -e "                   当前 Realm 转发规则                   "
  echo -e "--------------------------------------------------------"
  printf "%-5s| %-15s| %-35s| %-20s\n" "序号" "本地地址:端口 " "    目的地地址:端口 " "备注"
  echo -e "--------------------------------------------------------"
    local IFS=$'\n' # 设置IFS仅以换行符作为分隔符
    # 搜索所有包含 listen 的行，表示转发规则的起始行
    local lines=($(grep -n 'listen =' ${config_file}))
    
    if [ ${#lines[@]} -eq 0 ]; then
  echo -e "没有发现任何转发规则。"
        return
    fi

    local index=1
    for line in "${lines[@]}"; do
        local line_number=$(echo $line | cut -d ':' -f 1)
        local listen_info=$(sed -n "${line_number}p" ${config_file} | cut -d '"' -f 2)
        local remote_info=$(sed -n "$((line_number + 1))p" ${config_file} | cut -d '"' -f 2)
        local remark=$(sed -n "$((line_number-1))p" ${config_file} | grep "^# 备注:" | cut -d ':' -f 2)
        
        local listen_ip_port=$listen_info
        local remote_ip_port=$remote_info
        
    printf "%-4s| %-14s| %-28s| %-20s\n" " $index" "$listen_info" "$remote_info" "$remark"
    echo -e "--------------------------------------------------------"
        let index+=1
    done
}

# 添加转发规则
add_forward() {
    while true; do
        read -p "请输入本地监听端口: " local_port
        read -p "请输入需要转发的IP: " ip
        read -p "请输入需要转发端口: " port
        read -p "请输入备注(非中文): " remark
        # 追加到config.toml文件
        echo "[[endpoints]]
# 备注: $remark
listen = \"[::]:$local_port\"
remote = \"$ip:$port\"" >> ${config_file}
        
        read -p "是否继续添加(Y/N)? " answer
        if [[ $answer != "Y" && $answer != "y" ]]; then
            break
        fi
    done    
    sudo systemctl restart realm.service
}

# 启动服务
start_service() {
    sudo systemctl unmask realm.service
    sudo systemctl daemon-reload
    sudo systemctl restart realm.service
    sudo systemctl enable realm.service
    echo "realm服务已启动并设置为开机自启 !"
}

# 停止服务
stop_service() {
    systemctl stop realm
    echo "realm服务已停止 !"
}

# 重启服务
restart_service() {
    sudo systemctl stop realm
    sudo systemctl unmask realm.service
    sudo systemctl daemon-reload
    sudo systemctl restart realm.service
    sudo systemctl enable realm.service
    echo "realm服务已重启 !"
}

# 定时任务
cron_restart() {
  echo -e "------------------------------------------------------------------"
  echo -e "realm定时重启任务: "
  echo -e "-----------------------------------"
  echo -e "[1] 配置realm定时重启任务"
  echo -e "[2] 删除realm定时重启任务"
  echo -e "-----------------------------------"
  read -p "请选择: " numcron
  if [ "$numcron" == "1" ]; then
    echo -e "------------------------------------------------------------------"
    echo -e "realm定时重启任务类型: "
    echo -e "-----------------------------------"
    echo -e "[1] 每 ? 小时重启"
    echo -e "[2] 每日？点重启"
    echo -e "-----------------------------------"
    read -p "请选择: " numcrontype
    if [ "$numcrontype" == "1" ]; then
      echo -e "-----------------------------------"
      read -p "每 ? 小时重启: " cronhr
      echo "0 */$cronhr * * * root /usr/bin/systemctl restart realm" >>/etc/crontab
      echo -e "定时重启设置成功 !"
    elif [ "$numcrontype" == "2" ]; then
      echo -e "-----------------------------------"
      read -p "每日 ? 点重启: " cronhr
      echo "0 $cronhr * * * root /usr/bin/systemctl restart realm" >>/etc/crontab
      echo -e "定时重启设置成功 !"
    else
      echo "输入错误，请重试 !"
      exit
    fi
  elif [ "$numcron" == "2" ]; then
    sed -i "/realm/d" /etc/crontab
    echo -e "定时重启任务删除完成 !"
  else
    echo "输入错误，请重试 !"
    exit
  fi
}

# 更新脚本
Update_Shell() {
    echo -e "当前脚本版本为 [ ${sh_ver} ], 开始检测最新版本..."
    sh_new_ver=$(wget --no-check-certificate -qO- "https://raw.githubusercontent.com/chentianqihub/surge/main/scripts/realm.sh" | grep 'sh_ver="' | awk -F "=" '{print $NF}' | sed 's/\"//g' | head -1)
    if [[ -z ${sh_new_ver} ]]; then
        echo -e "${red}检测最新版本失败 !${plain}"
        return 1
    fi

    if [[ ${sh_new_ver} == ${sh_ver} ]]; then
        echo -e "当前已是最新版本 [ ${sh_new_ver} ]!"
        return 0
    fi

    # 提示用户是否更新
    echo -e "发现新版本 [ ${sh_new_ver} ]，是否更新? [Y/n]"
    read -p "(默认: y): " yn
    yn=${yn:-y} # 默认值为 'y'
    if [[ ${yn} =~ ^[Yy]$ ]]; then
        wget -N --no-check-certificate https://raw.githubusercontent.com/chentianqihub/surge/main/scripts/realm.sh -O realm.sh
        if [[ $? -ne 0 ]]; then
            echo -e "${red}下载脚本失败，请检查网络连接！${plain}"
            return 1
        fi
        echo -e "脚本已更新为最新版本 [ ${sh_new_ver} ] !"
        echo -e "3s后执行新脚本"
        sleep 3s
        exec bash realm.sh
    else
        echo -e "已取消..."
    fi
}

# 主循环
while true; do
    show_menu
    read -p "请选择一个选项[0-10]（默认值: 1）: " choice
    # 去掉输入中的空格
    #choice=$(echo $choice | tr -d '[:space:]')
    [[ -z "$choice" ]] && choice=1
    
    case $choice in
        1)
            deploy_realm
            ;;
        2)
            add_forward
            ;;
        3)
            show_all_conf
            ;;
        4)
            delete_forward
            ;;
        5)
            start_service
            ;;
        6)
            stop_service
            ;;
        7)
            restart_service
            ;;
        8)
            uninstall_realm
            ;;
        9)
            cron_restart
            ;;
        10)
            Update_Shell
            ;;  
        0)
            echo "退出脚本..."  
            exit 0            
            ;;
        *)
            echo "无效选项: $choice, 请输入正确数字${yellow}[0-10]${plain}"
            ;;
    esac
    read -p "按任意键继续..." key
done
