#!/usr/bin/env bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

sh_ver="1.6.8"
filepath=$(cd "$(dirname "$0")"; pwd)
file_1=$(echo -e "${filepath}"|awk -F "$0" '{print $1}')
FOLDER="/etc/snell/"
FILE="/usr/local/bin/snell-server"
Shadow_TLS_FILE="/usr/local/bin/shadow-tls"
CONF="/etc/snell/config.conf"
Now_ver_File="/etc/snell/ver.txt"
Local="/etc/sysctl.d/local.conf"

Green_font_prefix="\033[32m" && Red_font_prefix="\033[31m" && Yellow_font_prefix="\033[0;33m" && Blue_font_prefix="\033[0;36m" && Green_background_prefix="\033[42;37m" && Red_background_prefix="\033[41;37m" && Font_color_suffix="\033[0m"
Info="${Green_font_prefix}[信息]${Font_color_suffix}"
Error="${Red_font_prefix}[错误]${Font_color_suffix}"
Tip="${Yellow_font_prefix}[注意]${Font_color_suffix}"
Warn="${Yellow_font_prefix}[Warn]${Font_color_suffix}"

check_root(){
	[[ $EUID != 0 ]] && echo -e "${Error} 当前非ROOT账号(或没有ROOT权限),无法继续操作,请更换ROOT账号或使用 ${Green_background_prefix}sudo su${Font_color_suffix} 命令获取临时ROOT权限（执行后可能会提示输入当前账号的密码）。" && exit 1
}
#检查系统
check_sys(){
	if [[ -f /etc/redhat-release ]]; then
		release="centos"
	elif cat /etc/issue | grep -q -E -i "debian"; then
		release="debian"
	elif cat /etc/issue | grep -q -E -i "ubuntu"; then
		release="ubuntu"
	elif cat /etc/issue | grep -q -E -i "centos|red hat|redhat"; then
		release="centos"
	elif cat /proc/version | grep -q -E -i "debian"; then
		release="debian"
	elif cat /proc/version | grep -q -E -i "ubuntu"; then
		release="ubuntu"
	elif cat /proc/version | grep -q -E -i "centos|red hat|redhat"; then
		release="centos"
    fi
}

Installation_dependency(){
	if [[ ${release} == "centos" ]]; then
		yum update && yum install gzip wget curl unzip jq -y
	else
		apt-get update && apt-get install gzip wget curl unzip jq -y
	fi
	sysctl -w net.core.rmem_max=26214400
	sysctl -w net.core.rmem_default=26214400
	\cp -f /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
}

#检查系统内核版本
sysArch() {
    uname=$(uname -m)
    if [[ "$uname" == "i686" ]] || [[ "$uname" == "i386" ]]; then
        arch="i386"
    elif [[ "$uname" == *"armv7"* ]] || [[ "$uname" == "armv6l" ]]; then
        arch="armv7l"
    elif [[ "$uname" == *"armv8"* ]] || [[ "$uname" == "aarch64" ]]; then
        arch="aarch64"
    else
        arch="amd64"
    fi    
}

#开启系统 TCP Fast Open
enable_systfo() {
	kernel=$(uname -r | awk -F . '{print $1}')
	if [ "$kernel" -ge 3 ]; then
		echo 3 >/proc/sys/net/ipv4/tcp_fastopen
		[[ ! -e $Local ]] && echo "fs.file-max = 51200
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.rmem_default = 65536
net.core.wmem_default = 65536
net.core.netdev_max_backlog = 4096
net.core.somaxconn = 4096
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_tw_recycle = 0
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.ip_local_port_range = 10000 65000
net.ipv4.tcp_max_syn_backlog = 4096
net.ipv4.tcp_max_tw_buckets = 5000
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_ecn=1
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control = bbr" >>/etc/sysctl.d/local.conf && sysctl --system >/dev/null 2>&1
	else
		echo -e "$Error系统内核版本过低,无法支持 TCP Fast Open !"
	fi
}

check_installed_status(){
	[[ ! -e ${FILE} ]] && echo -e "${Error} Snell Server 没有安装,请检查 !" && exit 1
}

check_status(){
	#status=`systemctl status snell-server | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1`
	status=$(systemctl status shadow-tls.service | grep "Active" | awk -F'[()]' '{print $2}')
}

getSnellv4Url(){
	sysArch
	snell_v4_url="https://dl.nssurge.com/snell/snell-server-v4.1.0-linux-${arch}.zip"
}

getVer(){
	getSnellv4Url
	filename=$(basename "${snell_v4_url}")
	if [[ $filename =~ v([0-9]+\.[0-9]+\.[0-9]+(rc[0-9]*|b[0-9]*)?) ]]; then
    new_ver=${BASH_REMATCH[1]}
    echo -e "${Info} 检测到 Snell 最新版本为 [ ${new_ver} ]"
		else
    echo -e "${Error} Snell Server 最新版本获取失败！"
		fi
}

# v2 备用源
v2_Download() {
	echo -e "${Info} 默认开始下载 ${Yellow_font_prefix}v2 备用源版 ${Font_color_suffix}Snell Server ..."
	wget --no-check-certificate -N "https://raw.githubusercontent.com/xOS/Others/master/snell/v2.0.6/snell-server-v2.0.6-linux-${arch}.zip"
	if [[ ! -e "snell-server-v2.0.6-linux-${arch}.zip" ]]; then
		echo -e "${Error} Snell Server ${Yellow_font_prefix}v2 备用源版${Font_color_suffix} 下载失败 !"
		return 1 && exit 1
	else
		unzip -o "snell-server-v2.0.6-linux-${arch}.zip"
	fi
	if [[ ! -e "snell-server" ]]; then
		echo -e "${Error} Snell Server ${Yellow_font_prefix}v2 备用源版${Font_color_suffix} 解压失败 !"
		echo -e "${Error} Snell Server ${Yellow_font_prefix}v2 备用源版${Font_color_suffix} 安装失败 !"
		return 1 && exit 1
	else
		rm -rf "snell-server-v2.0.6-linux-${arch}.zip"
		chmod +x snell-server
		mv -f snell-server "${FILE}"
		echo "v2.0.6" > ${Now_ver_File}
		echo -e "${Info} Snell Server 主程序下载安装完毕 !"
		return 0
	fi
}

# v3 备用源
v3_Download() {
	echo -e "${Info} 试图请求 ${Yellow_font_prefix}v3 备用源版${Font_color_suffix} Snell Server ..."
	wget --no-check-certificate -N "https://raw.githubusercontent.com/xOS/Others/master/snell/v3.0.1/snell-server-v3.0.1-linux-${arch}.zip"
	if [[ ! -e "snell-server-v3.0.1-linux-${arch}.zip" ]]; then
		echo -e "${Error} Snell Server ${Yellow_font_prefix}v3 备用源版${Font_color_suffix} 下载失败 !"
		return 1 && exit 1
	else
		unzip -o "snell-server-v3.0.1-linux-${arch}.zip"
	fi
	if [[ ! -e "snell-server" ]]; then
		echo -e "${Error} Snell Server ${Yellow_font_prefix}v3 备用源版${Font_color_suffix} 解压失败 !"
		echo -e "${Error} Snell Server ${Yellow_font_prefix}v3 备用源版${Font_color_suffix} 安装失败 !"
		return 1 && exit 1
	else
		rm -rf "snell-server-v3.0.1-linux-${arch}.zip"
		chmod +x snell-server
		mv -f snell-server "${FILE}"
		echo "v3.0.1" > ${Now_ver_File}
		echo -e "${Info} Snell Server 主程序下载安装完毕 !"
		return 0
	fi
}

# v4 官方源
v4_Download(){
	echo -e "${Info} 试图请求 ${Yellow_font_prefix}v4 官网源版${Font_color_suffix} Snell Server ..."
	getVer

	wget --no-check-certificate -N "${snell_v4_url}"
	if [[ ! -e "snell-server-v${new_ver}-linux-${arch}.zip" ]]; then
		echo -e "${Error} Snell Server ${Yellow_font_prefix}v4 官网源版${Font_color_suffix} 下载失败 !"
		return 1 && exit 1
	else
		unzip -o "snell-server-v${new_ver}-linux-${arch}.zip"
	fi
	if [[ ! -e "snell-server" ]]; then
		echo -e "${Error} Snell Server ${Yellow_font_prefix}v4 官网源版${Font_color_suffix} 解压失败 !"
		echo -e "${Error} Snell Server ${Yellow_font_prefix}v4 官网源版${Font_color_suffix} 安装失败 !"
		return 1 && exit 1
	else
		rm -rf "snell-server-v${new_ver}-linux-${arch}.zip"
		chmod +x snell-server
		mv -f snell-server "${FILE}"
		echo "v${new_ver}" > ${Now_ver_File}
		echo -e "${Info} Snell Server 主程序下载安装完毕 !"
		return 0
	fi
}

# 安装
Install() {
	if [[ ! -e "${FOLDER}" ]]; then
		mkdir "${FOLDER}"
	fi
    [[ -e ${FILE} ]] && echo -e "${Error} 检测到 Snell Server 已安装,请先卸载再进行安装 !" && exit 1
		echo -e "选择安装版本${Yellow_font_prefix}[2-4]${Font_color_suffix} 
==================================
${Green_font_prefix} 2.${Font_color_suffix} v2  ${Green_font_prefix} 3.${Font_color_suffix} v3  ${Green_font_prefix} 4.${Font_color_suffix} v4
=================================="
	read -e -p "(默认：4.v4)：" ver
	[[ -z "${ver}" ]] && ver="4"
	if [[ ${ver} == "2" ]]; then
		Install_v2
	elif [[ ${ver} == "3" ]]; then
		Install_v3
	elif [[ ${ver} == "4" ]]; then
		Install_v4
	else
	     echo -e "${Red_font_prefix}[Warn]${Font_color_suffix} 无效输入! 将取默认值${Yellow_font_prefix} v4${Font_color_suffix}"
		ver="4"
                Install_v4
	fi
}

Service(){
	echo '
[Unit]
Description= Snell Service
After=network-online.target
Wants=network-online.target systemd-networkd-wait-online.service
[Service]
LimitNOFILE=32767 
Type=simple
User=root
Restart=on-failure
RestartSec=5s
ExecStartPre=/bin/sh -c 'ulimit -n 51200'
ExecStart=/usr/local/bin/snell-server -c /etc/snell/config.conf
[Install]
WantedBy=multi-user.target' > /etc/systemd/system/snell-server.service
systemctl enable --now snell-server
	echo -e "${Info} Snell Server 服务配置完成 !"
}

Write_config(){
	cat > ${CONF}<<-EOF
[snell-server]
listen = ::0:${port}
ipv6 = ${ipv6}
psk = ${psk}
obfs = ${obfs}
obfs-host = ${host}
tfo = ${tfo}
dns = ${dns}
version = ${ver}
EOF
}

Read_config(){
	[[ ! -e ${CONF} ]] && echo -e "${Error} Snell Server 配置文件不存在 !" && exit 1
	ipv6=$(cat ${CONF}|grep 'ipv6 = '|awk -F 'ipv6 = ' '{print $NF}')
	port=$(grep -E '^listen\s*=' ${CONF} | awk -F ':' '{print $NF}' | xargs)
	psk=$(cat ${CONF}|grep 'psk = '|awk -F 'psk = ' '{print $NF}')
	obfs=$(cat ${CONF}|grep 'obfs = '|awk -F 'obfs = ' '{print $NF}')
	host=$(cat ${CONF}|grep 'obfs-host = '|awk -F 'obfs-host = ' '{print $NF}')
	tfo=$(cat ${CONF}|grep 'tfo = '|awk -F 'tfo = ' '{print $NF}')
        dns=$(cat ${CONF}|grep 'dns = '|awk -F 'dns = ' '{print $NF}')
	ver=$(cat ${CONF}|grep 'version = '|awk -F 'version = ' '{print $NF}')
}

Set_port(){
    # 循环直到用户输入有效且未被占用的端口值
    while true; do
        echo -e "请输入 Snell Server 端口${Yellow_font_prefix}[1-65535]${Font_color_suffix}"
        read -e -p "(默认: 2345): " port
        [[ -z "${port}" ]] && port="2345"

        # 检查输入的端口是否为数字并在有效范围内
        if [[ ${port} =~ ^[0-9]+$ ]] && [[ ${port} -ge 1 ]] && [[ ${port} -le 65535 ]]; then
            # 检查端口是否被占用
            if ss -tunlp | grep -q ":${port}\b"; then
                echo -e "${Error} 端口 ${port} 已被占用, 请选择其他端口!" && echo
            else
                echo && echo "=============================="
                echo -e "端口 : ${Red_background_prefix} ${port} ${Font_color_suffix}"
                echo "==============================" && echo
                break
            fi
        else
            echo -e "${Error} 输入错误, 请输入正确的端口 !"
        fi
    done
}

Edit_port(){
    # 循环直到用户输入有效且未被占用的端口值
    while true; do
        echo -e "请输入 Snell Server 端口${Yellow_font_prefix}[1-65535]${Font_color_suffix}"
        read -e -p "(默认: 2345): " port
        [[ -z "${port}" ]] && port="2345"

        # 检查输入的端口是否为数字并在有效范围内
        if [[ ${port} =~ ^[0-9]+$ ]] && [[ ${port} -ge 1 ]] && [[ ${port} -le 65535 ]]; then
                echo && echo "=============================="
                echo -e "端口 : ${Red_background_prefix} ${port} ${Font_color_suffix}"
                echo "==============================" && echo
                break
        else
            echo -e "${Error} 输入错误, 请输入正确的端口 !"
        fi
    done
}

Set_ipv6(){
	echo -e "是否开启 IPv6 解析 ?
==================================
${Green_font_prefix} 1.${Font_color_suffix} 开启  ${Green_font_prefix} 2.${Font_color_suffix} 关闭
=================================="
	read -e -p "(默认: 2.关闭): " ipv6
	[[ -z "${ipv6}" ]] && ipv6="2"
	if [[ ${ipv6} == "1" ]]; then
		ipv6=true
	else
		ipv6=false
	fi
	echo && echo "=================================="
	echo -e "IPv6 解析 开启状态: ${Red_background_prefix} ${ipv6} ${Font_color_suffix}"
	echo "==================================" && echo
}

Set_psk(){
	echo -e "请输入 Snell Server 密钥 [0-9][a-z][A-Z]"
	read -e -p "(默认: 随机生成): " psk
	[[ -z "${psk}" ]] && psk=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)
	echo && echo "=============================="
	echo -e "密钥 : ${Red_background_prefix} ${psk} ${Font_color_suffix}"
	echo "==============================" && echo
}

Set_obfs() {
    if [[ ${ver} == "4" ]]; then
    echo -e "配置 OBFS, ${Tip} 无特殊作用不建议启用该项
==================================
${Green_font_prefix} 1.${Font_color_suffix} HTTP ${Green_font_prefix} 2.${Font_color_suffix} 关闭
=================================="
        read -e -p "(默认: 2.关闭): " obfs_input
        [[ -z "${obfs_input}" ]] && obfs_input="2"
        if [[ ${obfs_input} == "1" ]]; then
            obfs="http"
        elif [[ ${obfs_input} == "2" ]]; then
            obfs="off"
        else
            obfs="off"
        fi
    else
        echo -e "配置 OBFS, ${Tip} 无特殊作用不建议启用该项
==================================
${Green_font_prefix} 1.${Font_color_suffix} TLS  ${Green_font_prefix} 2.${Font_color_suffix} HTTP ${Green_font_prefix} 3.${Font_color_suffix} 关闭
=================================="
        read -e -p "(默认: 3.关闭): " obfs_input
        [[ -z "${obfs_input}" ]] && obfs_input="3"
        if [[ ${obfs_input} == "1" ]]; then
            obfs="tls"
        elif [[ ${obfs_input} == "2" ]]; then
            obfs="http"
        elif [[ ${obfs_input} == "3" ]]; then
            obfs="off"
        else
            obfs="off"
        fi
    fi

    echo && echo "=================================="
    echo -e "OBFS 状态: ${Red_background_prefix} ${obfs} ${Font_color_suffix}"
    echo "==================================" && echo
}

Set_ver(){
	echo -e "配置 Snell Server 协议版本${Yellow_font_prefix}[2-4]${Font_color_suffix} 
==================================
${Green_font_prefix} 2.${Font_color_suffix} v2 ${Green_font_prefix} 3.${Font_color_suffix} v3 ${Green_font_prefix} 4.${Font_color_suffix} v4 
=================================="
	read -e -p "(默认: 4.v4): " ver
	[[ -z "${ver}" ]] && ver="4"
	if [[ ${ver} == "2" ]]; then
		ver=2
	elif [[ ${ver} == "3" ]]; then
		ver=3
	elif [[ ${ver} == "4" ]]; then
		ver=4
	else
	     echo -e "${Red_font_prefix}[Warn]${Font_color_suffix} 无效输入! 将取默认值${Yellow_font_prefix} v4${Font_color_suffix}"
		ver=4
	fi
	echo && echo "=================================="
	echo -e "Snell Server 协议版本: ${Red_background_prefix} ${ver} ${Font_color_suffix}"
	echo "==================================" && echo
}

Set_host(){
	echo "请输入 Snell Server 域名 "
	read -e -p "(默认: icloud.com): " host
	[[ -z "${host}" ]] && host=icloud.com
	echo && echo "=============================="
	echo -e "域名 : ${Red_background_prefix} ${host} ${Font_color_suffix}"
	echo "==============================" && echo
}

Set_tfo(){
	echo -e "是否开启 TCP Fast Open ?
==================================
${Green_font_prefix} 1.${Font_color_suffix} 开启  ${Green_font_prefix} 2.${Font_color_suffix} 关闭
=================================="
	read -e -p "(默认: 1.开启): " tfo
	[[ -z "${tfo}" ]] && tfo="1"
	if [[ ${tfo} == "1" ]]; then
		tfo=true
		enable_systfo
	else
		tfo=false
	fi
	echo && echo "=================================="
	echo -e "TCP Fast Open 开启状态: ${Red_background_prefix} ${tfo} ${Font_color_suffix}"
	echo "==================================" && echo
}

Set_dns(){
	echo -e "${Tip} 请输入正确格式的的 DNS, 多条记录以英文逗号隔开, 仅支持 ${Yellow_font_prefix}[v4.1.0b1]${Font_color_suffix} 及以上版本"
	read -e -p "(默认值: 8.8.8.8, 1.1.1.1, 2001:4860:4860::8888): " dns
	[[ -z "${dns}" ]] && dns="8.8.8.8, 1.1.1.1, 2001:4860:4860::8888"
	echo && echo "=================================="
	echo -e "当前 DNS 为：${Red_background_prefix} ${dns} ${Font_color_suffix}"
	echo "==================================" && echo
}

Set(){
	check_installed_status
	echo
	echo -e "请输入要操作配置项的序号,然后回车
==============================
 ${Green_font_prefix}1.${Font_color_suffix}  修改 端口
 ${Green_font_prefix}2.${Font_color_suffix}  修改 密钥
 ${Green_font_prefix}3.${Font_color_suffix}  配置 OBFS
 ${Green_font_prefix}4.${Font_color_suffix}  配置 OBFS 域名
 ${Green_font_prefix}5.${Font_color_suffix}  开关 IPv6 解析
 ${Green_font_prefix}6.${Font_color_suffix}  开关 TCP Fast Open"

Read_config
if [[ -n "${dns}" ]]; then
    echo -e " ${Green_font_prefix}7.${Font_color_suffix}  配置 DNS"
    echo -e " ${Green_font_prefix}8.${Font_color_suffix}  配置 Snell Server 协议版本
==============================
 ${Green_font_prefix}9.${Font_color_suffix}  修改 全部配置"
        echo
	read -e -p "(默认: 取消):" modify
	[[ -z "${modify}" ]] && echo "已取消..." && exit 1
	if [[ "${modify}" == "1" ]]; then
		Read_config
		Set_port
		Set_psk=${psk}
		Set_obfs=${obfs}
		Set_host=${host}
		Set_ipv6=${ipv6}
		Set_tfo=${tfo}
                Set_dns=${dns}
		Set_ver=${ver}
		Write_config
		Restart
	elif [[ "${modify}" == "2" ]]; then
		Read_config
		Set_port=${port}
		Set_psk
		Set_obfs=${obfs}
		Set_host=${host}
		Set_ipv6=${ipv6}
		Set_tfo=${tfo}
                Set_dns=${dns}
		Set_ver=${ver}
		Write_config
		Restart
	elif [[ "${modify}" == "3" ]]; then
		Read_config
		Set_port=${port}
		Set_psk=${psk}
		Set_obfs
		Set_host=${host}
		Set_ipv6=${ipv6}
		Set_tfo=${tfo}
                Set_dns=${dns}
		Set_ver=${ver}
		Write_config
		Restart
	elif [[ "${modify}" == "4" ]]; then
		Read_config
		Set_port=${port}
		Set_psk=${psk}
		Set_obfs=${obfs}
		Set_host
		Set_ipv6=${ipv6}
		Set_tfo=${tfo}
                Set_dns=${dns}
		Set_ver=${ver}
		Write_config
		Restart
	elif [[ "${modify}" == "5" ]]; then
		Read_config
		Set_port=${port}
		Set_psk=${psk}
		Set_obfs=${obfs}
		Set_host=${host}
		Set_ipv6
		Set_tfo=${tfo}
                Set_dns=${dns}
		Set_ver=${ver}
		Write_config
		Restart
	elif [[ "${modify}" == "6" ]]; then
		Read_config
		Set_port=${port}
		Set_psk=${psk}
		Set_obfs=${obfs}
		Set_host=${host}
		Set_ipv6=${ipv6}
		Set_tfo
                Set_dns=${dns}
		Set_ver=${ver}
		Write_config
		Restart
	elif [[ "${modify}" == "7" ]]; then
		Read_config
		Set_port=${port}
		Set_psk=${psk}
		Set_obfs=${obfs}
		Set_host=${host}
		Set_ipv6=${ipv6}
		Set_tfo=${tfo}
		Set_dns
		Set_ver=${ver}
		Write_config
		Restart
	elif [[ "${modify}" == "8" ]]; then
		Read_config
		Set_port=${port}
		Set_psk=${psk}
		Set_obfs=${obfs}
		Set_host=${host}
		Set_ipv6=${ipv6}
		Set_tfo=${tfo}
		Set_dns=${dns}
		Set_ver
		Write_config
		Restart
         elif [[ "${modify}" == "9" ]]; then
                Read_config
		Set_ver
		Edit_port
		Set_psk
		Set_obfs
		if [[ "${obfs}" != "off" ]]; then
                Set_host  
                fi
		Set_ipv6
		Set_tfo
                if [[ ${ver} == "4" ]]; then
		Set_dns
                fi
		Write_config
		Restart
	 else
		echo -e "${Error} 请输入正确的数字${Yellow_font_prefix}[1-9]${Font_color_suffix}" && exit 1
	 fi
else
    echo -e " ${Green_font_prefix}7.${Font_color_suffix}  配置 Snell Server 协议版本
==============================
 ${Green_font_prefix}8.${Font_color_suffix}  修改 全部配置"
        echo
	read -e -p "(默认: 取消):" modify
	[[ -z "${modify}" ]] && echo "已取消..." && exit 1
	if [[ "${modify}" == "1" ]]; then
		Read_config
		Set_port
		Set_psk=${psk}
		Set_obfs=${obfs}
		Set_host=${host}
		Set_ipv6=${ipv6}
		Set_tfo=${tfo}
                Set_dns=${dns}
		Set_ver=${ver}
		Write_config
		Restart
	elif [[ "${modify}" == "2" ]]; then
		Read_config
		Set_port=${port}
		Set_psk
		Set_obfs=${obfs}
		Set_host=${host}
		Set_ipv6=${ipv6}
		Set_tfo=${tfo}
                Set_dns=${dns}
		Set_ver=${ver}
		Write_config
		Restart
	elif [[ "${modify}" == "3" ]]; then
		Read_config
		Set_port=${port}
		Set_psk=${psk}
		Set_obfs
		Set_host=${host}
		Set_ipv6=${ipv6}
		Set_tfo=${tfo}
                Set_dns=${dns}
		Set_ver=${ver}
		Write_config
		Restart
	elif [[ "${modify}" == "4" ]]; then
		Read_config
		Set_port=${port}
		Set_psk=${psk}
		Set_obfs=${obfs}
		Set_host
		Set_ipv6=${ipv6}
		Set_tfo=${tfo}
                Set_dns=${dns}
		Set_ver=${ver}
		Write_config
		Restart
	elif [[ "${modify}" == "5" ]]; then
		Read_config
		Set_port=${port}
		Set_psk=${psk}
		Set_obfs=${obfs}
		Set_host=${host}
		Set_ipv6
		Set_tfo=${tfo}
                Set_dns=${dns}
		Set_ver=${ver}
		Write_config
		Restart
	elif [[ "${modify}" == "6" ]]; then
		Read_config
		Set_port=${port}
		Set_psk=${psk}
		Set_obfs=${obfs}
		Set_host=${host}
		Set_ipv6=${ipv6}
		Set_tfo
                Set_dns=${dns}
		Set_ver=${ver}
		Write_config
		Restart
	elif [[ "${modify}" == "7" ]]; then
		Read_config
		Set_port=${port}
		Set_psk=${psk}
		Set_obfs=${obfs}
		Set_host=${host}
		Set_ipv6=${ipv6}
		Set_tfo=${tfo}
		Set_ver
		if [[ ${ver} == "4" ]]; then
		Set_dns
		fi
		Write_config
		Restart
        elif [[ "${modify}" == "8" ]]; then
                Read_config
		Set_ver
		Edit_port
		Set_psk
		Set_obfs
		if [[ "${obfs}" != "off" ]]; then
                Set_host  
                fi
		Set_ipv6
		Set_tfo
                if [[ ${ver} == "4" ]]; then
		Set_dns
                fi
		Write_config
		Restart
        else
		echo -e "${Error} 请输入正确的数字${Yellow_font_prefix}[1-8]${Font_color_suffix}" && exit 1
        fi
fi
    sleep 3s
    start_menu
}

# 安装 v2
Install_v2(){
	check_root
	echo -e "${Info} 开始设置 配置..."
	Set_port
	Set_psk
	Set_obfs  
     if [[ "${obfs}" != "off" ]]; then
        Set_host  
     fi
	Set_ipv6
	Set_tfo
	echo -e "${Info} 开始安装/配置 依赖..."
	Installation_dependency
	echo -e "${Info} 开始下载/安装..."
	v2_Download
	echo -e "${Info} 开始安装 服务脚本..."
	Service
	echo -e "${Info} 开始写入 配置文件..."
	Write_config
	echo -e "${Info} 所有步骤 安装完毕, 开始启动..."
	Start
    sleep 3s
    start_menu
}

# 安装 v3
Install_v3(){
	check_root
	echo -e "${Info} 开始设置 配置..."
	Set_port
	Set_psk
	Set_obfs  
     if [[ "${obfs}" != "off" ]]; then
        Set_host  
     fi
	Set_ipv6
	Set_tfo
	echo -e "${Info} 开始安装/配置 依赖..."
	Installation_dependency
	echo -e "${Info} 开始下载/安装..."
	v3_Download
	echo -e "${Info} 开始安装 服务脚本..."
	Service
	echo -e "${Info} 开始写入 配置文件..."
	Write_config
	echo -e "${Info} 所有步骤 安装完毕, 开始启动..."
	Start
    sleep 3s
    start_menu
}

# 安装 v4
Install_v4(){
	check_root
	echo -e "${Info} 开始设置 配置..."
	Set_port
	Set_psk
	Set_obfs  
     if [[ "${obfs}" != "off" ]]; then
        Set_host  # 只有当 obfs 不是 "off" 时才调用
     fi
	Set_ipv6
	Set_tfo
        Set_dns
	echo -e "${Info} 开始安装/配置 依赖..."
	Installation_dependency
	echo -e "${Info} 开始下载/安装..."
	v4_Download
	echo -e "${Info} 开始安装 服务脚本..."
	Service
	echo -e "${Info} 开始写入 配置文件..."
	Write_config
	echo -e "${Info} 所有步骤 安装完毕, 开始启动..."
	# print snell server info
     echo -e "—————————————————————————"
     echo -e "${Green_font_prefix}Please copy the following lines to the Surge [Proxy] section:${Font_color_suffix}" 
     if [[ "${obfs}" == "off" ]]; then
            echo "$(curl -s ipinfo.io/city) = snell, $(curl -4s ipinfo.io/ip), ${port}, psk=${psk}, version=${ver}, reuse=true, tfo=${tfo}"
     else
            echo "$(curl -s ipinfo.io/city) = snell, $(curl -4s ipinfo.io/ip), ${port}, psk=${psk}, obfs=${obfs}, obfs-host=${host}, version=${ver}, reuse=true, tfo=${tfo}"
     fi
     echo -e "—————————————————————————" 
	Start
    sleep 3s
    start_menu
}

Start(){
	check_installed_status
	#check_status
	status=`systemctl status snell-server | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1`
	[[ "$status" == "running" ]] && echo -e "${Info} Snell Server 已在运行 !" && exit 1
	systemctl start snell-server
	check_status
	[[ "$status" == "running" ]] && echo -e "${Info} Snell Server 启动成功 !"
    sleep 3s
    start_menu
}

Stop(){
	check_installed_status
	check_status
	[[ ! "$status" == "running" ]] && echo -e "${Error} Snell Server 没有运行,请检查 !" && exit 1
	systemctl stop snell-server
	echo -e "${Info} Snell Server 停止成功 !"
    sleep 3s
    start_menu
}

Restart(){
	check_installed_status
	systemctl restart snell-server
	echo -e "${Info} Snell Server 重启完毕 !"
	sleep 3s
	View
    start_menu
}

Update(){
	check_installed_status
	echo -e "${Info} Snell Server 更新完毕 !"
    sleep 3s
    start_menu
}

Uninstall(){
    check_installed_status
    echo "确定要卸载 Snell Server ? (y/N)"
    echo
    read -e -p "(默认: n):" unyn
    [[ -z ${unyn} ]] && unyn="n"
    if [[ ${unyn} == [Yy] ]]; then
        echo "正在停止 Snell Server 服务..."
        systemctl stop snell-server
        if [[ $? -eq 0 ]]; then
            echo -e "${Blue_font_prefix}Snell Server 服务已停止${Font_color_suffix}"
        else
            echo "停止服务失败,请手动检查"
        fi

        echo "正在禁用 Snell Server 服务..."
        systemctl disable snell-server
        if [[ $? -eq 0 ]]; then
            echo -e "${Blue_font_prefix}Snell Server 服务已禁用${Font_color_suffix}"
        else
            echo "禁用服务失败,请手动检查"
        fi

        echo "正在删除 Snell Server 主程序和配置文件..."
        rm -rf "${FILE}"
        if [[ $? -eq 0 ]]; then
            echo -e "${Blue_font_prefix}Snell Server 主程序删除完成${Font_color_suffix}"
        else
            echo "删除Snell Server 主程序失败,请手动检查"
        fi
        
        rm -rf "${FOLDER}"
        if [[ $? -eq 0 ]]; then
            echo -e "${Blue_font_prefix}Snell Server 配置文件删除完成${Font_color_suffix}"
        else
            echo "删除配置文件失败,请手动检查"
        fi

        echo -e "—————————————————————————"
	echo -e "${Yellow_font_prefix}Snell Server 卸载完成 !${Font_color_suffix}" && echo
    else
        echo && echo "卸载已取消..." && echo
    fi
    sleep 2s
    start_menu
}

getipv4(){
	ipv4=$(wget -qO- -4 -t1 -T2 ipinfo.io/ip)
	if [[ -z "${ipv4}" ]]; then
		ipv4=$(wget -qO- -4 -t1 -T2 api.ip.sb/ip)
		if [[ -z "${ipv4}" ]]; then
			ipv4=$(wget -qO- -4 -t1 -T2 members.3322.org/dyndns/getip)
			if [[ -z "${ipv4}" ]]; then
				ipv4="IPv4_Error"
			fi
		fi
	fi
}

getipv6(){
	ip6=$(wget -qO- -6 -t1 -T2 ifconfig.co)
	if [[ -z "${ip6}" ]]; then
		ip6="IPv6_Error"
	fi
}

View(){
	check_installed_status
	Read_config
	getipv4
	getipv6
	clear && echo
	echo -e "Snell Server 配置信息: "
	echo -e "—————————————————————————"
	[[ "${ipv4}" != "IPv4_Error" ]] && echo -e " 地址\t: ${Green_font_prefix}${ipv4}${Font_color_suffix}"
	[[ "${ip6}" != "IPv6_Error" ]] && echo -e " 地址\t: ${Green_font_prefix}${ip6}${Font_color_suffix}"
	echo -e " 端口\t: ${Green_font_prefix}${port}${Font_color_suffix}"
	echo -e " 密钥\t: ${Green_font_prefix}${psk}${Font_color_suffix}"
	echo -e " OBFS\t: ${Green_font_prefix}${obfs}${Font_color_suffix}"
        if [[ -n "${host}" ]]; then
        echo -e " 域名\t: ${Green_font_prefix}${host}${Font_color_suffix}"
        fi
	echo -e " IPv6\t: ${Green_font_prefix}${ipv6}${Font_color_suffix}"
	echo -e " TFO\t: ${Green_font_prefix}${tfo}${Font_color_suffix}"
        if [[ -n "${dns}" ]]; then
	echo -e " DNS\t: ${Green_font_prefix}${dns}${Font_color_suffix}"
	fi
	echo -e " VER\t: ${Green_font_prefix}${ver}${Font_color_suffix}"
	echo -e "—————————————————————————"
	echo
	before_start_menu
}

Status(){
	echo -e "${Info} 获取 Snell Server 活动日志 ..."
	echo -e "${Tip} ${Yellow_font_prefix}返回主菜单请按 q${Font_color_suffix} "
	systemctl status snell-server
        sleep 1s
	start_menu
}

Journal(){
        echo -e "${Info} 获取 Snell Server 服务日志 ..."
	journalctl -u snell
	sleep 2s 
	start_menu
}

Download_Shadow_TLS(){
echo -e "${Info} 开始下载/安装..."
    # 获取最新的 SHADOW_TLS_VERSION
    SHADOW_TLS_VERSION=$(curl -s "https://api.github.com/repos/ihciah/shadow-tls/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    if [ -z "$SHADOW_TLS_VERSION" ]; then
        echo "${Error} 获取 SHADOW_TLS_VERSION 失败"   
        exit 1
    else echo -e "${Info} 检测到 Shadow-TLS 最新版本为 [ ${SHADOW_TLS_VERSION} ]"    
    fi

    # 下载 shadow-tls 并检查是否成功
    url="https://github.com/ihciah/shadow-tls/releases/download/${SHADOW_TLS_VERSION}/shadow-tls-x86_64-unknown-linux-musl"
    if ! wget "$url" -O ${Shadow_TLS_FILE}; then
        echo -e "${Error} 下载 Shadow-TLS 失败"
        exit 1
    else chmod +x ${Shadow_TLS_FILE}
         echo -e "${Info} Shadow-TLS 主程序下载安装完毕！"        
    fi
}

Install_Shadow_TLS(){
    [[ -e ${Shadow_TLS_FILE} ]] && echo -e "${Error} 检测到 Shadow-TLS 已安装 ,请先卸载再执行安装!" && exit 1
    # 循环直到用户输入有效的 SHADOW_TLS_PORT 值
while true; do
    # 提示用户输入 SHADOW_TLS_PORT 值
    read -e -p "请输入 SHADOW_TLS_PORT 值(1-65535,默认8443): " SHADOW_TLS_PORT

    # 如果用户未输入值,则使用默认值 8443
    [[ -z "${SHADOW_TLS_PORT}" ]] && SHADOW_TLS_PORT="8443"

    # 检查用户输入的值是否有效
    if ! [[ "$SHADOW_TLS_PORT" =~ ^[0-9]+$ ]] || [ "$SHADOW_TLS_PORT" -lt 1 ] || [ "$SHADOW_TLS_PORT" -gt 65535 ]; then
        echo -e "${Error} SHADOW_TLS_PORT值必须是1到65535之间的数字"
        echo
        continue
    fi

    # 检查端口是否被占用
    if ss -tunlp | awk '/tcp/ && $5 ~ /:'"$SHADOW_TLS_PORT"'$/' | grep --color=auto "$SHADOW_TLS_PORT"; then
    #if ss -tunlp | awk '/tcp/ && $5 ~ /:'"$SHADOW_TLS_PORT"'$/ {print $5}' | grep --color=auto .; then
    #if [[ -n $(ss -tunlp | awk '/tcp/ && $5 ~ /:'"${SHADOW_TLS_PORT}"'$/ {print $5}' | sed 's/.*://g') ]]; then
    #if ss -tunlp | awk -v p="$SHADOW_TLS_PORT" '/tcp/ && $5 ~ ":"p"$"' | grep --color=auto "$SHADOW_TLS_PORT" ; then
    #if ss -tulnp | grep --color=auto -w ":${SHADOW_TLS_PORT} "; then
    #if ss -tulnp | grep --color=auto -E ":[[:space:]]*${SHADOW_TLS_PORT}([[:space:]]|$)"; then
    #if ss -tulnp | grep --color=auto -E ":${SHADOW_TLS_PORT}(\s+|$)"; then
        echo -e "${Error} 端口 ${SHADOW_TLS_PORT} 重复或已被其它程序占用,请选择其它端口!" && echo
    else
        # 端口未被占用,退出循环
        break
    fi
done

# 输出最终的 SHADOW_TLS_PORT 值
echo -e "\033[33mSHADOW_TLS_PORT: ${SHADOW_TLS_PORT}\033[0m" && echo

    # 提示用户输入 SHADOW_TLS_SNI 值
read -e -p "请输入 SHADOW_TLS_SNI 值(默认: mensura.cdn-apple.com): " SHADOW_TLS_SNI

    # 如果用户未输入值,则使用默认值 mensura.cdn-apple.com
[[ -z "${SHADOW_TLS_SNI}" ]] && SHADOW_TLS_SNI="mensura.cdn-apple.com"

# 输出最终的 SHADOW_TLS_SNI 值
echo -e "${Yellow_font_prefix}SHADOW_TLS_SNI: ${SHADOW_TLS_SNI}${Font_color_suffix}" && echo


    # 提示用户输入 SHADOW_TLS_PWD 值
read -e -p "请输入 SHADOW_TLS_PWD 值(默认: JsJeWtjiUyJ5yeto): " SHADOW_TLS_PWD

    # 如果用户未输入值,则使用默认值 JsJeWtjiUyJ5yeto
[[ -z "${SHADOW_TLS_PWD}" ]] && SHADOW_TLS_PWD="JsJeWtjiUyJ5yeto"

# 输出最终的 SHADOW_TLS_PWD 值
echo -e "${Yellow_font_prefix}SHADOW_TLS_PWD: ${SHADOW_TLS_PWD}${Font_color_suffix}" && echo

    Download_Shadow_TLS

    # 查看Snell Server配置信息
    Read_config

    # 创建systemd服务文件
    echo -e "${Info} 开始安装 服务脚本..."
    service_file="/etc/systemd/system/shadow-tls.service"
sudo tee "$service_file" > /dev/null <<-EOF
	[Unit]
	Description=Shadow-TLS Server Service
	Documentation=man:sstls-server
	After=network-online.target
	Wants=network-online.target

	[Service]
	Type=simple
	ExecStart=${Shadow_TLS_FILE} --v3 server --listen 0.0.0.0:${SHADOW_TLS_PORT} --server 127.0.0.1:${port} --tls ${SHADOW_TLS_SNI} --password ${SHADOW_TLS_PWD}
	StandardOutput=syslog
	StandardError=syslog
	SyslogIdentifier=shadow-tls

	[Install]
	WantedBy=multi-user.target
EOF

    # 重新加载systemd守护进程并启动服务
    sudo systemctl daemon-reload
    sudo systemctl enable shadow-tls.service
    echo -e "${Info} Shadow-TLS 服务配置完成 !"
    echo -e "${Info} 所有步骤 安装完毕, 开始启动..."

    # 启动服务
    if sudo systemctl start shadow-tls.service; then
        # 提取服务状态
        status=$(systemctl status shadow-tls.service | grep "Active" | awk -F'[()]' '{print $2}')
        if [ "$status" == "running" ]; then
            echo -e "${Info} ${Yellow_font_prefix}Shadow-TLS 服务已成功启动并且正在运行 !${Font_color_suffix}"
            echo -e "—————————————————————————"
            echo -e "${Green_font_prefix}Please copy the following lines to the Surge [Proxy] section:${Font_color_suffix}" 
            if [[ "${obfs}" == "off" ]]; then
            echo "$(curl -s ipinfo.io/city) = snell, $(curl -s ip.sb -4), ${SHADOW_TLS_PORT}, psk=${psk}, version=${ver}, reuse=true, tfo=${tfo}, shadow-tls-password=JsJeWtjiUyJ5yeto, shadow-tls-sni=${SHADOW_TLS_SNI}, shadow-tls-version=3"
            else
            echo "$(curl -s ipinfo.io/city) = snell, $(curl -s ip.sb -4), ${SHADOW_TLS_PORT}, psk=${psk}, obfs=${obfs}, obfs-host=${host}, version=${ver}, reuse=true, tfo=${tfo}, shadow-tls-password=JsJeWtjiUyJ5yeto, shadow-tls-sni=${SHADOW_TLS_SNI}, shadow-tls-version=3"
            fi
            echo -e "—————————————————————————" && exit 1
        else
            echo -e "${Error} 服务未在运行状态"
        fi
    else
        echo -e "${Error} 错误: 启动 shadow-tls 服务失败"
        exit 1
    fi
    sleep 2s
    start_menu
}

Uninstall_Shadow_TLS(){
    check_Shadow_TLS_installed_status
    echo "确定要卸载 Shadow-TLS ? (y/N)"
    echo
    read -e -p "(默认: n):" ynun
    [[ -z "${ynun}" ]] && ynun="n" # 如果用户没有输入,设置默认值为 'n'
    
    if [[ "${ynun}" =~ ^[Yy]$ ]]; then
        # 检查服务是否启动
        if systemctl is-enabled --quiet shadow-tls.service; then
            echo "正在停止 shadow-tls 服务..."
            sudo systemctl stop shadow-tls.service
            if [[ $? -eq 0 ]]; then
            echo -e "${Blue_font_prefix}shadow-tls 服务已停止${Font_color_suffix}"
            else
            echo -e "${Error} 停止服务失败,请手动检查"
            fi
           
            echo "正在禁用 shadow-tls 服务..."
            sudo systemctl disable shadow-tls.service
            if [[ $? -eq 0 ]]; then
            echo -e "${Blue_font_prefix}shadow-tls 服务已禁用${Font_color_suffix}"
            else
            echo -e "${Error} 禁用服务失败,请手动检查"
            fi
        else
            echo -e "${Warn} shadow-tls 服务已被禁用"
            echo "正在停止 shadow-tls 服务..."
            sudo systemctl stop shadow-tls.service
            if [[ $? -eq 0 ]]; then
            echo -e "${Blue_font_prefix}shadow-tls 服务已停止${Font_color_suffix}"
            else
            echo -e "${Warn} 停止服务失败,请手动检查"
            fi
        fi

        # 检查服务文件是否存在并删除
        if [ -f /etc/systemd/system/shadow-tls.service ]; then
            echo "正在删除服务文件..."
            sudo rm /etc/systemd/system/shadow-tls.service
            if [[ $? -eq 0 ]]; then
            echo -e "${Blue_font_prefix}shadow-tls 服务文件已删除${Font_color_suffix}"
            else
            echo -e "${Error} 删除服务文件失败,请手动检查"
            fi
            echo "重新加载 systemd 配置..."
            sudo systemctl daemon-reload
            echo "重置 systemd 失败状态..."
            sudo systemctl reset-failed
        else
            echo -e "${Warn} 服务文件不存在,无需删除"
        fi

        # 删除检查可执行文件
            echo "删除 shadow-tls 可执行文件..."
            sudo rm -rf /usr/local/bin/shadow-tls
            if [[ $? -eq 0 ]]; then
            echo -e "${Blue_font_prefix}shadow-tls 可执行文件删除完成${Font_color_suffix}"
            else
            echo -e "${Error} 删除shadow-tls 可执行文件失败,请手动检查"
            fi
        
	echo -e "—————————————————————————"
        echo -e "${Yellow_font_prefix}Shadow-TLS 服务已成功卸载 !${Font_color_suffix}"
    else
        echo && echo "卸载已取消..." && echo
    fi
    sleep 3s
    start_menu
}

Start_Shadow_TLS(){
     check_Shadow_TLS_installed_status
	check_Shadow_TLS_status
	[[ "$shadow_tls_status" == "running" ]] && echo -e "${Info} Shadow-TLS 已在运行 !" && exit 1
	systemctl start shadow-tls
	check_Shadow_TLS_status
	[[ "$shadow_tls_status" == "running" ]] && echo -e "${Info} Shadow-TLS 启动成功 !"
    sleep 3s
    start_menu
}

Stop_Shadow_TLS(){
     check_Shadow_TLS_installed_status
	check_Shadow_TLS_status
	[[ !"$shadow_tls_status" == "running" ]] && echo -e "${Error} Shadow-TLS 未在运行,请检查 !" && exit 1
	systemctl stop shadow-tls
	echo -e "${Info} Shadow-TLS 停止成功 !"
    sleep 3s
    start_menu
}

Restart_Shadow_TLS(){
     check_Shadow_TLS_installed_status
	systemctl restart shadow-tls
	echo -e "${Info} Shadow-TLS 重启完毕 !"
	sleep 3s
     start_menu
}

Status_Shadow_TLS(){
	echo -e "${Info} 获取 Shadow_TLS 运行状态 ..."
	#if systemctl is-enabled --quiet shadow-tls.service; then
        if [[ -e ${Shadow_TLS_FILE} ]]; then
	echo -e "${Tip} ${Yellow_font_prefix}返回主菜单请按 q${Font_color_suffix} "
	else
            echo -e "${Error} ${Red_font_prefix}shadow-tls 服务未安装${Font_color_suffix}"
	fi
	systemctl status shadow-tls
        sleep 1s
	start_menu
}

Journal_Shadow_TLS(){
        echo -e "${Info} 获取 Shadow-TLS 服务日志 ..."
        echo -e "${Tip} ${Yellow_font_prefix}返回主菜单请按 q${Font_color_suffix} "
	journalctl -u shadow-tls
	start_menu
}

check_Shadow_TLS_installed_status(){
	[[ ! -e ${Shadow_TLS_FILE} ]] && echo -e "${Error} Shadow-TLS 没有安装,请检查 !" && exit 1
}

check_Shadow_TLS_status(){
	shadow_tls_status=`systemctl status shadow-tls.service | grep "Active" | awk -F'[()]' '{print $2}'`
}

View_Shadow_TLS(){
     check_Shadow_TLS_installed_status
     Read_Shadow_TLS_config
     clear && echo
	echo -e "Shadow TLS 服务文件："
	echo -e "—————————————————————————"
	cat /etc/systemd/system/shadow-tls.service
	echo -e "—————————————————————————"
	echo
	before_start_menu
}

Read_Shadow_TLS_config() {
    # 检查 /etc/systemd/system/shadow-tls.service 文件是否存在
    if [[ ! -e "/etc/systemd/system/shadow-tls.service" ]]; then
        echo -e "${Error} Shadow TLS 服务文件不存在!"
        exit 1
    fi

    # 从 shadow-tls.service 文件中提取 ExecStart 行
    ExecStartLine=$(grep -E "^ExecStart=" /etc/systemd/system/shadow-tls.service)
   
    # 使用 awk 提取端口号
    SHADOW_TLS_PORT=$(echo "$ExecStartLine" | awk -F '--listen | --server' '{print $2}' | awk -F: '{print $2}')
    
    # 使用 awk 提取 SNI
    SHADOW_TLS_SNI=$(echo "$ExecStartLine" | awk -F '--tls ' '{print $2}' | awk '{print $1}')

    # 使用 awk 提取 --password 之后的部分
    SHADOW_TLS_PWD=$(echo "$ExecStartLine" | awk -F '--password ' '{print $2}' | awk '{print $1}')
}


Edit_Shadow_TLS_PORT(){
# 循环直到用户输入有效的 SHADOW_TLS_PORT 值
while true; do
    # 提示用户输入 SHADOW_TLS_PORT 值
    read -e -p "请输入 SHADOW_TLS_PORT 值(1-65535,默认8443): " SHADOW_TLS_PORT

    # 如果用户未输入值,则使用默认值 8443
    [[ -z "${SHADOW_TLS_PORT}" ]] && SHADOW_TLS_PORT="8443"

    # 检查用户输入的值是否有效
    if ! [[ "$SHADOW_TLS_PORT" =~ ^[0-9]+$ ]] || [ "$SHADOW_TLS_PORT" -lt 1 ] || [ "$SHADOW_TLS_PORT" -gt 65535 ]; then
        echo -e "${Error} SHADOW_TLS_PORT值必须是1到65535之间的数字"
        echo
        continue
    fi

    # 检查端口是否被占用
    if ss -tunlp | awk '/tcp/ && $5 ~ /:'"$SHADOW_TLS_PORT"'$/' | grep --color=auto "$SHADOW_TLS_PORT"; then
        echo -e "${Error} 端口 ${SHADOW_TLS_PORT} 重复或已被其它程序占用,请选择其它端口!" && echo
    else
        # 端口未被占用,退出循环
        break
    fi
done

    echo -e "\033[33mSHADOW_TLS_PORT: ${SHADOW_TLS_PORT}\033[0m" & echo


# 创建systemd服务文件
sudo tee /etc/systemd/system/shadow-tls.service > /dev/null <<-EOF
	[Unit]
	Description=Shadow-TLS Server Service
	Documentation=man:sstls-server
	After=network-online.target
	Wants=network-online.target

	[Service]
	Type=simple
	ExecStart=${Shadow_TLS_FILE} --v3 server --listen 0.0.0.0:${SHADOW_TLS_PORT} --server 127.0.0.1:${port} --tls ${SHADOW_TLS_SNI} --password ${SHADOW_TLS_PWD}
	StandardOutput=syslog
	StandardError=syslog
	SyslogIdentifier=shadow-tls

	[Install]
	WantedBy=multi-user.target
EOF

    # 重新加载systemd守护进程
    sudo systemctl daemon-reload

    # 重启服务
    if sudo systemctl restart shadow-tls.service; then
        # 提取服务状态
        shadow_tls_status=$(systemctl status shadow-tls.service | grep "Active" | awk -F'[()]' '{print $2}')
        if [ "$shadow_tls_status" == "running" ]; then
            echo -e "${Info} ${Green_font_prefix}服务已成功重启并且正在运行 !${Font_color_suffix}"
            echo -e "—————————————————————————"
            echo -e "${Green_font_prefix}Please copy the following lines to the Surge [Proxy] section:${Font_color_suffix}" 
            if [[ "${obfs}" == "off" ]]; then
            echo "$(curl -s ipinfo.io/city) = snell, $(curl -s ip.sb -4), ${SHADOW_TLS_PORT}, psk=${psk}, version=${ver}, reuse=true, tfo=${tfo}, shadow-tls-password=${SHADOW_TLS_PWD}, shadow-tls-sni=${SHADOW_TLS_SNI}, shadow-tls-version=3"
            else
            echo "$(curl -s ipinfo.io/city) = snell, $(curl -s ip.sb -4), ${SHADOW_TLS_PORT}, psk=${psk}, obfs=${obfs}, obfs-host=${host}, version=${ver}, reuse=true, tfo=${tfo}, shadow-tls-password=${SHADOW_TLS_PWD}, shadow-tls-sni=${SHADOW_TLS_SNI}, shadow-tls-version=3"
            fi
            echo -e "—————————————————————————" && exit 1
        else
            echo -e "${Error} 服务未在运行状态,请手动检查"
            systemctl status shadow-tls.service
        fi
    else
        echo -e "${Error} 错误: 启动 shadow-tls 服务失败"
	systemctl status shadow-tls.service
        exit 1
    fi
}

Edit_Shadow_TLS_SNI(){
# 提示用户输入 SHADOW_TLS_SNI 值
read -e -p "请输入 SHADOW_TLS_SNI 值(默认: mensura.cdn-apple.com): " SHADOW_TLS_SNI

# 如果用户未输入值,则使用默认值 8443
[[ -z "${SHADOW_TLS_SNI}" ]] && SHADOW_TLS_SNI="mensura.cdn-apple.com"

    echo -e "${Yellow_font_prefix}SHADOW_TLS_SNI: ${SHADOW_TLS_SNI}${Font_color_suffix}" && echo


# 创建systemd服务文件
sudo tee /etc/systemd/system/shadow-tls.service > /dev/null <<-EOF
	[Unit]
	Description=Shadow-TLS Server Service
	Documentation=man:sstls-server
	After=network-online.target
	Wants=network-online.target

	[Service]
	Type=simple
	ExecStart=${Shadow_TLS_FILE} --v3 server --listen 0.0.0.0:${SHADOW_TLS_PORT} --server 127.0.0.1:${port} --tls ${SHADOW_TLS_SNI} --password ${SHADOW_TLS_PWD}
	StandardOutput=syslog
	StandardError=syslog
	SyslogIdentifier=shadow-tls

	[Install]
	WantedBy=multi-user.target
EOF

    # 重新加载systemd守护进程
    sudo systemctl daemon-reload

    # 重启服务
    if sudo systemctl restart shadow-tls.service; then
        # 提取服务状态
        shadow_tls_status=$(systemctl status shadow-tls.service | grep "Active" | awk -F'[()]' '{print $2}')
        if [ "$shadow_tls_status" == "running" ]; then
            echo -e "${Info} ${Green_font_prefix}服务已成功重启并且正在运行 !${Font_color_suffix}"
            echo -e "—————————————————————————"
            echo -e "${Green_font_prefix}Please copy the following line to the Surge [Proxy] section:${Font_color_suffix}" 
            if [[ "${obfs}" == "off" ]]; then
            echo "$(curl -s ipinfo.io/city) = snell, $(curl -s ip.sb -4), ${SHADOW_TLS_PORT}, psk=${psk}, version=${ver}, reuse=true, tfo=${tfo}, shadow-tls-password=${SHADOW_TLS_PWD}, shadow-tls-sni=${SHADOW_TLS_SNI}, shadow-tls-version=3"
            else
            echo "$(curl -s ipinfo.io/city) = snell, $(curl -s ip.sb -4), ${SHADOW_TLS_PORT}, psk=${psk}, obfs=${obfs}, obfs-host=${host}, version=${ver}, reuse=true, tfo=${tfo}, shadow-tls-password=${SHADOW_TLS_PWD}, shadow-tls-sni=${SHADOW_TLS_SNI}, shadow-tls-version=3"
            fi
            echo -e "—————————————————————————" && exit 1
        else
            echo -e "${Error} 服务未在运行状态,请手动检查"
            systemctl status shadow-tls.service
        fi
    else
        echo -e "${Error} 错误: 启动 shadow-tls 服务失败"
	systemctl status shadow-tls.service
        exit 1
    fi
}

Edit_Shadow_TLS_PWD(){
# 提示用户输入 SHADOW_TLS_PWD 值
read -e -p "请输入 SHADOW_TLS_PWD 值(默认: JsJeWtjiUyJ5yeto): " SHADOW_TLS_PWD

# 如果用户未输入值,则使用默认值 JsJeWtjiUyJ5yeto
[[ -z "${SHADOW_TLS_PWD}" ]] && SHADOW_TLS_PWD="JsJeWtjiUyJ5yeto"

    echo -e "${Yellow_font_prefix}SHADOW_TLS_PWD: ${SHADOW_TLS_PWD}${Font_color_suffix}" && echo


# 创建systemd服务文件
sudo tee /etc/systemd/system/shadow-tls.service > /dev/null <<-EOF
	[Unit]
	Description=Shadow-TLS Server Service
	Documentation=man:sstls-server
	After=network-online.target
	Wants=network-online.target

	[Service]
	Type=simple
	ExecStart=${Shadow_TLS_FILE} --v3 server --listen 0.0.0.0:${SHADOW_TLS_PORT} --server 127.0.0.1:${port} --tls ${SHADOW_TLS_SNI} --password ${SHADOW_TLS_PWD}
	StandardOutput=syslog
	StandardError=syslog
	SyslogIdentifier=shadow-tls

	[Install]
	WantedBy=multi-user.target
EOF

    # 重新加载systemd守护进程
    sudo systemctl daemon-reload

    # 重启服务
    if sudo systemctl restart shadow-tls.service; then
        # 提取服务状态
        shadow_tls_status=$(systemctl status shadow-tls.service | grep "Active" | awk -F'[()]' '{print $2}')
        if [ "$shadow_tls_status" == "running" ]; then
            echo -e "${Info} ${Green_font_prefix}服务已成功重启并且正在运行 !${Font_color_suffix}"
            echo -e "—————————————————————————"
            echo -e "${Green_font_prefix}Please copy the following lines to the Surge [Proxy] section:${Font_color_suffix}" 
            if [[ "${obfs}" == "off" ]]; then
            echo "$(curl -s ipinfo.io/city) = snell, $(curl -s ip.sb -4), ${SHADOW_TLS_PORT}, psk=${psk}, version=${ver}, reuse=true, tfo=${tfo}, shadow-tls-password=${SHADOW_TLS_PWD}, shadow-tls-sni=${SHADOW_TLS_SNI}, shadow-tls-version=3"
            else
            echo "$(curl -s ipinfo.io/city) = snell, $(curl -s ip.sb -4), ${SHADOW_TLS_PORT}, psk=${psk}, obfs=${obfs}, obfs-host=${host}, version=${ver}, reuse=true, tfo=${tfo}, shadow-tls-password=${SHADOW_TLS_PWD}, shadow-tls-sni=${SHADOW_TLS_SNI}, shadow-tls-version=3"
            fi
            echo -e "—————————————————————————" && exit 1
        else
            echo -e "${Error} 服务未在运行状态,请手动检查"
            systemctl status shadow-tls.service
        fi
    else
        echo -e "${Error} 错误: 启动 shadow-tls 服务失败"
	systemctl status shadow-tls.service
        exit 1
    fi
}

ReInstall_Shadow_TLS(){
    # 循环直到用户输入有效的 SHADOW_TLS_PORT 值
while true; do
    # 提示用户输入 SHADOW_TLS_PORT 值
    read -e -p "请输入 SHADOW_TLS_PORT 值(1-65535,默认8443): " SHADOW_TLS_PORT

    # 如果用户未输入值,则使用默认值 8443
    [[ -z "${SHADOW_TLS_PORT}" ]] && SHADOW_TLS_PORT="8443"

    # 检查用户输入的值是否有效
    if ! [[ "$SHADOW_TLS_PORT" =~ ^[0-9]+$ ]] || [ "$SHADOW_TLS_PORT" -lt 1 ] || [ "$SHADOW_TLS_PORT" -gt 65535 ]; then
        echo -e "${Error} SHADOW_TLS_PORT值必须是1到65535之间的数字" && echo
        continue
    fi
    # 如果输入有效，退出循环
    break

done

# 输出最终的 SHADOW_TLS_PORT 值
echo -e "\033[33mSHADOW_TLS_PORT: ${SHADOW_TLS_PORT}\033[0m" && echo

    # 提示用户输入 SHADOW_TLS_SNI 值
read -e -p "请输入 SHADOW_TLS_SNI 值(默认: mensura.cdn-apple.com): " SHADOW_TLS_SNI

    # 如果用户未输入值,则使用默认值 mensura.cdn-apple.com
[[ -z "${SHADOW_TLS_SNI}" ]] && SHADOW_TLS_SNI="mensura.cdn-apple.com"

# 输出最终的 SHADOW_TLS_SNI 值
echo -e "${Yellow_font_prefix}SHADOW_TLS_SNI: ${SHADOW_TLS_SNI}${Font_color_suffix}" && echo


    # 提示用户输入 SHADOW_TLS_PWD 值
read -e -p "请输入 SHADOW_TLS_PWD 值(默认: JsJeWtjiUyJ5yeto): " SHADOW_TLS_PWD

    # 如果用户未输入值,则使用默认值 JsJeWtjiUyJ5yeto
[[ -z "${SHADOW_TLS_PWD}" ]] && SHADOW_TLS_PWD="JsJeWtjiUyJ5yeto"

# 输出最终的 SHADOW_TLS_PWD 值
echo -e "${Yellow_font_prefix}SHADOW_TLS_PWD: ${SHADOW_TLS_PWD}${Font_color_suffix}" && echo


    # 查看Snell Server配置信息
    Read_config

    # 创建systemd服务文件
    service_file="/etc/systemd/system/shadow-tls.service"
sudo tee "$service_file" > /dev/null <<-EOF
	[Unit]
	Description=Shadow-TLS Server Service
	Documentation=man:sstls-server
	After=network-online.target
	Wants=network-online.target

	[Service]
	Type=simple
	ExecStart=${Shadow_TLS_FILE} --v3 server --listen 0.0.0.0:${SHADOW_TLS_PORT} --server 127.0.0.1:${port} --tls ${SHADOW_TLS_SNI} --password ${SHADOW_TLS_PWD}
	StandardOutput=syslog
	StandardError=syslog
	SyslogIdentifier=shadow-tls

	[Install]
	WantedBy=multi-user.target
EOF

    # 重新加载systemd守护进程
    sudo systemctl daemon-reload

    # 重启服务
    if sudo systemctl restart shadow-tls.service; then
        # 提取服务状态
        status=$(systemctl status shadow-tls.service | grep "Active" | awk -F'[()]' '{print $2}')
        if [ "$status" == "running" ]; then
            echo -e "${Info} ${Yellow_font_prefix}Shadow-TLS 服务已成功重启并且正在运行 !${Font_color_suffix}"
            echo -e "—————————————————————————"
            echo -e "${Green_font_prefix}Please copy the following lines to the Surge [Proxy] section:${Font_color_suffix}" 
            if [[ "${obfs}" == "off" ]]; then
            echo "$(curl -s ipinfo.io/city) = snell, $(curl -s ip.sb -4), ${SHADOW_TLS_PORT}, psk=${psk}, version=${ver}, reuse=true, tfo=${tfo}, shadow-tls-password=JsJeWtjiUyJ5yeto, shadow-tls-sni=${SHADOW_TLS_SNI}, shadow-tls-version=3"
            else
            echo "$(curl -s ipinfo.io/city) = snell, $(curl -s ip.sb -4), ${SHADOW_TLS_PORT}, psk=${psk}, obfs=${obfs}, obfs-host=${host}, version=${ver}, reuse=true, tfo=${tfo}, shadow-tls-password=JsJeWtjiUyJ5yeto, shadow-tls-sni=${SHADOW_TLS_SNI}, shadow-tls-version=3"
            fi
            echo -e "—————————————————————————" && exit 1
        else
            echo -e "${Error} 服务未在运行状态"
        fi
    else
        echo -e "${Error} 错误: 启动 shadow-tls 服务失败"
        systemctl status shadow-tls.service
        exit 1
    fi
    sleep 2s
    start_menu
}

Set_Shadow_TLS(){
	check_Shadow_TLS_installed_status
	echo && echo -e "你想要做什么？
==============================
 ${Green_font_prefix}1.${Font_color_suffix}  修改Shadow-TLS 端口
 ${Green_font_prefix}2.${Font_color_suffix}  修改Shadow-TLS SNI
 ${Green_font_prefix}3.${Font_color_suffix}  修改Shadow-TLS PASSWORD
 ==============================
 ${Green_font_prefix}4.${Font_color_suffix}  修改Shadow-TLS 全部配置"  && echo
	read -e -p "(默认: 取消):" modify
	[[ -z "${modify}" ]] && echo "已取消..." && exit 1
	if [[ "${modify}" == "1" ]]; then
	Read_config
	Read_Shadow_TLS_config
	Edit_Shadow_TLS_PORT
	elif [[ "${modify}" == "2" ]]; then
	Read_config
	Read_Shadow_TLS_config
	Edit_Shadow_TLS_SNI
	elif [[ "${modify}" == "3" ]]; then
	Read_config
	Read_Shadow_TLS_config
	Edit_Shadow_TLS_PWD
        elif [[ "${modify}" == "4" ]]; then
        ReInstall_Shadow_TLS
	else
		echo -e "${Error} 请输入正确的数字${Yellow_font_prefix}[1-4]${Font_color_suffix}" && exit 1
	fi
    sleep 3s
    start_menu
}


Update_Shell(){
	echo -e "当前版本为 [ ${sh_ver} ],开始检测最新版本..."
	sh_new_ver=$(wget --no-check-certificate -qO- "https://raw.githubusercontent.com/chentianqihub/surge/main/scripts/snell%2Bstls_new.sh"|grep 'sh_ver="'|awk -F "=" '{print $NF}'|sed 's/\"//g'|head -1)
	[[ -z ${sh_new_ver} ]] && echo -e "${Error} 检测最新版本失败 !" && start_menu
	if [[ ${sh_new_ver} != ${sh_ver} ]]; then
		echo -e "发现新版本[ ${sh_new_ver} ],是否更新？[Y/n]"
		read -p "(默认: y):" yn
		[[ -z "${yn}" ]] && yn="y"
		if [[ ${yn} == [Yy] ]]; then
			wget -O snell+stls_new.sh --no-check-certificate https://raw.githubusercontent.com/chentianqihub/surge/main/scripts/snell%2Bstls_new.sh && chmod +x snell+stls_new.sh
			echo -e "脚本已更新为最新版本[ ${sh_new_ver} ] !"
			echo -e "3s后执行新脚本"
            sleep 3s
            bash snell+stls_new.sh
		else
			echo && echo "	已取消..." && echo
            sleep 3s
            start_menu
		fi
	else
		echo -e "${Green_font_prefix}当前已是最新版本[v${sh_new_ver}] !${Font_color_suffix}"
		sleep 2s
        start_menu
	fi
	sleep 3s
    	bash snell+stls_new.sh
}
before_start_menu() {
    echo && echo -n -e "${yellow}* 按回车返回主菜单 *${plain}" && read temp
    start_menu
}

start_menu(){
clear
check_root
check_sys
sysArch
action=$1
	echo && echo -e "  
==============================
Snell Server 管理脚本 ${Red_font_prefix}[v${sh_ver}]${Font_color_suffix}
==============================
 ${Green_font_prefix} 0.${Font_color_suffix} 更新脚本
——————————————————————————————
 ${Green_font_prefix} 1.${Font_color_suffix} 安装 Snell Server
 ${Green_font_prefix} 2.${Font_color_suffix} 卸载 Snell Server
——————————————————————————————
 ${Green_font_prefix} 3.${Font_color_suffix} 启动 Snell Server
 ${Green_font_prefix} 4.${Font_color_suffix} 停止 Snell Server
 ${Green_font_prefix} 5.${Font_color_suffix} 重启 Snell Server
——————————————————————————————
 ${Green_font_prefix} 6.${Font_color_suffix} 设置 Snell配置信息
 ${Green_font_prefix} 7.${Font_color_suffix} 查看 Snell配置信息
 ${Green_font_prefix} 8.${Font_color_suffix} 查看 Snell运行状态
 ${Green_font_prefix} 9.${Font_color_suffix} 查看 Snell实时日志
——————————————————————————————
 ${Green_font_prefix} 10.${Font_color_suffix} 退出脚本
——————————————————————————————
 ${Green_font_prefix} 11.${Font_color_suffix} 安装 Shadow-TLS
 ${Green_font_prefix} 12.${Font_color_suffix} 卸载 Shadow-TLS
——————————————————————————————
 ${Green_font_prefix} 13.${Font_color_suffix} 启动 Shadow-TLS
 ${Green_font_prefix} 14.${Font_color_suffix} 停止 Shadow-TLS
 ${Green_font_prefix} 15.${Font_color_suffix} 重启 Shadow-TLS
——————————————————————————————
 ${Green_font_prefix} 16.${Font_color_suffix} 查看 Shadow-TLS运行状态
 ${Green_font_prefix} 17.${Font_color_suffix} 查看 Shadow-TLS实时日志
 ${Green_font_prefix} 18.${Font_color_suffix} 查看 Shadow-TLS服务文件
 ${Green_font_prefix} 19.${Font_color_suffix} 设置 Shadow-TLS配置信息
==============================" && echo
	if [[ -e ${FILE} ]]; then
	        #check_status
		status=`systemctl status snell-server | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1`
                version=$(cat ${CONF}|grep 'version = '|awk -F 'version = ' '{print $NF}')
                getVer > /dev/null 2>&1
		if [[ "$version" == "4" ]]; then
                   if [[ "$status" == "running" ]]; then
                       echo -e " 当前Snell状态: ${Green_font_prefix}已安装${Yellow_font_prefix}[v${new_ver}]${Font_color_suffix}并${Green_font_prefix}已启动${Font_color_suffix}"
                   else
                       echo -e " 当前Snell状态: ${Green_font_prefix}已安装${Yellow_font_prefix}[v${new_ver}]${Font_color_suffix}但${Red_font_prefix}未启动${Font_color_suffix}"
                   fi
                else
                   if [[ "$status" == "running" ]]; then
                       echo -e " 当前Snell状态: ${Green_font_prefix}已安装${Yellow_font_prefix}[v$(cat ${CONF} | grep 'version = ' | awk -F 'version = ' '{print $NF}')]${Font_color_suffix}并${Green_font_prefix}已启动${Font_color_suffix}"
                   else
                       echo -e " 当前Snell状态: ${Green_font_prefix}已安装${Yellow_font_prefix}[v$(cat ${CONF} | grep 'version = ' | awk -F 'version = ' '{print $NF}')]${Font_color_suffix}但${Red_font_prefix}未启动${Font_color_suffix}"
                   fi
                fi
	else
		echo -e " 当前Snell状态: ${Red_font_prefix}未安装${Font_color_suffix}"
	fi
	
	if [[ -e ${Shadow_TLS_FILE} ]]; then
		check_Shadow_TLS_status > /dev/null 2>&1
		SHADOW_TLS_VERSION=$(curl -s "https://api.github.com/repos/ihciah/shadow-tls/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
		if [[ "$shadow_tls_status" == "running" ]]; then
			echo -e " 当前Shadow-TLS状态: ${Green_font_prefix}已安装${Yellow_font_prefix}[${SHADOW_TLS_VERSION}]${Font_color_suffix}并${Green_font_prefix}已启动${Font_color_suffix}"
		else
			echo -e " 当前Shadow-TLS状态: ${Green_font_prefix}已安装${Yellow_font_prefix}[${SHADOW_TLS_VERSION}]${Font_color_suffix}但${Red_font_prefix}未启动${Font_color_suffix}"
		fi
	else
		echo -e " 当前Shadow-TLS状态: ${Red_font_prefix}未安装${Font_color_suffix}"
	fi
	echo
	read -e -p " 请输入数字[0-19]（默认值: 1）: " num
	
     # 如果用户未输入值,则使用默认值1
     [[ -z "$num" ]] && num=1
	
	case "$num" in
		0)
		Update_Shell
		;;
		1)
		Install
		;;
		2)
		Uninstall
		;;
		3)
		Start
		;;
		4)
		Stop
		;;
		5)
		Restart
		;;
		6)
		Set
		;;
		7)
		View
		;;
		8)
		Status
		;;
		9)
		Journal
		;;
		10)
		exit 1
		;;
                11)
                Install_Shadow_TLS
                ;;
                12)
                Uninstall_Shadow_TLS
                ;;
                13)
                Start_Shadow_TLS
                ;;
                14)
                Stop_Shadow_TLS
                ;;
                15)
                Restart_Shadow_TLS
                ;;
                16)
                Status_Shadow_TLS
                ;;
                17)
                Journal_Shadow_TLS
                ;;
                18)
                View_Shadow_TLS
                ;;
                19)
                Set_Shadow_TLS
                ;;
		*)
		echo -e "${Error} 请输入正确数字${Yellow_font_prefix}[0-19]${Font_color_suffix}"
		;;
	esac
}
start_menu
