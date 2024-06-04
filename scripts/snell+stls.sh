#!/usr/bin/env bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

sh_ver="1.6.0"
filepath=$(cd "$(dirname "$0")"; pwd)
file_1=$(echo -e "${filepath}"|awk -F "$0" '{print $1}')
FOLDER="/etc/snell/"
FILE="/usr/local/bin/snell-server"
CONF="/etc/snell/config.conf"
Now_ver_File="/etc/snell/ver.txt"
Local="/etc/sysctl.d/local.conf"
obfs=""   # 全局变量初始化

Green_font_prefix="\033[32m" && Red_font_prefix="\033[31m" && Green_background_prefix="\033[42;37m" && Red_background_prefix="\033[41;37m" && Font_color_suffix="\033[0m" && Yellow_font_prefix="\033[0;33m"
Info="${Green_font_prefix}[信息]${Font_color_suffix}"
Error="${Red_font_prefix}[错误]${Font_color_suffix}"
Tip="${Yellow_font_prefix}[注意]${Font_color_suffix}"
Warn="${Yellow_font_prefix}[Warn]${Font_color_suffix}"

check_root(){
	[[ $EUID != 0 ]] && echo -e "${Error} 当前非ROOT账号(或没有ROOT权限)，无法继续操作，请更换ROOT账号或使用 ${Green_background_prefix}sudo su${Font_color_suffix} 命令获取临时ROOT权限（执行后可能会提示输入当前账号的密码）。" && exit 1
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
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control = bbr" >>/etc/sysctl.d/local.conf && sysctl --system >/dev/null 2>&1
	else
		echo -e "$Error系统内核版本过低，无法支持 TCP Fast Open ！"
	fi
}

check_installed_status(){
	[[ ! -e ${FILE} ]] && echo -e "${Error} Snell Server 没有安装，请检查 !" && exit 1
}

check_status(){
	#status=`systemctl status snell-server | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1`
	status=$(systemctl status shadow-tls.service | grep "Active" | awk -F'[()]' '{print $2}')
}

# v2 备用源
v2_Download() {
	echo -e "${Info} 默认开始下载${Yellow_font_prefix}v2 备用源版${Font_color_suffix}Snell Server ……"
	wget --no-check-certificate -N "https://raw.githubusercontent.com/xOS/Others/master/snell/v2.0.6/snell-server-v2.0.6-linux-${arch}.zip"
	if [[ ! -e "snell-server-v2.0.6-linux-${arch}.zip" ]]; then
		echo -e "${Error} Snell Server${Yellow_font_prefix}v2 备用源版${Font_color_suffix}下载失败！"
		return 1 && exit 1
	else
		unzip -o "snell-server-v2.0.6-linux-${arch}.zip"
	fi
	if [[ ! -e "snell-server" ]]; then
		echo -e "${Error} Snell Server${Yellow_font_prefix}v2 备用源版${Font_color_suffix}解压失败 !"
		echo -e "${Error} Snell Server${Yellow_font_prefix}v2 备用源版${Font_color_suffix}安装失败 !"
		return 1 && exit 1
	else
		rm -rf "snell-server-v2.0.6-linux-${arch}.zip"
		chmod +x snell-server
		mv -f snell-server "${FILE}"
		echo "v2.0.6" > ${Now_ver_File}
		echo -e "${Info} Snell Server 主程序下载安装完毕！"
		return 0
	fi
}

# v3 备用源
v3_Download() {
	echo -e "${Info} 试图请求${Yellow_font_prefix}v3 备用源版${Font_color_suffix}Snell Server ……"
	wget --no-check-certificate -N "https://raw.githubusercontent.com/xOS/Others/master/snell/v3.0.1/snell-server-v3.0.1-linux-${arch}.zip"
	if [[ ! -e "snell-server-v3.0.1-linux-${arch}.zip" ]]; then
		echo -e "${Error} Snell Server${Yellow_font_prefix}v3 备用源版${Font_color_suffix}下载失败！"
		return 1 && exit 1
	else
		unzip -o "snell-server-v3.0.1-linux-${arch}.zip"
	fi
	if [[ ! -e "snell-server" ]]; then
		echo -e "${Error} Snell Server${Yellow_font_prefix}v3 备用源版${Font_color_suffix}解压失败 !"
		echo -e "${Error} Snell Server${Yellow_font_prefix}v3 备用源版${Font_color_suffix}安装失败 !"
		return 1 && exit 1
	else
		rm -rf "snell-server-v3.0.1-linux-${arch}.zip"
		chmod +x snell-server
		mv -f snell-server "${FILE}"
		echo "v3.0.1" > ${Now_ver_File}
		echo -e "${Info} Snell Server 主程序下载安装完毕！"
		return 0
	fi
}

# v4 官方源
v4_Download(){
	echo -e "${Info} 试图请求${Yellow_font_prefix}v4 官网源版${Font_color_suffix}Snell Server ……"
	wget --no-check-certificate -N "https://dl.nssurge.com/snell/snell-server-v4.0.1-linux-${arch}.zip"
	if [[ ! -e "snell-server-v4.0.1-linux-${arch}.zip" ]]; then
		echo -e "${Error} Snell Server${Yellow_font_prefix}v4 官网源版${Font_color_suffix}下载失败！"
		return 1 && exit 1
	else
		unzip -o "snell-server-v4.0.1-linux-${arch}.zip"
	fi
	if [[ ! -e "snell-server" ]]; then
		echo -e "${Error} Snell Server${Yellow_font_prefix}v4 官网源版${Font_color_suffix}解压失败 !"
		echo -e "${Error} Snell Server${Yellow_font_prefix}v4 官网源版${Font_color_suffix}安装失败 !"
		return 1 && exit 1
	else
		rm -rf "snell-server-v4.0.1-linux-${arch}.zip"
		chmod +x snell-server
		mv -f snell-server "${FILE}"
		echo "v4.0.1" > ${Now_ver_File}
		echo -e "${Info} Snell Server 主程序下载安装完毕！"
		return 0
	fi
}

# 安装
Install() {
	if [[ ! -e "${FOLDER}" ]]; then
		mkdir "${FOLDER}"
	else
		[[ -e "${FILE}" ]] && rm -rf "${FILE}"
	fi
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
version = ${ver}
EOF
}
Read_config(){
	[[ ! -e ${CONF} ]] && echo -e "${Error} Snell Server 配置文件不存在 !" && exit 1
	ipv6=$(cat ${CONF}|grep 'ipv6 = '|awk -F 'ipv6 = ' '{print $NF}')
	port=$(cat ${CONF}|grep ':'|awk -F ':' '{print $NF}')
	psk=$(cat ${CONF}|grep 'psk = '|awk -F 'psk = ' '{print $NF}')
	obfs=$(cat ${CONF}|grep 'obfs = '|awk -F 'obfs = ' '{print $NF}')
	host=$(cat ${CONF}|grep 'obfs-host = '|awk -F 'obfs-host = ' '{print $NF}')
	tfo=$(cat ${CONF}|grep 'tfo = '|awk -F 'tfo = ' '{print $NF}')
	ver=$(cat ${CONF}|grep 'version = '|awk -F 'version = ' '{print $NF}')
}
Set_port(){
	while true
		do
		echo -e "${Tip} 本步骤不涉及系统防火墙端口操作，请手动放行相应端口！"
		echo -e "请输入 Snell Server 端口${Yellow_font_prefix}[1-65535]${Font_color_suffix}"
		read -e -p "(默认: 2345):" port
		[[ -z "${port}" ]] && port="2345"
		echo $((${port}+0)) &>/dev/null
		if [[ $? -eq 0 ]]; then
			if [[ ${port} -ge 1 ]] && [[ ${port} -le 65535 ]]; then
				echo && echo "=============================="
				echo -e "端口 : ${Red_background_prefix} ${port} ${Font_color_suffix}"
				echo "==============================" && echo
				break
			else
				echo "输入错误, 请输入正确的端口。"
			fi
		else
			echo "输入错误, 请输入正确的端口。"
		fi
		done
}

Set_ipv6(){
	echo -e "是否开启 IPv6 解析 ？
==================================
${Green_font_prefix} 1.${Font_color_suffix} 开启  ${Green_font_prefix} 2.${Font_color_suffix} 关闭
=================================="
	read -e -p "(默认：1.开启)：" ipv6
	[[ -z "${ipv6}" ]] && ipv6="1"
	if [[ ${ipv6} == "1" ]]; then
		ipv6=true
	else
		ipv6=false
	fi
	echo && echo "=================================="
	echo -e "IPv6 解析 开启状态：${Red_background_prefix} ${ipv6} ${Font_color_suffix}"
	echo "==================================" && echo
}

Set_psk(){
	echo "请输入 Snell Server 密钥${Yellow_font_prefix}[0-9][a-z][A-Z]${Font_color_suffix}"
	read -e -p "(默认: 随机生成):" psk
	[[ -z "${psk}" ]] && psk=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)
	echo && echo "=============================="
	echo -e "密钥 : ${Red_background_prefix} ${psk} ${Font_color_suffix}"
	echo "==============================" && echo
}

Set_obfs(){
    echo -e "配置 OBFS
==================================
${Green_font_prefix} 1.${Font_color_suffix} TLS  ${Green_font_prefix} 2.${Font_color_suffix} HTTP ${Green_font_prefix} 3.${Font_color_suffix} 关闭
=================================="
    read -e -p "(默认：3.关闭)：" obfs_input
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
    echo && echo "=================================="
    echo -e "OBFS 状态：${Red_background_prefix} ${obfs} ${Font_color_suffix}"
    echo "==================================" && echo
}

Set_ver(){
	echo -e "配置 Snell Server 协议版本${Yellow_font_prefix}[2-4]${Font_color_suffix} 
==================================
${Green_font_prefix} 2.${Font_color_suffix} v2 ${Green_font_prefix} 3.${Font_color_suffix} v3 ${Green_font_prefix} 4.${Font_color_suffix} v4 
=================================="
	read -e -p "(默认：4.v4)：" ver
	[[ -z "${ver}" ]] && ver="4"
	if [[ ${ver} == "2" ]]; then
		ver=2
	elif [[ ${ver} == "3" ]]; then
		ver=3
	elif [[ ${ver} == "4" ]]; then
		ver=4
	else
		ver=4
	fi
	echo && echo "=================================="
	echo -e "Snell Server 协议版本：${Red_background_prefix} ${ver} ${Font_color_suffix}"
	echo "==================================" && echo
}

Set_host(){
	echo "请输入 Snell Server 域名 "
	read -e -p "(默认: icloud.com):" host
	[[ -z "${host}" ]] && host=icloud.com
	echo && echo "=============================="
	echo -e "	域名 : ${Red_background_prefix} ${host} ${Font_color_suffix}"
	echo "==============================" && echo
}

Set_tfo(){
	echo -e "是否开启 TCP Fast Open ？
==================================
${Green_font_prefix} 1.${Font_color_suffix} 开启  ${Green_font_prefix} 2.${Font_color_suffix} 关闭
=================================="
	read -e -p "(默认：1.开启)：" tfo
	[[ -z "${tfo}" ]] && tfo="1"
	if [[ ${tfo} == "1" ]]; then
		tfo=true
		enable_systfo
	else
		tfo=false
	fi
	echo && echo "=================================="
	echo -e "TCP Fast Open 开启状态：${Red_background_prefix} ${tfo} ${Font_color_suffix}"
	echo "==================================" && echo
}

Set(){
	check_installed_status
	echo && echo -e "你想要做什么？
==============================
 ${Green_font_prefix}1.${Font_color_suffix}  修改 端口
 ${Green_font_prefix}2.${Font_color_suffix}  修改 密钥
 ${Green_font_prefix}3.${Font_color_suffix}  配置 OBFS
 ${Green_font_prefix}4.${Font_color_suffix}  配置 OBFS 域名
 ${Green_font_prefix}5.${Font_color_suffix}  开关 IPv6 解析
 ${Green_font_prefix}6.${Font_color_suffix}  开关 TCP Fast Open
 ${Green_font_prefix}7.${Font_color_suffix}  配置 Snell Server 协议版本
==============================
 ${Green_font_prefix}8.${Font_color_suffix}  修改 全部配置" && echo
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
		Write_config
		Restart
	elif [[ "${modify}" == "8" ]]; then
		Read_config
		Set_port
		Set_psk
		Set_obfs
		Set_host
		Set_ipv6
		Set_tfo
		Set_ver
		Write_config
		Restart
	else
		echo -e "${Error} 请输入正确的数字${Yellow_font_prefix}[1-8]${Font_color_suffix}" && exit 1
	fi
    sleep 3s
    start_menu
}

# 安装 v2
Install_v2(){
	check_root
	[[ -e ${FILE} ]] && echo -e "${Error} 检测到 Snell Server 已安装 !" && exit 1
	echo -e "${Info} 开始设置 配置..."
	Set_port
	Set_psk
	Set_obfs
	Set_host
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
	echo -e "${Info} 所有步骤 安装完毕，开始启动..."
	Start
    sleep 3s
    start_menu
}

# 安装 v3
Install_v3(){
	check_root
	[[ -e ${FILE} ]] && echo -e "${Error} 检测到 Snell Server 已安装 !" && exit 1
	echo -e "${Info} 开始设置 配置..."
	Set_port
	Set_psk
	Set_obfs
	Set_host
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
	echo -e "${Info} 所有步骤 安装完毕，开始启动..."
	Start
    sleep 3s
    start_menu
}

# 安装 v4
Install_v4(){
	check_root
	[[ -e ${FILE} ]] && echo -e "${Error} 检测到 Snell Server 已安装 ,请先卸载旧版再安装新版!" && exit 1
	echo -e "${Info} 开始设置 配置..."
	Set_port
	Set_psk
	Set_obfs  # 这将设置全局变量 obfs
     if [[ "${obfs}" != "off" ]]; then
        Set_host  # 只有当 obfs 不是 "off" 时才调用
     fi
	Set_ipv6
	Set_tfo
	echo -e "${Info} 开始安装/配置 依赖..."
	Installation_dependency
	echo -e "${Info} 开始下载/安装..."
	v4_Download
	echo -e "${Info} 开始安装 服务脚本..."
	Service
	echo -e "${Info} 开始写入 配置文件..."
	Write_config
	echo -e "${Info} 所有步骤 安装完毕，开始启动..."
	# print snell server info
     echo -e "—————————————————————————"
     echo -e "${Green_font_prefix}Please copy the following line to the Surge [Proxy] section:${Font_color_suffix}" 
     echo "$(curl -s ipinfo.io/city) = snell, $(curl -4s ipinfo.io/ip), ${port}, psk=${psk}, version=${ver}, reuse=true, tfo=${tfo}"
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
	[[ ! "$status" == "running" ]] && echo -e "${Error} Snell Server 没有运行，请检查 !" && exit 1
	systemctl stop snell-server
	echo -e "${Info} Snell Server 停止成功 !"
    sleep 3s
    start_menu
}
Restart(){
	check_installed_status
	systemctl restart snell-server
	echo -e "${Info} Snell Server 重启完毕!"
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
            echo "Snell Server 服务已停止"
        else
            echo "停止服务失败，请手动检查"
        fi

        echo "正在禁用 Snell Server 服务..."
        systemctl disable snell-server
        if [[ $? -eq 0 ]]; then
            echo "Snell Server 服务已禁用"
        else
            echo "禁用服务失败，请手动检查。"
        fi

        echo "正在删除 Snell Server 主程序和配置文件..."
        rm -rf "${FILE}"
        rm -rf /etc/snell
        if [[ $? -eq 0 ]]; then
            echo "文件删除完成"
        else
            echo "删除文件失败，请手动检查"
        fi

        echo && echo -e "${Yellow_font_prefix}Snell Server 卸载完成 !${Font_color_suffix}" && echo
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
	echo -e "Snell Server 配置信息："
	echo -e "—————————————————————————"
	[[ "${ipv4}" != "IPv4_Error" ]] && echo -e " 地址\t: ${Green_font_prefix}${ipv4}${Font_color_suffix}"
	[[ "${ip6}" != "IPv6_Error" ]] && echo -e " 地址\t: ${Green_font_prefix}${ip6}${Font_color_suffix}"
	echo -e " 端口\t: ${Green_font_prefix}${port}${Font_color_suffix}"
	echo -e " 密钥\t: ${Green_font_prefix}${psk}${Font_color_suffix}"
	echo -e " OBFS\t: ${Green_font_prefix}${obfs}${Font_color_suffix}"
	echo -e " 域名\t: ${Green_font_prefix}${host}${Font_color_suffix}"
	echo -e " IPv6\t: ${Green_font_prefix}${ipv6}${Font_color_suffix}"
	echo -e " TFO\t: ${Green_font_prefix}${tfo}${Font_color_suffix}"
	echo -e " VER\t: ${Green_font_prefix}${ver}${Font_color_suffix}"
	echo -e "—————————————————————————"
	echo
	before_start_menu
}

Status(){
	echo -e "${Info} 获取 Snell Server 活动日志 ……"
	echo -e "${Tip} ${Yellow_font_prefix}返回主菜单请按 q${Font_color_suffix} "
	systemctl status snell-server
	start_menu
}

Install_Shadow_TLS(){
    # 提示用户输入 SHADOW_TLS_PORT 值
read -e -p "请输入SHADOW_TLS_PORT值(1-65535,默认8443): " SHADOW_TLS_PORT

# 如果用户未输入值，则使用默认值 8443
[[ -z "${SHADOW_TLS_PORT}" ]] && SHADOW_TLS_PORT="8443"

# 检查用户输入的值是否有效
if ! [[ "$SHADOW_TLS_PORT" =~ ^[0-9]+$ ]] || [ "$SHADOW_TLS_PORT" -lt 1 ] || [ "$SHADOW_TLS_PORT" -gt 65535 ]; then
    echo -e "${Error} SHADOW_TLS_PORT值必须是1到65535之间的数字"
    exit 1
fi

    echo -e "\033[33mSHADOW_TLS_PORT: ${SHADOW_TLS_PORT}\033[0m"

    # 获取最新的 SHADOW_TLS_VERSION
    SHADOW_TLS_VERSION=$(curl -s "https://api.github.com/repos/ihciah/shadow-tls/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    if [ -z "$SHADOW_TLS_VERSION" ]; then
        echo "${Error} 获取 SHADOW_TLS_VERSION 失败"
        exit 1
    fi

    # 下载 shadow-tls 并检查是否成功
    url="https://github.com/ihciah/shadow-tls/releases/download/${SHADOW_TLS_VERSION}/shadow-tls-x86_64-unknown-linux-musl"
    destination="/usr/local/bin/shadow-tls"
    if ! wget "$url" -O "$destination"; then
        echo -e "${Error} 下载 shadow-tls 失败"
        exit 1
    fi

    # 设置可执行权限
    chmod +x "$destination"

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
	ExecStart=$destination --v3 server --listen 0.0.0.0:${SHADOW_TLS_PORT} --server 127.0.0.1:2345 --tls mensura.cdn-apple.com --password JsJeWtjiUyJ5yeto
	StandardOutput=syslog
	StandardError=syslog
	SyslogIdentifier=shadow-tls

	[Install]
	WantedBy=multi-user.target
EOF

    # 重新加载systemd守护进程并启动服务
    sudo systemctl daemon-reload
    sudo systemctl enable shadow-tls.service

    # 启动服务
    if sudo systemctl start shadow-tls.service; then
        # 提取服务状态
        status=$(systemctl status shadow-tls.service | grep "Active" | awk -F'[()]' '{print $2}')
        if [ "$status" == "running" ]; then
            echo -e "${Yellow_font_prefix}Shadow-TLS 服务已成功启动并且正在运行${Font_color_suffix}"
            Read_config
            echo -e "—————————————————————————"
            echo -e "${Green_font_prefix}Please copy the following line to the Surge [Proxy] section:${Font_color_suffix}" 
            echo "$(curl -s ipinfo.io/city) = snell, $(curl -s ip.sb -4), ${port}, psk=${psk}, version=${ver}, reuse=true, tfo=${tfo}, shadow-tls-password=JsJeWtjiUyJ5yeto, shadow-tls-sni=mensura.cdn-apple.com, shadow-tls-version=3"
            echo -e "—————————————————————————"
        else
            echo "服务未在运行状态"
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
    [[ -z "${ynun}" ]] && ynun="n" # 如果用户没有输入，设置默认值为 'n'
    
    if [[ "${ynun}" =~ ^[Yy]$ ]]; then
        # 检查服务是否启动
        if systemctl is-enabled --quiet shadow-tls.service; then
            echo "正在停止 shadow-tls 服务..."
            sudo systemctl stop shadow-tls.service
            if [[ $? -eq 0 ]]; then
            echo "shadow-tls 服务已停止"
            else
            echo "停止服务失败，请手动检查"
           fi
           
            echo "正在禁用 shadow-tls 服务..."
            sudo systemctl disable shadow-tls.service
            if [[ $? -eq 0 ]]; then
            echo "shadow-tls 服务已禁用"
            else
            echo "禁用服务失败，请手动检查"
            fi
        else
            echo -e "${Warn} shadow-tls 服务已被禁用"
            echo "正在停止 shadow-tls 服务..."
            sudo systemctl stop shadow-tls.service
            if [[ $? -eq 0 ]]; then
            echo "shadow-tls 服务已停止"
            else
            echo "停止服务失败，请手动检查"
           fi
        fi

        # 检查服务文件是否存在并删除
        if [ -f /etc/systemd/system/shadow-tls.service ]; then
            echo "正在删除服务文件..."
            sudo rm /etc/systemd/system/shadow-tls.service
            if [[ $? -eq 0 ]]; then
            echo "shadow-tls 服务文件已删除"
            else
            echo "停止服务失败，请手动检查"
           fi
           
            echo "重新加载 systemd 配置..."
            sudo systemctl daemon-reload
            echo "重置 systemd 失败状态..."
            sudo systemctl reset-failed
        else
            echo "服务文件不存在，无需删除"
        fi

        # 删除检查可执行文件
            echo "删除 shadow-tls 可执行文件..."
            sudo rm -rf /usr/local/bin/shadow-tls
            if [[ $? -eq 0 ]]; then
            echo "shadow-tls 可执行文件删除完成"
            else
            echo "删除shadow-tls 可执行文件失败，请手动检查"
            fi

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
	check_status
	[[ "$shadow_tls_status" == "running" ]] && echo -e "${Info} Shadow-TLS 启动成功 !"
    sleep 3s
    start_menu
}

Stop_Shadow_TLS(){
     check_Shadow_TLS_installed_status
	check_Shadow_TLS_status
	[[ !"$shadow_tls_status" == "running" ]] && echo -e "${Error} Shadow-TLS 未在运行，请检查 !" && exit 1
	systemctl stop shadow-tls
	echo -e "${Info} Shadow-TLS 停止成功 !"
    sleep 3s
    start_menu
}

Restart_Shadow_TLS(){
     check_Shadow_TLS_installed_status
	systemctl restart shadow-tls
	echo -e "${Info} Shadow-TLS 重启完毕!"
	sleep 3s
     start_menu
}

Status_Shadow_TLS(){
	echo -e "${Info} 获取 Shadow_TLS 活动日志 ……"
	if systemctl is-enabled --quiet shadow-tls.service; then
	echo -e "${Tip} ${Yellow_font_prefix}返回主菜单请按 q${Font_color_suffix} "
	else
            echo -e "${Error} ${Red_font_prefix}shadow-tls 服务未安装${Font_color_suffix}"
	fi
	systemctl status shadow-tls
	start_menu
}

check_Shadow_TLS_installed_status(){
	[[ ! -e "/usr/local/bin/shadow-tls" ]] && echo -e "${Error} Shadow-TLS 没有安装，请检查 !" && exit 1
}

check_Shadow_TLS_status(){
	shadow_tls_status=`systemctl status shadow-tls.service | grep "Active" | awk -F'[()]' '{print $2}'`
}

Edit_Shadow_TLS(){
# 提示用户输入 SHADOW_TLS_PORT 值
read -e -p "请输入SHADOW_TLS_PORT值(1-65535,默认8443): " SHADOW_TLS_PORT

# 如果用户未输入值，则使用默认值 8443
[[ -z "${SHADOW_TLS_PORT}" ]] && SHADOW_TLS_PORT="8443"

# 检查用户输入的值是否有效
if ! [[ "$SHADOW_TLS_PORT" =~ ^[0-9]+$ ]] || [ "$SHADOW_TLS_PORT" -lt 1 ] || [ "$SHADOW_TLS_PORT" -gt 65535 ]; then
    echo -e "${Error} SHADOW_TLS_PORT值必须是1到65535之间的数字"
    exit 1
fi

    echo -e "\033[33mSHADOW_TLS_PORT: ${SHADOW_TLS_PORT}\033[0m"

# 创建systemd服务文件
sudo tee /etc/systemd/system/shadow-tls.service > /dev/null <<-EOF
	[Unit]
	Description=Shadow-TLS Server Service
	Documentation=man:sstls-server
	After=network-online.target
	Wants=network-online.target

	[Service]
	Type=simple
	ExecStart=/usr/local/bin/shadow-tls --v3 server --listen 0.0.0.0:${SHADOW_TLS_PORT} --server 127.0.0.1:2345 --tls mensura.cdn-apple.com --password JsJeWtjiUyJ5yeto
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
            echo -e "${Yellow_font_prefix}服务已成功启动并且正在运行${Font_color_suffix}"
            Read_config
            echo -e "—————————————————————————"
            echo -e "${Green_font_prefix}Please copy the following line to the Surge [Proxy] section:${Font_color_suffix}" 
            echo "$(curl -s ipinfo.io/city) = snell, ${ipv4}, ${port}, psk=${psk}, version=${ver}, reuse=true, tfo=${tfo}, shadow-tls-password=JsJeWtjiUyJ5yeto, shadow-tls-sni=mensura.cdn-apple.com, shadow-tls-version=3"
            echo -e "—————————————————————————"
        else
            echo -e "${Red_font_prefix}服务未在运行状态${Font_color_suffix}"
            systemctl status shadow-tls.service
        fi
    else
        echo -e "${Error} 错误: 启动 shadow-tls 服务失败"
        exit 1
    fi
}

Set_Shadow_TLS(){
	check_Shadow_TLS_installed_status
	echo && echo -e "你想要做什么？
==============================
 ${Green_font_prefix}1.${Font_color_suffix}  修改Shadow-TLS端口
 =============================="  && echo
	read -e -p "(默认: 取消):" modify
	[[ -z "${modify}" ]] && echo "已取消..." && exit 1
	if [[ "${modify}" == "1" ]]; then
	Edit_Shadow_TLS	
	else
		echo -e "${Error} 请输入正确的数字${Yellow_font_prefix}[1]${Font_color_suffix}" && exit 1
	fi
    sleep 3s
    start_menu
}


Update_Shell(){
	echo -e "当前版本为 [ ${sh_ver} ]，开始检测最新版本..."
	sh_new_ver=$(wget --no-check-certificate -qO- "https://raw.githubusercontent.com/chentianqihub/surge/main/scripts/snell%2Bstls.sh"|grep 'sh_ver="'|awk -F "=" '{print $NF}'|sed 's/\"//g'|head -1)
	[[ -z ${sh_new_ver} ]] && echo -e "${Error} 检测最新版本失败 !" && start_menu
	if [[ ${sh_new_ver} != ${sh_ver} ]]; then
		echo -e "发现新版本[ ${sh_new_ver} ]，是否更新？[Y/n]"
		read -p "(默认: y):" yn
		[[ -z "${yn}" ]] && yn="y"
		if [[ ${yn} == [Yy] ]]; then
			wget -O snell.sh --no-check-certificate https://raw.githubusercontent.com/chentianqihub/surge/main/scripts/snell%2Bstls.sh && chmod +x snell+stls.sh
			echo -e "脚本已更新为最新版本[ ${sh_new_ver} ] !"
			echo -e "3s后执行新脚本"
            sleep 3s
            bash snell+stls.sh
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
    	bash snell+stls.sh
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
——————————————————————————————
 ${Green_font_prefix} 9.${Font_color_suffix} 退出脚本
——————————————————————————————
 ${Green_font_prefix} 10.${Font_color_suffix} 安装 Shadow-TLS
 ${Green_font_prefix} 11.${Font_color_suffix} 卸载 Shadow-TLS
——————————————————————————————
 ${Green_font_prefix} 12.${Font_color_suffix} 启动 Shadow-TLS
 ${Green_font_prefix} 13.${Font_color_suffix} 停止 Shadow-TLS
 ${Green_font_prefix} 14.${Font_color_suffix} 重启 Shadow-TLS
——————————————————————————————
 ${Green_font_prefix} 15.${Font_color_suffix} 查看 Shadow-TLS运行状态
 ${Green_font_prefix} 16.${Font_color_suffix} 设置 Shadow-TLS配置信息
==============================" && echo
	if [[ -e ${FILE} ]]; then
	     #check_status
		status=`systemctl status snell-server | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1`
		if [[ "$status" == "running" ]]; then
			echo -e " 当前Snell状态: ${Green_font_prefix}已安装${Yellow_font_prefix}[v$(cat ${CONF}|grep 'version = '|awk -F 'version = ' '{print $NF}')]${Font_color_suffix}并${Green_font_prefix}已启动${Font_color_suffix}"
		else
			echo -e " 当前Snell状态: ${Green_font_prefix}已安装${Yellow_font_prefix}[v$(cat ${CONF}|grep 'version = '|awk -F 'version = ' '{print $NF}')]${Font_color_suffix}但${Red_font_prefix}未启动${Font_color_suffix}"
		fi
	else
		echo -e " 当前Snell状态: ${Red_font_prefix}未安装${Font_color_suffix}"
	fi
	
	if [[ -e "/usr/local/bin/shadow-tls" ]]; then
		check_Shadow_TLS_status
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
	read -e -p " 请输入数字[0-16]（默认值: 1）:" num
	
     # 如果用户未输入值，则使用默认值1
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
		exit 1
		;;
		10)
                Install_Shadow_TLS
                ;;
                11)
                Uninstall_Shadow_TLS
                ;;
                12)
                Start_Shadow_TLS
                ;;
                13)
                Stop_Shadow_TLS
                ;;
                14)
                Restart_Shadow_TLS
                ;;
                15)
                Status_Shadow_TLS
                ;;
                16)
                Set_Shadow_TLS
                ;;
		*)
		echo -e "请输入正确数字${Yellow_font_prefix}[0-16]${Font_color_suffix}"
		;;
	esac
}
start_menu
