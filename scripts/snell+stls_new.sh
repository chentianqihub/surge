#!/usr/bin/env bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

#=================================================
#	System Required: Debian/Ubuntu/CentOS
#	Description: Snell+ShadowTLS 管理脚本 
#	Author: https://github.com/chentianqihub/surge
#	Link: https://t.me/m/XIADdsxCNTRl
#=================================================

sh_ver="1.8.7"
snell_v1_version="1"
snell_v2_version="2.0.6"
snell_v3_version="3.0.1"
snell_v4_version="4.1.1"
snell_v5_version="5.0.0"
filepath=$(cd "$(dirname "$0")" || exit; pwd)
file_1=$(echo -e "${filepath}"|awk -F "$0" '{print $1}')
FOLDER="/etc/snell/"
FILE="/usr/local/bin/snell-server"
Shadow_TLS_FILE="/usr/local/bin/shadow-tls"
Snell_conf="/etc/snell/config.conf"
Snell_ver_File="/etc/snell/ver.txt"
sysctl_conf="/etc/sysctl.d/local.conf"
service_file="/etc/systemd/system/shadow-tls.service"

Green_font_prefix="\033[32m" && Red_font_prefix="\033[31m" && Yellow_font_prefix="\033[0;33m" && Blue_font_prefix="\033[0;36m" && Green_background_prefix="\033[42;37m" && Red_background_prefix="\033[41;37m" && Font_color_suffix="\033[0m"
Blue_italic="\033[36m\033[3m"  # 青蓝色+斜体
Info="${Green_font_prefix}[信息]${Font_color_suffix}"
Error="${Red_font_prefix}[错误]${Font_color_suffix}"
Tip="${Yellow_font_prefix}[注意]${Font_color_suffix}"
Warn="${Yellow_font_prefix}[Warn]${Font_color_suffix}"

# 检查是否为 Root 用户
check_root(){
	[[ $EUID != 0 ]] && echo -e "${Error} 当前非ROOT账号(或没有ROOT权限),无法继续操作! 请更换ROOT账号或使用 ${Green_background_prefix}sudo su${Font_color_suffix} 命令获取临时ROOT权限(执行后可能会提示输入当前账号的密码)." && exit 1
}

# 检查系统类型
check_sys(){
	if [[ -f /etc/redhat-release ]]; then
		release="centos"
	elif grep -q -E -i "debian" /etc/issue; then
		release="debian"
	elif grep -q -E -i "ubuntu" /etc/issue; then	
		release="ubuntu"
	elif grep -q -E -i "centos|red hat|redhat" /etc/issue; then	
		release="centos"
	elif grep -q -E -i "debian" /proc/version; then	
		release="debian"
	elif grep -q -E -i "ubuntu" /proc/version; then	
		release="ubuntu"
	elif grep -q -E -i "centos|red hat|redhat" /proc/version; then	
		release="centos"
    fi
}

# 等待其他包管理器实例结束
wait_for_package_manager() {
    local max_wait=60
    local waited=0
    local spin='-\|/'
    if [[ ${release} == "centos" ]]; then
    package_manager="yum/rpm"
    lock_files=("/var/run/yum.pid" "/var/lib/rpm/.rpm.lock")
    else
    package_manager="apt/dpkg"
    lock_files=("/var/lib/dpkg/lock-frontend" "/var/lib/dpkg/lock")
    fi

while true; do
        lock_found=0
        
    # 检查锁文件是否存在
    for lock_file in "${lock_files[@]}"; do
    if [ -e "$lock_file" ]; then
        if fuser "$lock_file" >/dev/null 2>&1; then
            lock_found=1
            break
        fi
    fi
    done

    if [ "$lock_found" -eq 1 ]; then
        if [ $waited -ge $max_wait ]; then
            printf "\r\033[K"
            echo -e "${Error} 等待超时, 无法获取 ${package_manager} 锁, 请稍后再试 !"
            exit 1
        fi
        #printf "\r${Tip} 请等待其他 ${package_manager} 进程完成...(Maximum waiting time: 60s)  ${spin:$((waited % ${#spin})):1} "
        printf "\r%b 请等待其他 %s 进程完成...(Maximum waiting time: 60s)  %s " "${Tip}" "${package_manager}" "${spin:$((waited % ${#spin})):1}"
        sleep 1
        waited=$((waited + 1))
    else
        break    
    fi
done  
    printf "\r\033[K"

    if [ $waited -gt 0 ]; then
        echo -e "${Info}等待完成, 继续执行..."
    fi
    
}

# 安装依赖
Install_dependencies(){
     wait_for_package_manager
     # 需要安装的软件包
     local cmds=(wget curl gzip unzip jq ss)
     local missing_cmds=()
     local need_pkgs=() 
     local still_missing=()

     # 收集缺失的命令
    for cmd in "${cmds[@]}"; do
        command -v "$cmd" &>/dev/null || missing_cmds+=("$cmd")
    done

    # 如果没有缺失，直接返回
    if [[ ${#missing_cmds[@]} -eq 0 ]]; then
        echo -e "${Info} 依赖检查完成 !"
        return 0
    fi
    echo -e "${Error} 检测到缺少依赖: ${Blue_italic}${missing_cmds[*]}${Font_color_suffix}"
    echo -e "${Info} 正在尝试安装..."

    # 根据缺失的命令映射出对应的软件包（一次性安装）
    for cmd in "${missing_cmds[@]}"; do
        case "$cmd" in
            ss)
                if [[ -f /etc/debian_version ]]; then
                    need_pkgs+=(iproute2)
                elif [[ -f /etc/redhat-release ]]; then
                    need_pkgs+=(iproute)
                else
                    echo -e "${Error} 无法识别的系统类型, 请手动安装 iproute/iproute2 !"
                    exit 1
                fi
                ;;
            *) need_pkgs+=("$cmd") ;;
        esac
    done

    # 去重（bash 4+）
    if declare -A _tmp 2>/dev/null; then
        declare -A uniq
        for p in "${need_pkgs[@]}"; do uniq["$p"]=1; done
        need_pkgs=("${!uniq[@]}")
    fi

    # 执行安装
    if [[ -f /etc/debian_version ]]; then
		apt-get update && apt-get -y install "${need_pkgs[@]}"
    elif [[ -f /etc/redhat-release ]]; then
		yum update && yum -y install "${need_pkgs[@]}"
    else
        echo -e "${Error} 不支持的系统, 请自行安装: ${Blue_italic}${need_pkgs[*]}${Font_color_suffix} !"
        exit 1
    fi

     # 检查依赖包是否安装成功
    for cmd in "${missing_cmds}"; do
        command -v "$cmd" &> /dev/null || still_missing+=("$cmd")
    done      
    # 如果仍有依赖包安装失败，列出失败的包并退出
    if [ ${#still_missing[@]} -ne 0 ]; then
        echo -e "${Error} 以下依赖包安装失败或无法找到: ${Blue_italic}${still_missing[*]}${Font_color_suffix}"
        echo -e "${Error} 请手动安装这些依赖包后重试 !"
        exit 1
    fi
    echo -e "${Info} 依赖检查完成，所有组件已就绪 !"

	# 其余系统调优
	sysctl -w net.core.rmem_max=26214400
	sysctl -w net.core.rmem_default=26214400
	\cp -f /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
}

# 检查系统架构
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

# 开启TCP Fast Open
enable_systfo() {
	kernel=$(uname -r | awk -F . '{print $1}')
	if [ "$kernel" -ge 3 ]; then
		echo 3 >/proc/sys/net/ipv4/tcp_fastopen
		[[ ! -e $sysctl_conf ]] && echo "fs.file-max = 51200
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
		echo -e "${Error} 系统内核版本过低,无法支持 TCP Fast Open !"
                tfo=false
	fi
}

check_installed_status(){
	[[ ! -e ${FILE} ]] && echo -e "${Error} Snell Server 没有安装,请检查 !" && exit 1
}

check_status(){
     #status=$(systemctl status snell-server | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
	#status=$(systemctl status snell-server.service | grep "Active" | awk -F'[()]' '{print $2}')
	if systemctl is-active snell-server.service &> /dev/null; then
        status="running"
     else
        status="stopped"
     fi
}

# 获取 Snell 下载链接
getSnellDownloadUrl(){
	sysArch
	local version=$1
	if [[ "$ver" -ge 4 ]] ; then
	snell_url="https://dl.nssurge.com/snell/snell-server-v${version}-linux-${arch}.zip"
	else
	snell_url="https://raw.githubusercontent.com/chentianqihub/Others/master/snell/v${version}/snell-server-v${version}-linux-${arch}.zip"
	fi
}

# 获取最新版本信息
getVer(){
    var_name="snell_v${ver}_version"
    new_ver="${!var_name}"
    
    if [[ -z "${new_ver}" ]]; then
        echo -e "${Error} Snell v${ver} 最新版本获取失败!"
        return 1
    fi  
    echo -e "${Info} 检测到 Snell v${ver} 最新版本为 [ ${new_ver} ]"
}

# 下载并安装 Snell v1（GitHub 备份源）
v1_Download(){
     getVer
	Snell_Download "${snell_v1_version}" "v1 GitHub备份源版"
}

# 下载并安装 Snell v2（GitHub 备份源）
v2_Download(){
     getVer
	Snell_Download "${snell_v2_version}" "v2 GitHub备份源版"
}

# 下载并安装 Snell v3（GitHub 备份源）
v3_Download(){
     getVer
	Snell_Download "${snell_v3_version}" "v3 GitHub备份源版"
}

# 下载并安装 Snell v4（官方源）
v4_Download(){
     getVer
	Snell_Download "${snell_v4_version}" "v4 官网源版"
}

# 下载并安装 Snell v5（官方源）
v5_Download(){
     getVer
	Snell_Download "${snell_v5_version}" "v5 官网源版"
}

# 通用下载并安装 Snell 函数
Snell_Download(){
	local version=$1
	local version_type=$2
	echo -e "${Info} 试图请求 Snell Server ${Yellow_font_prefix}${version_type}${Font_color_suffix} ..."
	getSnellDownloadUrl "${version}"
	wget --no-check-certificate -N "${snell_url}"
	if [[ ! -e "snell-server-v${version}-linux-${arch}.zip" ]]; then
		echo -e "${Error} Snell Server ${Yellow_font_prefix}${version_type}${Font_color_suffix} 下载失败 !"
		exit 1
	else
		unzip -o "snell-server-v${version}-linux-${arch}.zip"
	fi
	if [[ ! -e "snell-server" ]]; then
		echo -e "${Error} Snell Server ${Yellow_font_prefix}${version_type}${Font_color_suffix} 解压失败 !"
		exit 1
	else
		rm -rf "snell-server-v${version}-linux-${arch}.zip"
		chmod +x snell-server
		mv -f snell-server "${FILE}"
		echo "v${version}" > ${Snell_ver_File}
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
		echo -e "选择安装版本${Yellow_font_prefix}[1-5]${Font_color_suffix} 
==================================
${Green_font_prefix} 1.${Font_color_suffix} v1 ${Green_font_prefix} 2.${Font_color_suffix} v2  ${Green_font_prefix} 3.${Font_color_suffix} v3  ${Green_font_prefix} 4.${Font_color_suffix} v4 ${Green_font_prefix} 5.${Font_color_suffix} v5
=================================="
	read -e -p "(默认: 5.v5): " ver
	[[ -z "${ver}" ]] && ver="5"
	if [[ ${ver} == "1" ]]; then
	     echo && echo "=================================="
	     echo -e "Snell Server 协议版本: ${Red_background_prefix} v${ver} ${Font_color_suffix}"
	     echo "==================================" && echo
	     Install_v1
	elif [[ ${ver} == "2" ]]; then
	     echo && echo "=================================="
	     echo -e "Snell Server 协议版本: ${Red_background_prefix} v${ver} ${Font_color_suffix}"
	     echo "==================================" && echo
	     Install_v2
	elif [[ ${ver} == "3" ]]; then
	     echo && echo "=================================="
	     echo -e "Snell Server 协议版本: ${Red_background_prefix} v${ver} ${Font_color_suffix}"
	     echo "==================================" && echo
	     Install_v3
	elif [[ ${ver} == "4" ]]; then
	     echo && echo "=================================="
	     echo -e "Snell Server 协议版本: ${Red_background_prefix} v${ver} ${Font_color_suffix}"
	     echo "==================================" && echo
	     Install_v4
	elif [[ ${ver} == "5" ]]; then
	     echo && echo "=================================="
	     echo -e "Snell Server 协议版本: ${Red_background_prefix} v${ver} ${Font_color_suffix}"
	     echo "==================================" && echo
	     Install_v5     
	else
	     echo -e "${Warn} 无效输入! 将取默认值${Yellow_font_prefix} v5${Font_color_suffix}"
	     ver="5"
	     echo && echo "=================================="
	     echo -e "Snell Server 协议版本: ${Red_background_prefix} v${ver} ${Font_color_suffix}"
	     echo "==================================" && echo
          Install_v5
	fi
}

# 配置服务
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

# 写入配置文件
Write_config(){
if [[ -f "${Snell_conf}" ]]; then
        cp "${Snell_conf}" "${Snell_conf}.bak.$(date +%Y%m%d_%H%M%S)"
        echo -e "${Info} 已备份旧配置文件到 ${Snell_conf}.bak"
    fi
    cat > "${Snell_conf}" << EOF
[snell-server]
listen = ::0:${port}
ipv6 = ${ipv6}
psk = ${psk}
obfs = ${obfs}
$(if [[ ${obfs} != "off" ]]; then echo "obfs-host = ${host}"; fi)
tfo = ${tfo}
$(if [[ "${ver}" =~ ^[45]$ ]]; then echo "dns = ${dns}"; fi)
version = ${ver}
EOF
}

# 读取配置文件
Read_config(){
	[[ ! -e ${Snell_conf} ]] && echo -e "${Error} Snell Server 配置文件不存在 !" && exit 1
	ipv6=$(grep 'ipv6 = ' "${Snell_conf}" | awk -F 'ipv6 = ' '{print $NF}')
	port=$(grep -E '^listen\s*=' ${Snell_conf} | awk -F ':' '{print $NF}' | xargs)
	psk=$(grep 'psk = ' "${Snell_conf}" |awk -F 'psk = ' '{print $NF}')
	obfs=$(grep 'obfs = ' "${Snell_conf}" |awk -F 'obfs = ' '{print $NF}')
	host=$(grep 'obfs-host = ' "${Snell_conf}" |awk -F 'obfs-host = ' '{print $NF}')
	tfo=$(grep 'tfo = ' "${Snell_conf}" |awk -F 'tfo = ' '{print $NF}')
     dns=$(grep 'dns = ' "${Snell_conf}" |awk -F 'dns = ' '{print $NF}')
	ver=$(grep 'version = ' "${Snell_conf}" |awk -F 'version = ' '{print $NF}')
}

# 设置端口
Set_port(){
    # 循环直到用户输入有效且未被占用的端口值
    while true; do
        echo -e "${Tip} 本步骤不涉及系统防火墙端口操作, 请手动放行相应端口 !"
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

# 编辑端口
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

# 设置 IPv6
Set_ipv6(){
	echo -e "是否开启 IPv6 解析 ?
==================================
${Green_font_prefix} 1.${Font_color_suffix} 开启  ${Green_font_prefix} 2.${Font_color_suffix} 关闭
=================================="
	read -e -p "(默认: 2.关闭): " ipv6
	[[ -z "${ipv6}" ]] && ipv6="2"
	if [[ ${ipv6} == "1" ]]; then
		ipv6=true
	elif [[ ${ipv6} == "2" ]]; then
		ipv6=false
        else 
	     echo -e "${Warn} 无效输入! 将取默认值${Yellow_font_prefix} 2.关闭 ${Font_color_suffix}"
	     ipv6=false
	fi
	echo && echo "=================================="
	echo -e "IPv6 解析 开启状态: ${Red_background_prefix} ${ipv6} ${Font_color_suffix}"
	echo "==================================" && echo
}

# 设置密钥
Set_psk(){
	echo -e "请输入 Snell Server 密钥 [0-9][a-z][A-Z]"
	read -e -p "(默认: 随机生成): " psk
	[[ -z "${psk}" ]] && psk=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)
	echo && echo "=============================="
	echo -e "密钥 : ${Red_background_prefix} ${psk} ${Font_color_suffix}"
	echo "==============================" && echo
}

# 设置 OBFS
Set_obfs() {
    if [[ "${ver}" = "4" || "${ver}" = "5" ]]; then
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
            echo -e "${Warn} 无效输入! 将取默认值${Yellow_font_prefix} 2.关闭 ${Font_color_suffix}"
            obfs="off"
        fi
    else
        echo -e "配置 OBFS, ${Tip} 无特殊作用不建议启用该项
==================================
${Green_font_prefix} 1.${Font_color_suffix} TLS  ${Green_font_prefix} 2.${Font_color_suffix} HTTP ${Green_font_prefix} 3.${Font_color_suffix} 关闭
=================================="
        read -e -p "(默认: 2.HTTP): " obfs_input
        [[ -z "${obfs_input}" ]] && obfs_input="2"
        if [[ ${obfs_input} == "1" ]]; then
            obfs="tls"
        elif [[ ${obfs_input} == "2" ]]; then
            obfs="http"
        elif [[ ${obfs_input} == "3" ]]; then
            obfs="off"
        else
            echo -e "${Warn} 无效输入! 将取默认值${Yellow_font_prefix} 3.关闭 ${Font_color_suffix}"
            obfs="off"
        fi
    fi
    echo && echo "=================================="
    echo -e "OBFS 状态: ${Red_background_prefix} ${obfs} ${Font_color_suffix}"
    echo "==================================" && echo
}

# 设置 OBFS 域名
Set_host(){
	echo -e "请输入 Snell Server 域名, ${Tip} v4 版本及以上如无特别需求可忽略"
	read -e -p "(默认: icloud.com): " host
	[[ -z "${host}" ]] && host=icloud.com
	echo && echo "=============================="
	echo -e "域名 : ${Red_background_prefix} ${host} ${Font_color_suffix}"
	echo "==============================" && echo
}

# 设置协议版本
Set_ver(){
	echo -e "配置 Snell Server 协议版本${Yellow_font_prefix}[1-5]${Font_color_suffix} 
==================================
${Green_font_prefix} 1.${Font_color_suffix} v1 ${Green_font_prefix} ${Green_font_prefix} 2.${Font_color_suffix} v2 ${Green_font_prefix} 3.${Font_color_suffix} v3 ${Green_font_prefix} 4.${Font_color_suffix} v4 ${Green_font_prefix} 5.${Font_color_suffix} v5 
=================================="
	read -e -p "(默认: 5.v5): " ver
	[[ -z "${ver}" ]] && ver="5"
	if [[ ${ver} == "1" ]]; then
		ver=1
	elif [[ ${ver} == "2" ]]; then
		ver=2
	elif [[ ${ver} == "3" ]]; then
		ver=3
	elif [[ ${ver} == "4" ]]; then
		ver=4
	elif [[ ${ver} == "5" ]]; then
		ver=5	
	else
	     echo -e "${Warn} 无效输入! 将取默认值${Yellow_font_prefix} v5${Font_color_suffix}"
	     ver=5
	fi
	echo && echo "=================================="
	echo -e "Snell Server 协议版本: ${Red_background_prefix} v${ver} ${Font_color_suffix}"
	echo "==================================" && echo
}

# 设置 TCP Fast Open
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
	elif [[ ${tfo} == "2" ]]; then 
	     tfo=false
	else
	     echo -e "${Warn} 无效输入! 将取默认值${Yellow_font_prefix} 1.开启 ${Font_color_suffix}"
	     tfo=true
	     enable_systfo
	fi
	echo && echo "=================================="
	echo -e "TCP Fast Open 开启状态: ${Red_background_prefix} ${tfo} ${Font_color_suffix}"
	echo "==================================" && echo
}

# 设置 DNS
Set_dns(){
	echo -e "${Tip} 请输入正确格式的的 DNS, 多条记录以英文逗号隔开, 仅支持 ${Yellow_font_prefix}[v4.1.0b1]${Font_color_suffix} 及以上版本"
	read -e -p "(默认值: 1.1.1.1, 8.8.8.8, 2001:4860:4860::8888): " dns
	[[ -z "${dns}" ]] && dns="1.1.1.1, 8.8.8.8, 2001:4860:4860::8888"
	echo && echo "=================================="
	echo -e "当前 DNS 为: ${Red_background_prefix} ${dns} ${Font_color_suffix}"
	echo "==================================" && echo
}

# 输出 snell 配置信息
Output_Snell(){
     getipcity
     getipv4
     echo -e "—————————————————————————"
     echo -e "${Green_font_prefix}Please copy the following lines to the Surge [Proxy] section:${Font_color_suffix}" 
     if [[ "${obfs}" == "off" ]]; then
            echo "${ip_city} = snell, ${ipv4}, ${port}, psk=${psk}, version=${ver}, reuse=true, tfo=${tfo}"
     else
            echo "${ip_city} = snell, ${ipv4}, ${port}, psk=${psk}, obfs=${obfs}, obfs-host=${host}, version=${ver}, reuse=true, tfo=${tfo}"
     fi
     echo -e "—————————————————————————"
}

# 修改配置
Set(){
	check_installed_status
	echo
	echo -e "请输入要操作配置项的序号, 然后回车
==============================
 ${Green_font_prefix}1.${Font_color_suffix}  修改 端口
 ${Green_font_prefix}2.${Font_color_suffix}  修改 密钥
 ${Green_font_prefix}3.${Font_color_suffix}  配置 OBFS
 ${Green_font_prefix}4.${Font_color_suffix}  配置 OBFS 域名
 ${Green_font_prefix}5.${Font_color_suffix}  开关 IPv6 解析
 ${Green_font_prefix}6.${Font_color_suffix}  开关 TCP Fast Open"

Read_config
if [[ "${ver}" = "4" || "${ver}" = "5" ]]; then
    echo -e " ${Green_font_prefix}7.${Font_color_suffix}  配置 DNS"
    echo -e " ${Green_font_prefix}8.${Font_color_suffix}  配置 Snell Server 协议版本
==============================
 ${Green_font_prefix}9.${Font_color_suffix}  修改 全部配置"
        echo
	read -e -p "(默认: 取消): " modify
	[[ -z "${modify}" ]] && echo "已取消..." && exit 1
	if [[ "${modify}" == "1" ]]; then
		Read_config
		Set_port
		Write_config
		Restart
	elif [[ "${modify}" == "2" ]]; then
		Read_config
		Set_psk
		Write_config
		Restart
	elif [[ "${modify}" == "3" ]]; then
		Read_config
		Set_obfs
		if [[ "${obfs}" != "off" ]]; then
               Set_host  
          fi
		Write_config
		Restart
	elif [[ "${modify}" == "4" ]]; then
		Read_config
		if [[ "${obfs}" = "off" ]]; then
		echo -e "${Error} 当前 obfs 处于关闭状态, 请先开启后再设置 obfs-host" && exit 1
		else Set_host
		fi
		Write_config
		Restart
	elif [[ "${modify}" == "5" ]]; then
		Read_config
		Set_ipv6
		Write_config
		Restart
	elif [[ "${modify}" == "6" ]]; then
		Read_config
		Set_tfo
		Write_config
		Restart
	elif [[ "${modify}" == "7" ]]; then
		Read_config
		Set_dns
		Write_config
		Restart
	elif [[ "${modify}" == "8" ]]; then
		Read_config
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
                if [[ "${ver}" = "4" || "${ver}" = "5" ]]; then
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
	read -e -p "(默认: 取消): " modify
	[[ -z "${modify}" ]] && echo "已取消..." && exit 1
	if [[ "${modify}" == "1" ]]; then
		Read_config
		Set_port
		Write_config
		Restart
	elif [[ "${modify}" == "2" ]]; then
		Read_config
		Set_psk
		Write_config
		Restart
	elif [[ "${modify}" == "3" ]]; then
		Read_config
		Set_obfs
		if [[ "${obfs}" != "off" ]]; then
               Set_host  
        fi
		Write_config
		Restart
	elif [[ "${modify}" == "4" ]]; then
		Read_config
		if [[ "${obfs}" = "off" ]]; then
		echo -e "${Error} 当前 obfs 处于关闭状态, 请先开启后再设置 obfs-host" && exit 1
		else Set_host
		fi
		Write_config
		Restart
	elif [[ "${modify}" == "5" ]]; then
		Read_config
		Set_ipv6
		Write_config
		Restart
	elif [[ "${modify}" == "6" ]]; then
		Read_config
		Set_tfo
		Write_config
		Restart
	elif [[ "${modify}" == "7" ]]; then
		Read_config
		Set_ver
		if [[ "${ver}" = "4" || "${ver}" = "5" ]]; then
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
          if [[ "${ver}" = "4" || "${ver}" = "5" ]]; then
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

# 统一的安装函数
Install_Snell(){
    local version=$1            # 版本号，如 1/2/3/4/5
    check_root  
    echo -e "${Info} 开始设置 配置..." && echo
    Set_port
    Set_psk
    Set_obfs
    [[ "$obfs" != "off" ]] && Set_host        # 只在开启 obfs 时询问 host
    Set_ipv6
    Set_tfo
    (( ver >= 4 )) && Set_dns                 # v4 及以上才支持 DNS 设置
    
    echo -e "${Info} 开始安装/配置 依赖..."
    Install_dependencies
    
    echo -e "${Info} 开始下载/安装..."
    # 动态调用对应版本的下载函数
    "v${version}_Download"
    
    echo -e "${Info} 开始写入 配置文件..."
    Write_config
    
    echo -e "${Info} 开始安装 服务脚本..."
    Service
    
    echo -e "${Info} 所有步骤 安装完毕, 开始启动..."
    Start
    Output_Snell
}

# 为了兼容性，保留原函数名作为包装器
Install_v1(){ Install_Snell 1; }
Install_v2(){ Install_Snell 2; }
Install_v3(){ Install_Snell 3; }
Install_v4(){ Install_Snell 4; }
Install_v5(){ Install_Snell 5; }

# 启动 Snell
Start(){
	check_installed_status
	check_status
	if [[ "$status" == "running" ]]; then
           echo -e "${Info} Snell Server 已在运行 !"
        else
           systemctl start snell-server
           check_status
           if [[ "$status" == "running" ]]; then
              echo -e "${Info} Snell Server 启动成功 !"
              sleep 3s
              start_menu            
           else
              echo -e "${Error} Snell Server 启动失败 !"
              exit 1
           fi
        fi
}

# 停止 Snell
Stop(){
	check_installed_status
	check_status
	[[ ! "$status" == "running" ]] && echo -e "${Error} Snell Server 没有运行,请检查 !" && exit 1
	systemctl stop snell-server
	echo -e "${Info} Snell Server 停止成功 !"
    sleep 3s
    start_menu
}

# 重启 Snell
Restart(){
	check_installed_status
     systemctl daemon-reload
	systemctl restart snell-server
	echo -e "${Info} Snell Server 重启完毕 !"
	sleep 3s
	View
    start_menu
}

# 更新 Snell
Update(){
	check_installed_status
	echo -e "${Info} Snell Server 更新完毕 !"
     sleep 3s
     start_menu
}

# 卸载 Snell
Uninstall(){
    check_installed_status
    echo "确定要卸载 Snell Server ? (y/N)"
    echo
    read -e -p "(默认: n): " unyn
    [[ -z ${unyn} ]] && unyn="n"
    if [[ ${unyn} == [Yy] ]]; then
        echo "正在停止 Snell Server 服务..."
        systemctl stop snell-server
        if [[ $? -eq 0 ]]; then
            echo -e "${Info} Snell Server 服务已停止"
        else
            echo -e "${Error} 停止服务失败,请手动检查"
        fi

        echo "正在禁用 Snell Server 服务..."
        systemctl disable snell-server
        if [[ $? -eq 0 ]]; then
            echo -e "${Info} Snell Server 服务已禁用"
        else
            echo -e "${Error} 禁用服务失败,请手动检查"
        fi

        echo "正在删除 Snell Server 主程序和配置文件..."
        rm -rf "${FILE}"
        if [[ $? -eq 0 ]]; then
            echo -e "${Info} Snell Server 主程序删除完成"
        else
            echo -e "${Error} 删除 Snell Server 主程序失败,请手动检查"
        fi
        
        rm -rf "${FOLDER}"
        if [[ $? -eq 0 ]]; then
            echo -e "${Info} Snell Server 配置文件删除完成"
        else
            echo -e "${Error} 删除配置文件失败,请手动检查"
        fi

        echo -e "—————————————————————————"
	echo -e "${Info} ${Yellow_font_prefix}Snell Server 卸载完成 !${Font_color_suffix}"
    else
        echo && echo "卸载已取消..." && echo
    fi
    sleep 2s
    start_menu
}

# 获取 IP 位置信息
getipcity(){
     ip_city=$(curl -s ipinfo.io/city)
     if [[ -z "${ip_city}" ]]; then
		ip_city=$(curl -s https://api.myip.la/en?json | jq '.location' | jq -r '.city')
                if [[ -z "${ipv4}" ]]; then
		   ipv4=$(uname -n)
	        fi
     fi
}

# 获取 IPv4 地址
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

# 获取 IPv6 地址
getipv6(){
	ipv6=$(wget -qO- -6 -t1 -T2 ifconfig.co)
	if [[ -z "${ipv6}" ]]; then
		ipv6="IPv6_Error"
	fi
}

# 查看配置信息
View(){
	check_installed_status
	Read_config
	getipv4
	getipv6
	clear && echo
	echo -e "Snell Server 配置信息: "
	echo -e "—————————————————————————"
	[[ "${ipv4}" != "IPv4_Error" ]] && echo -e " IPV4\t: ${Green_font_prefix}${ipv4}${Font_color_suffix}"
	[[ "${ipv6}" != "IPv6_Error" ]] && echo -e " IPV6\t: ${Green_font_prefix}${ipv6}${Font_color_suffix}"
	echo -e " 端口\t: ${Green_font_prefix}${port}${Font_color_suffix}"
	echo -e " 密钥\t: ${Green_font_prefix}${psk}${Font_color_suffix}"
	echo -e " OBFS\t: ${Green_font_prefix}${obfs}${Font_color_suffix}"
     if [[ -n "${host}" ]]; then
          echo -e " 域名\t: ${Green_font_prefix}${host}${Font_color_suffix}"
     fi
	echo -e " TFO\t: ${Green_font_prefix}${tfo}${Font_color_suffix}"
     if [[ -n "${dns}" && "${ver}" -ge 4 ]]; then
	     echo -e " DNS\t: ${Green_font_prefix}${dns}${Font_color_suffix}"
	fi
	echo -e " VER\t: ${Green_font_prefix}${ver}${Font_color_suffix}"
	echo -e "—————————————————————————"
	echo
	before_start_menu
}

# 查看 Snell 运行状态
Status(){
	echo -e "${Info} 获取 Snell Server 运行状态 ..."
	echo -e "${Tip} ${Yellow_font_prefix}返回主菜单请按 q${Font_color_suffix} "
	systemctl status snell-server
     sleep 1s
	before_start_menu
}

# 查看 Snell 服务日志
Journal(){
     echo -e "${Info} 获取 Snell Server 服务日志 ..."
	journalctl -u snell
	sleep 1s 
	before_start_menu
}

# 手动编辑 Snell 配置文件
Manual_Edit_Snell(){
    echo -e "${Tip} 请谨慎操作 !"
    echo
    echo -e "${Info} 获取 Snell Server 配置文件 ..."

    # 检查是否存在 CONF 配置文件
    if [ ! -f "$CONF" ]; then
        echo -e "${Error} Snell Server 配置文件不存在: ${CONF}"
        echo -e "${Tip} 请先安装 Snell Server 创建配置文件后重试 !"
        return 1
    fi

    # 检查是否安装了 nano
    if ! command -v nano &> /dev/null; then
        echo -e "${Tip} 未检测到 nano 编辑器 !"
        read -e -p "是否安装 nano ? [y/N]:(默认: y) " install_nano
        install_nano=${install_nano:-Y}
        if [[ "$install_nano" =~ ^[Yy]$ ]]; then
            # 检测系统包管理器并安装 nano
            if command -v apt &> /dev/null; then
                sudo apt update && sudo apt install nano -y
                nano "$CONF"
                echo -e "${Tip} 本步骤不涉及重启操作, 请自行重载重启服务 ! "
            elif command -v yum &> /dev/null; then
                sudo yum install nano -y
                nano "$CONF"
                echo -e "${Tip} 本步骤不涉及重启操作, 请自行重载重启服务 ! "
            else
                echo -e "${Error} 未知的包管理器! 请手动安装 nano."
                return 1
            fi
        else
            echo -e "${Info} 已取消安装 nano, 退出编辑配置文件..."
        fi
    else
    nano "$CONF"
    echo -e "${Tip} 本步骤不涉及重启操作, 请自行重载重启服务 ! "    
    fi

    sleep 2s
    # 返回主菜单
    start_menu
}

Set_Shadow_TLS_VER(){
echo -e "配置 Shadow-TLS 协议版本${Yellow_font_prefix}[2-3]${Font_color_suffix} 
==================================
${Green_font_prefix} 2.${Font_color_suffix} v2    ${Green_font_prefix} 3.${Font_color_suffix} v3 
=================================="
	read -e -p "(默认: 3.v3): " SHADOW_TLS_VER
	[[ -z "${SHADOW_TLS_VER}" ]] && SHADOW_TLS_VER="3"
	if [[ ${SHADOW_TLS_VER} == "2" ]]; then
		SHADOW_TLS_VER=2	
	elif
	     [[ ${SHADOW_TLS_VER} == "3" ]]; then
		SHADOW_TLS_VER=3
	else	
	     echo -e "${Warn} 无效输入! 将取默认值${Yellow_font_prefix} v3${Font_color_suffix}"
	     SHADOW_TLS_VER=3
	fi
	echo && echo "=================================="
	echo -e "Shadow-TLS 协议版本: ${Red_background_prefix} v${SHADOW_TLS_VER} ${Font_color_suffix}"
	echo "==================================" && echo
}

Set_Shadow_TLS_TFO(){
	echo -e "是否开启 Shadow-TLS TCP Fast Open ?
==================================
${Green_font_prefix} 1.${Font_color_suffix} 开启  ${Green_font_prefix} 2.${Font_color_suffix} 关闭
=================================="
	read -e -p "(默认: 1.开启): " SHADOW_TLS_TFO
	[[ -z "${SHADOW_TLS_TFO}" ]] && SHADOW_TLS_TFO="1"
	if [[ ${SHADOW_TLS_TFO} == "1" ]]; then
		SHADOW_TLS_TFO=true
	elif [[ ${SHADOW_TLS_TFO} == "2" ]]; then 
	     SHADOW_TLS_TFO=false
	else
	     echo -e "${Warn} 无效输入! 将取默认值${Yellow_font_prefix} 1.开启 ${Font_color_suffix}"
	     SHADOW_TLS_TFO=true
	fi
	echo && echo "=================================="
	echo -e "Shadow-TLS TCP Fast Open 开启状态: ${Red_background_prefix} ${SHADOW_TLS_TFO} ${Font_color_suffix}"
	echo "==================================" && echo
}

Set_Shadow_TLS_MODE(){
	echo -e "请选择 Shadow-TLS V3 模式, ${Tip} V3 loosy mode is able to defend against hijacking only if using TLS1.3 Handshake Server
==================================
${Green_font_prefix} 1.${Font_color_suffix} loosy  ${Green_font_prefix} 2.${Font_color_suffix} strict
=================================="
	read -e -p "(默认: 2.strict): " SHADOW_TLS_MODE
	[[ -z "${SHADOW_TLS_MODE}" ]] && SHADOW_TLS_MODE="2"
	if [[ ${SHADOW_TLS_MODE} == "1" ]]; then
		SHADOW_TLS_MODE="loosy"
	elif [[ ${SHADOW_TLS_MODE} == "2" ]]; then 
	     SHADOW_TLS_MODE="strict"
	else
	     echo -e "${Warn} 无效输入! 将取默认值${Yellow_font_prefix} 2.strict ${Font_color_suffix}"
	     SHADOW_TLS_MODE="strict"
	fi
	echo && echo "=================================="
	echo -e "Shadow-TLS V3 mode: ${Red_background_prefix} ${SHADOW_TLS_MODE} ${Font_color_suffix}"
	echo "==================================" && echo
}

Set_Shadow_TLS_WILDCARD_SNI(){
	echo -e "配置 wildcard-sni, Use sni:443 as handshake server without predefining mapping(useful for bypass billing system like airplane wifi without modifying server config)
${Tip} Possible values:
       - \e[1moff\e[0m:    Disabled
       - \e[1mauthed\e[0m: For authenticated client only(may be differentiable); in v2 protocol it is eq to all
       - \e[1mall\e[0m:    For all request(may cause service abused but not differentiable)
==================================
${Green_font_prefix} 1.${Font_color_suffix} off  ${Green_font_prefix} 2.${Font_color_suffix} authed  ${Green_font_prefix} 3.${Font_color_suffix} all
=================================="
	read -e -p "(默认: 1.off): " SHADOW_TLS_WILDCARD_SNI
	[[ -z "${SHADOW_TLS_WILDCARD_SNI}" ]] && SHADOW_TLS_WILDCARD_SNI="1"
	if [[ ${SHADOW_TLS_WILDCARD_SNI} == "1" ]]; then
		SHADOW_TLS_WILDCARD_SNI="off"
	elif [[ ${SHADOW_TLS_WILDCARD_SNI} == "2" ]]; then 
	     SHADOW_TLS_WILDCARD_SNI="authed"
	elif [[ ${SHADOW_TLS_WILDCARD_SNI} == "3" ]]; then 
	     SHADOW_TLS_WILDCARD_SNI="all"    
	else
	     echo -e "${Warn} 无效输入! 将取默认值${Yellow_font_prefix} 1.off ${Font_color_suffix}"
	     SHADOW_TLS_WILDCARD_SNI="off"
	fi
	echo && echo "=================================="
	echo -e "Shadow-TLS wildcard-sni: ${Red_background_prefix} ${SHADOW_TLS_WILDCARD_SNI} ${Font_color_suffix}"
	echo "==================================" && echo
}

Set_Shadow_TLS_IPVER(){
echo -e "请选择 Shadow-TLS 监听 v4 or v6 地址(默认: v4) ?  ${Tip} 一般系统已启用 IPv6 双栈支持
==================================
${Green_font_prefix} 1.${Font_color_suffix} v4  ${Green_font_prefix} 2.${Font_color_suffix} v6
=================================="
     read -e -p "(默认: 1.v4): " SHADOW_TLS_IPVER
     [[ -z "${SHADOW_TLS_IPVER}" ]] && SHADOW_TLS_IPVER="1"
     if [[ ${SHADOW_TLS_IPVER} == "1" ]]; then
		SHADOW_TLS_IPVER="0.0.0.0"
		echo && echo "=================================="
		echo -e "Shadow-TLS 监听地址类型: ${Red_background_prefix} v4 ${Font_color_suffix}"
		echo "==================================" && echo
     elif  [[ ${SHADOW_TLS_IPVER} == "2" ]]; then 
		SHADOW_TLS_IPVER="::0"
		echo && echo "=================================="
		echo -e "Shadow-TLS 监听地址类型: ${Red_background_prefix} v6 ${Font_color_suffix}"
		echo "==================================" && echo
     else 
          echo -e "${Warn} 无效输入! 将取默认值${Yellow_font_prefix} v4 ${Font_color_suffix}"
		SHADOW_TLS_IPVER="0.0.0.0"
		echo && echo "=================================="
		echo -e "Shadow-TLS 监听地址类型: ${Red_background_prefix} v4 ${Font_color_suffix}"
		echo "==================================" && echo		
     fi
}

Set_Shadow_TLS_PORT(){
    echo -e "请输入 Shadow-TLS 监听端口${Yellow_font_prefix}[1-65535]${Font_color_suffix}"
# 循环直到用户输入有效的 SHADOW_TLS_PORT 值
while true; do
    # 提示用户输入 SHADOW_TLS_PORT 值
    read -e -p "(默认: 8443): " SHADOW_TLS_PORT

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
echo && echo "=============================="
	echo -e "Shadow-TLS 监听端口: ${Red_background_prefix} ${SHADOW_TLS_PORT} ${Font_color_suffix}"
	echo "==============================" && echo
}

Edit_Shadow_TLS_PORT(){
    echo -e "请输入 Shadow-TLS 监听端口${Yellow_font_prefix}[1-65535]${Font_color_suffix}"
    # 循环直到用户输入有效的 SHADOW_TLS_PORT 值
while true; do
    # 提示用户输入 SHADOW_TLS_PORT 值
    read -e -p "(默认: 8443): " SHADOW_TLS_PORT

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
    echo && echo "=============================="
    echo -e "Shadow-TLS 监听端口: ${Red_background_prefix} ${SHADOW_TLS_PORT} ${Font_color_suffix}"
    echo "==============================" && echo
}

Set_Shadow_TLS_SNI() {
    local default_domain="swcdn.apple.com"
    local choices=(
        "swcdn.apple.com"
        "mensura.cdn-apple.com"
        "gateway.icloud.com"
    )

    echo -e "请选择 Shadow-TLS TLS SNI 名称: "
    echo "=============================="
    # -------- 左对齐显示菜单（数字绿色） --------
    printf "  ${Green_font_prefix}1${Font_color_suffix}) %-24s\n" "${choices[0]}"
    printf "  ${Green_font_prefix}2${Font_color_suffix}) %-24s\n" "${choices[1]}"
    printf "  ${Green_font_prefix}3${Font_color_suffix}) %-24s\n" "${choices[2]}"
    printf "  ${Green_font_prefix}4${Font_color_suffix}) %-24s\n" "Custom domain"
    echo "=============================="
    # ---------- 读取菜单选项 ----------
    local sel
    while true; do
        read -rep "请输入选项 [1-4] (默认 1): " sel
        sel=${sel:-1}                     # 回车等同于 1
        case "$sel" in
            1|2|3)                        # 直接使用预设域名
                SHADOW_TLS_SNI="${choices[$((sel-1))]}"
                break
                ;;
            4)                            # 进入自定义
                read -rep "请输入自定义域名 (默认: $default_domain): " custom
                SHADOW_TLS_SNI="${custom:-$default_domain}"
                break
                ;;
            *)  echo "${Error} 请输入正确的数字 [1-4]" ;;
        esac
    done

    # ---------- 输出结果 ----------
    echo
    echo "=============================="
    echo -e "Shadow-TLS TLS 服务器名称: ${Red_background_prefix} ${SHADOW_TLS_SNI} ${Font_color_suffix}"
    echo "=============================="
    echo
}

Set_Shadow_TLS_PWD() {
    local default_pwd="JsJeWtjiUyJ5yeto"

    echo -e "请选择 Shadow-TLS 密码: "
    echo "=============================="
    printf "  ${Green_font_prefix}1${Font_color_suffix}) %-24s\n" "$default_pwd"
    printf "  ${Green_font_prefix}2${Font_color_suffix}) %-24s\n" "Generate a random string"
    printf "  ${Green_font_prefix}3${Font_color_suffix}) %-24s\n" "Enter a custom password"
    echo "=============================="

    # ---------- 读取菜单选项 ----------
    local sel
    while true; do
        read -rep "请输入选项 [1-3] (默认 1): " sel
        sel=${sel:-1}               # 直接回车 = 1
        case "$sel" in
            1)
                SHADOW_TLS_PWD="$default_pwd"
                break
                ;;
            2)
                # 生成 16 位 [A-Z a-z 0-9] 随机串
                SHADOW_TLS_PWD="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16)"
                # 理论上极少数情况下长度可能不足，再兜底一次
                while [[ ${#SHADOW_TLS_PWD} -lt 16 ]]; do
                    SHADOW_TLS_PWD+=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c $((16-${#SHADOW_TLS_PWD})))
                done
                break
                ;;
            3)
                # ---------- 自定义密码 ----------
                local custom_pwd
                while true; do
                    read -rep "请输入自定义密码(至少 6 位, 回车重新输入): " custom_pwd
                    if [[ -z "$custom_pwd" ]]; then
                        echo -e "${Error} 密码不能为空, 请重新输入 !"
                    elif [[ ${#custom_pwd} -lt 6 ]]; then
                        echo -e "${Error} 长度不足 6 位, 请重新输入 !"
                    else
                        SHADOW_TLS_PWD="$custom_pwd"
                        break
                    fi
                done
                break
                ;;
            *)
                echo "${Error} 请输入正确的数字 [1-3]"
                ;;
        esac
    done

    # ---------- 输出结果 ----------
    echo
    echo "=============================="
    echo -e "Shadow-TLS 密码: ${Red_background_prefix} ${SHADOW_TLS_PWD} ${Font_color_suffix}"
    echo "=============================="
    echo
}

Sys_edition(){
    system_arch=$(uname -m)
    os=$(uname -s | tr '[:upper:]' '[:lower:]')
    
    case "$system_arch-$os" in
        x86_64-linux)
            EDITION="x86_64-unknown-linux-musl"
            ;;
        x86_64-darwin)
            EDITION="x86_64-apple-darwin"
            ;;
        aarch64-linux)
            EDITION="aarch64-unknown-linux-musl"
            ;;
        aarch64-darwin)
            EDITION="aarch64-apple-darwin"
            ;;
        arm-linux)
            EDITION="arm-unknown-linux-musleabi"
            ;;
        armv7-linux)
            EDITION="armv7-unknown-linux-musleabihf"
            ;;
        *)
            echo -e "${Error} 不支持的架构内核: $system_arch-$os !"
            return
            ;;
    esac
    echo -e "${Info} 检测到适配的架构内核: ${EDITION}"
}

Download_Shadow_TLS(){
    echo -e "${Info} 开始下载/安装..."
   
    # 获取最新的版本
        SHADOW_TLS_LATEST_VER=$(curl -s "https://api.github.com/repos/ihciah/shadow-tls/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        if [ -z "$SHADOW_TLS_LATEST_VER" ]; then
            echo "${Error} 获取 Shadow-TLS 最新版本失败 !"   
            exit 1
        else 
            echo -e "${Info} 检测到 Shadow-TLS 最新版本为 [ ${SHADOW_TLS_LATEST_VER} ]"    
        fi

    # 下载 shadow-tls 并检查是否成功
    Sys_edition
    SHADOW_TLS_URL="https://github.com/ihciah/shadow-tls/releases/download/${SHADOW_TLS_LATEST_VER}/shadow-tls-${EDITION}"
    if wget -q --show-progress "${SHADOW_TLS_URL}" -O "${Shadow_TLS_FILE}"; then
        chmod +x "${Shadow_TLS_FILE}"
        echo -e "${Info} Shadow-TLS 主程序下载安装完毕!"
    else
        echo -e "${Error} Shadow-TLS 下载失败!"
        exit 1
    fi
}

Write_Shadow_TLS_Config() {
    # -------- 拼接 ExecStart 参数 --------
    local args=()

    [[ ${SHADOW_TLS_TFO}   == true  ]] && args+=(--fastopen)
    if [[ ${SHADOW_TLS_VER} -ge 3 && ${SHADOW_TLS_MODE} == strict ]]; then
        args+=(--strict)
    fi

    # ≥3 才需要显式指定版本号
    if [[ ${SHADOW_TLS_VER} -ge 3 ]]; then
        args+=(--v"${SHADOW_TLS_VER}")
    fi

    args+=(server)
    args+=(--wildcard-sni="${SHADOW_TLS_WILDCARD_SNI}")

    args+=(--listen "${SHADOW_TLS_IPVER}:${SHADOW_TLS_PORT}"
          --server  "127.0.0.1:${port}"
          --tls     "${SHADOW_TLS_SNI}"
          --password "${SHADOW_TLS_PWD}" )

    # 把数组展平成字符串
    local exec_start="${Shadow_TLS_FILE} ${args[*]}"

    # -------- 写入 systemd 单元 --------
    sudo tee "${service_file}" >/dev/null <<EOF
[Unit]
Description=Shadow-TLS Server Service
Documentation=man:sstls-server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${exec_start}
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=shadow-tls

[Install]
WantedBy=multi-user.target
EOF
}

Install_Shadow_TLS(){
    [[ -e ${Shadow_TLS_FILE} ]] && echo -e "${Error} 检测到 Shadow-TLS 已安装 ,请先卸载再执行安装!" && exit 1
    Set_Shadow_TLS_VER
    Set_Shadow_TLS_TFO
    (( SHADOW_TLS_VER >= 3 )) && Set_Shadow_TLS_MODE
    Set_Shadow_TLS_WILDCARD_SNI
    Set_Shadow_TLS_IPVER
    Set_Shadow_TLS_PORT
    Set_Shadow_TLS_SNI
    Set_Shadow_TLS_PWD
    Download_Shadow_TLS

    # 查看Snell Server配置信息
    Read_config

    # 创建systemd服务文件
    echo -e "${Info} 开始安装 服务脚本..."
    Write_Shadow_TLS_Config

    # 重新加载systemd守护进程并启动服务
    sudo systemctl daemon-reload
    sudo systemctl enable shadow-tls.service
    echo -e "${Info} Shadow-TLS 服务配置完成 !"
    echo -e "${Info} 所有步骤 安装完毕, 开始启动..."

    # 启动服务
    if sudo systemctl start shadow-tls.service; then
        # 提取服务状态
        check_Shadow_TLS_status
        if [ "$status" == "running" ]; then
            echo -e "${Info} ${Yellow_font_prefix}Shadow-TLS 服务已成功启动并且正在运行 !${Font_color_suffix}"
            Output_Shadow_TLS
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

Uninstall_Shadow_TLS(){
    check_Shadow_TLS_installed_status
    echo "确定要卸载 Shadow-TLS ? (y/N)"
    echo
    read -e -p "(默认: n): " ynun
    [[ -z "${ynun}" ]] && ynun="n" # 如果用户没有输入,设置默认值为 'n'
    
    if [[ "${ynun}" =~ ^[Yy]$ ]]; then
        # 检查服务是否启动
        if systemctl is-enabled --quiet shadow-tls.service; then
            echo "正在停止 shadow-tls 服务..."
            sudo systemctl stop shadow-tls.service >/dev/null 2>&1
            if [[ $? -eq 0 ]]; then
            echo -e "${Info} shadow-tls 服务已停止"
            else
            echo -e "${Error} 停止服务失败,请手动检查"
            fi
           
            echo "正在禁用 shadow-tls 服务..."
            sudo systemctl disable shadow-tls.service
            if [[ $? -eq 0 ]]; then
            echo -e "${Info} shadow-tls 服务已禁用"
            else
            echo -e "${Error} 禁用服务失败,请手动检查"
            fi
        else
            echo -e "${Warn} shadow-tls 服务已被禁用"
            echo "正在停止 shadow-tls 服务..."
            sudo systemctl stop shadow-tls.service
            if [[ $? -eq 0 ]]; then
            echo -e "${Info} shadow-tls 服务已停止"
            else
            echo -e "${Warn} 停止服务失败,请手动检查"
            fi
        fi

        # 检查服务文件是否存在并删除
        if [ -f "${service_file}" ]; then
            echo "正在删除服务文件..."
            sudo rm "${service_file}"
            if [[ $? -eq 0 ]]; then
            echo -e "${Info} shadow-tls 服务文件已删除"
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
            echo -e "${Info} shadow-tls 可执行文件删除完成"
            else
            echo -e "${Error} 删除shadow-tls 可执行文件失败,请手动检查"
            fi
        
	echo -e "—————————————————————————"
        echo -e "${Info} ${Yellow_font_prefix}Shadow-TLS 服务已成功卸载 !${Font_color_suffix}"
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
    sleep 2s
    start_menu
}

Restart_Check_Shadow_TLS(){
    # 重新加载systemd守护进程
    sudo systemctl daemon-reload

    # 重启服务
    if sudo systemctl restart shadow-tls.service; then
        # 提取服务状态
        check_Shadow_TLS_status
        if [ "$shadow_tls_status" == "running" ]; then
            echo -e "${Info} 服务已成功重启并且正在运行 !"
            Output_Shadow_TLS
        else
            echo -e "${Error} 服务未在运行状态,请手动检查"
            systemctl status shadow-tls.service
        fi
    else
        echo -e "${Error} 错误: 重启 shadow-tls 服务失败"
	   systemctl status shadow-tls.service
        exit 1
    fi
}

Stop_Shadow_TLS(){
     check_Shadow_TLS_installed_status
	check_Shadow_TLS_status
	[[ ! "$shadow_tls_status" == "running" ]] && echo -e "${Error} Shadow-TLS 未在运行,请检查 !" && exit 1
	systemctl stop shadow-tls
	echo -e "${Info} Shadow-TLS 停止成功 !"
    sleep 3s
    start_menu
}

Restart_Shadow_TLS(){
     check_Shadow_TLS_installed_status
        systemctl daemon-reload
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
	before_start_menu
}

Journal_Shadow_TLS(){
     echo -e "${Info} 获取 Shadow-TLS 服务日志 ..."
	journalctl -u shadow-tls
	sleep 1s
	before_start_menu
}

Output_Shadow_TLS(){
echo -e "—————————————————————————"
            echo -e "${Green_font_prefix}Please copy the following lines to the Surge [Proxy] section:${Font_color_suffix}"
            # 先获取 IPv4 和 IPv6 地址
            ipv4_addr=$(curl -s --connect-timeout 5 ip.sb -4)
            ipv6_addr=$(curl -s --connect-timeout 5 ip.sb -6)
            ip_city=$(curl -s ipinfo.io/city) 
            
    if [[ "${SHADOW_TLS_IPVER}" == "::0" ]]; then
            if [[ "${obfs}" == "off" ]]; then
                 if [[ -n "$ipv6_addr" ]]; then
                 echo "${ip_city} = snell, ${ipv6_addr}, ${SHADOW_TLS_PORT}, psk=${psk}, version=${ver}, reuse=true, tfo=${tfo}, shadow-tls-password=${SHADOW_TLS_PWD}, shadow-tls-sni=${SHADOW_TLS_SNI}, shadow-tls-version=${SHADOW_TLS_VER}"
                 echo -e "—————————————————————————"
                 echo "${ip_city} = snell, ${ipv4_addr}, ${SHADOW_TLS_PORT}, psk=${psk}, version=${ver}, reuse=true, tfo=${tfo}, shadow-tls-password=${SHADOW_TLS_PWD}, shadow-tls-sni=${SHADOW_TLS_SNI}, shadow-tls-version=${SHADOW_TLS_VER}"
                 else
                 echo "IPv6 is not available."
                 echo -e "—————————————————————————"
                 echo "${ip_city} = snell, ${ipv4_addr}, ${SHADOW_TLS_PORT}, psk=${psk}, version=${ver}, reuse=true, tfo=${tfo}, shadow-tls-password=${SHADOW_TLS_PWD}, shadow-tls-sni=${SHADOW_TLS_SNI}, shadow-tls-version=${SHADOW_TLS_VER}"
                 fi
            else
                 if [[ -n "$ipv6_addr" ]]; then
                 echo "${ip_city} = snell, ${ipv6_addr}, ${SHADOW_TLS_PORT}, psk=${psk}, obfs=${obfs}, obfs-host=${host}, version=${ver}, reuse=true, tfo=${tfo}, shadow-tls-password=${SHADOW_TLS_PWD}, shadow-tls-sni=${SHADOW_TLS_SNI}, shadow-tls-version=${SHADOW_TLS_VER}"
                 echo -e "—————————————————————————"
                 echo "${ip_city} = snell, ${ipv4_addr}, ${SHADOW_TLS_PORT}, psk=${psk}, obfs=${obfs}, obfs-host=${host}, version=${ver}, reuse=true, tfo=${tfo}, shadow-tls-password=${SHADOW_TLS_PWD}, shadow-tls-sni=${SHADOW_TLS_SNI}, shadow-tls-version=${SHADOW_TLS_VER}"
                 else
                 echo "IPv6 is not available."
                 echo -e "—————————————————————————"
                 echo "${ip_city} = snell, ${ipv4_addr}, ${SHADOW_TLS_PORT}, psk=${psk}, obfs=${obfs}, obfs-host=${host}, version=${ver}, reuse=true, tfo=${tfo}, shadow-tls-password=${SHADOW_TLS_PWD}, shadow-tls-sni=${SHADOW_TLS_SNI}, shadow-tls-version=${SHADOW_TLS_VER}"
                 fi                 
            fi
    else
            if [[ "${obfs}" == "off" ]]; then
            echo "$(curl -s ipinfo.io/city) = snell, ${ipv4_addr}, ${SHADOW_TLS_PORT}, psk=${psk}, version=${ver}, reuse=true, tfo=${tfo}, shadow-tls-password=${SHADOW_TLS_PWD}, shadow-tls-sni=${SHADOW_TLS_SNI}, shadow-tls-version=${SHADOW_TLS_VER}"
            else
            echo "$(curl -s ipinfo.io/city) = snell, ${ipv4_addr}, ${SHADOW_TLS_PORT}, psk=${psk}, obfs=${obfs}, obfs-host=${host}, version=${ver}, reuse=true, tfo=${tfo}, shadow-tls-password=${SHADOW_TLS_PWD}, shadow-tls-sni=${SHADOW_TLS_SNI}, shadow-tls-version=${SHADOW_TLS_VER}"
            fi
    fi
            echo -e "—————————————————————————" && exit 1
}

check_Shadow_TLS_installed_status(){
	[[ ! -e ${Shadow_TLS_FILE} ]] && echo -e "${Error} Shadow-TLS 没有安装,请检查 !" && exit 1
}

check_Shadow_TLS_status(){
	shadow_tls_status=$(systemctl status shadow-tls.service | grep "Active" | awk -F'[()]' '{print $2}')
}

View_Shadow_TLS(){
     check_Shadow_TLS_installed_status
     Read_Shadow_TLS_config
     clear && echo
	echo -e "Shadow TLS 服务文件："
	echo -e "—————————————————————————"
	cat "${service_file}"
	echo -e "—————————————————————————"
	echo
	before_start_menu
}

Read_Shadow_TLS_config() {
    # 检查 /etc/systemd/system/shadow-tls.service 文件是否存在
    if [[ ! -e "${service_file}" ]]; then
        echo -e "${Error} Shadow TLS 服务文件不存在!"
        exit 1
    fi

    # 从 shadow-tls.service 文件中提取 ExecStart 行
    ExecStartLine=$(grep -E "^ExecStart=" "${service_file}")

    # 判断版本：出现 --v3 ⇒ 3，否则 ⇒ 2
    if [[ $ExecStartLine =~ --v3 ]]; then
    SHADOW_TLS_VER=3
    else
    SHADOW_TLS_VER=2
    fi

    # 检查是否包含 "fastopen"
    if [[ "$ExecStartLine" == *"fastopen"* ]]; then
    SHADOW_TLS_TFO=true
    else
    SHADOW_TLS_TFO=false
    fi

    # 检查是否包含 "strict"
    if [[ "$ExecStartLine" == *"strict"* ]]; then
    SHADOW_TLS_MODE="strict"
    else
    SHADOW_TLS_MODE="loosy"
    fi

    #SHADOW_TLS_WILDCARD_SNI=$(echo "$ExecStartLine" | awk -F'--wildcard-sni=' '{print $2}' | awk '{print $1}')
    SHADOW_TLS_WILDCARD_SNI=$(echo "$ExecStartLine" | sed -n 's/.*--wildcard-sni=\([^ ]*\).*/\1/p')
   
    # 提取监听地址 (SHADOW_TLS_IPVER)
    SHADOW_TLS_IPVER=$(echo "$ExecStartLine" | awk -F '--listen ' '{print $2}' | awk -F ' --' '{print $1}' | awk -F ':' '{OFS=":"; NF--; print}')

    # 提取端口号 (SHADOW_TLS_PORT)
    SHADOW_TLS_PORT=$(echo "$ExecStartLine" | awk -F '--listen ' '{print $2}' | awk -F ' --' '{print $1}' | awk -F ':' '{print $NF}')
    
    # 使用 awk 提取 SNI
    SHADOW_TLS_SNI=$(echo "$ExecStartLine" | awk -F '--tls ' '{print $2}' | awk '{print $1}')

    # 使用 awk 提取 --password 之后的部分
    SHADOW_TLS_PWD=$(echo "$ExecStartLine" | awk -F '--password ' '{print $2}' | awk '{print $1}')
}

Edit_Shadow_TLS_PORT(){
    Set_Shadow_TLS_PORT
    Write_Shadow_TLS_Config
    Restart_Check_Shadow_TLS
}

Edit_Shadow_TLS_SNI(){
    Set_Shadow_TLS_SNI
    Write_Shadow_TLS_Config
    Restart_Check_Shadow_TLS
}

Edit_Shadow_TLS_PWD(){
    Set_Shadow_TLS_PWD
    Write_Shadow_TLS_Config
    Restart_Check_Shadow_TLS
}

Edit_Shadow_TLS_IPVER(){
    Set_Shadow_TLS_IPVER
    Write_Shadow_TLS_Config
    Restart_Check_Shadow_TLS
}

Edit_Shadow_TLS_TFO(){
    Set_Shadow_TLS_TFO
    Write_Shadow_TLS_Config
    Restart_Check_Shadow_TLS
}

Edit_Shadow_TLS_MODE(){
    Set_Shadow_TLS_MODE
    Write_Shadow_TLS_Config
    Restart_Check_Shadow_TLS
}

Edit_Shadow_TLS_WILDCARD_SNI(){
    Set_Shadow_TLS_WILDCARD_SNI
    Write_Shadow_TLS_Config
    Restart_Check_Shadow_TLS
}

Edit_Shadow_TLS_VER(){
    Set_Shadow_TLS_VER
    Set_Shadow_TLS_MODE
    Write_Shadow_TLS_Config
    Restart_Check_Shadow_TLS
}

ReInstall_Shadow_TLS(){
    Set_Shadow_TLS_VER
    Set_Shadow_TLS_TFO
    (( SHADOW_TLS_VER >= 3 )) && Set_Shadow_TLS_MODE
    Set_Shadow_TLS_WILDCARD_SNI
    Set_Shadow_TLS_IPVER
    Edit_Shadow_TLS_PORT
    Set_Shadow_TLS_SNI
    Set_Shadow_TLS_PWD
    
    # 查看Snell Server配置信息
    Read_config
    
    # 创建systemd服务文件
    Write_Shadow_TLS_Config
    
    Restart_Check_Shadow_TLS
    sleep 2s
    start_menu
}

Set_Shadow_TLS() {
    check_Shadow_TLS_installed_status

    # 先读取当前配置，才能知道版本号
    Read_config
    Read_Shadow_TLS_config

    echo
    echo -e "请输入要操作配置项的序号，然后回车"
    echo -e "=============================="
    echo -e " ${Green_font_prefix}1.${Font_color_suffix}  修改 Shadow-TLS LISTEN PORT"
    echo -e " ${Green_font_prefix}2.${Font_color_suffix}  修改 Shadow-TLS TLS-SNI"
    echo -e " ${Green_font_prefix}3.${Font_color_suffix}  修改 Shadow-TLS PASSWORD"
    echo -e " ${Green_font_prefix}4.${Font_color_suffix}  修改 Shadow-TLS LISTEN TYPE"
    echo -e " ${Green_font_prefix}5.${Font_color_suffix}  开关 Shadow-TLS TCP Fast Open"

    if [[ ${SHADOW_TLS_VER} -ge 3 ]]; then
        echo -e " ${Green_font_prefix}6.${Font_color_suffix}  修改 Shadow-TLS MODE"
        echo -e " ${Green_font_prefix}7.${Font_color_suffix}  修改 Shadow-TLS WILDCARD-SNI"
        echo -e " ${Green_font_prefix}8.${Font_color_suffix}  修改 Shadow-TLS VER"
        echo -e "=============================="
        echo -e " ${Green_font_prefix}9.${Font_color_suffix}  修改 Shadow-TLS ALL CONFIG"
        local max_opt=9
    else
        echo -e " ${Green_font_prefix}6.${Font_color_suffix}  修改 Shadow-TLS WILDCARD-SNI"
        echo -e " ${Green_font_prefix}7.${Font_color_suffix}  修改 Shadow-TLS VER"
        echo -e "=============================="
        echo -e " ${Green_font_prefix}8.${Font_color_suffix}  修改 Shadow-TLS ALL CONFIG"
        local max_opt=8
    fi
    echo

    read -rep "(默认: 取消): " modify
    [[ -z $modify ]] && echo "已取消..." && exit 1

    case "$modify" in
        1) Edit_Shadow_TLS_PORT   ;;
        2) Edit_Shadow_TLS_SNI    ;;
        3) Edit_Shadow_TLS_PWD    ;;
        4) Edit_Shadow_TLS_IPVER  ;;
        5) Edit_Shadow_TLS_TFO    ;;

        6)
            if [[ ${SHADOW_TLS_VER} -ge 3 ]]; then
                Edit_Shadow_TLS_MODE          # v≥3: 6 = MODE
            else
                Edit_Shadow_TLS_WILDCARD_SNI  # v2 : 6 = WILDCARD-SNI
            fi
            ;;
        7)
            if [[ ${SHADOW_TLS_VER} -ge 3 ]]; then
                Edit_Shadow_TLS_WILDCARD_SNI  # v≥3: 7 = WILDCARD-SNI
            else
                Edit_Shadow_TLS_VER           # v2 : 7 = VER
            fi
            ;;
        8)
            if [[ ${SHADOW_TLS_VER} -ge 3 ]]; then
                Edit_Shadow_TLS_VER           # v≥3: 8 = VER
            else
                ReInstall_Shadow_TLS          # v2 : 8 = ALL CONFIG
            fi
            ;;
        9)
            if [[ ${SHADOW_TLS_VER} -ge 3 ]]; then
                ReInstall_Shadow_TLS          # v≥3: 9 = ALL CONFIG
            else
                echo -e "${Error} 请输入正确的数字${Yellow_font_prefix}[1-${max_opt}]${Font_color_suffix}"
                exit 1
            fi
            ;;
        *)
            echo -e "${Error} 请输入正确的数字${Yellow_font_prefix}[1-${max_opt}]${Font_color_suffix}"
            exit 1
            ;;
    esac

    sleep 3s
    start_menu
}

Manual_Edit_Shadow_TLS(){
    echo -e "${Tip} 请慎重操作 ! "
    echo
    echo -e "${Info} 获取 Shadow-TLS 服务文件 ..."

    # 检查是否存在配置文件
    if [ ! -f "${service_file}" ]; then
        echo -e "${Error} Shadow-TLS 配置文件不存在: ${service_file}"
        echo -e "${Tip} 请先安装 Shadow-TLS 创建服务文件后重试 !"
        return 1
    fi

    # 检查是否安装了 nano
    if ! command -v nano &> /dev/null; then
        echo -e "${Tip} 未检测到 nano 编辑器 !"
        read -e -p "是否安装 nano ? [y/N]:(默认: y) " install_nano
        install_nano=${install_nano:-Y}
        if [[ "$install_nano" =~ ^[Yy]$ ]]; then
            # 检测系统包管理器并安装 nano
            if command -v apt &> /dev/null; then
                sudo apt update && sudo apt install nano -y
                nano "${service_file}"
                echo -e "${Tip} 本步骤不涉及重启操作, 请自行重载重启服务 ! "
            elif command -v yum &> /dev/null; then
                sudo yum install nano -y
                nano "${service_file}"
                echo -e "${Tip} 本步骤不涉及重启操作, 请自行重载重启服务 ! "
            else
                echo -e "${Error} 未知的包管理器! 请手动安装 nano."
                return 1
            fi
        else
            echo -e "${Info} 已取消安装 nano, 退出编辑配置文件..."
        fi
    else
    nano "${service_file}"
    echo -e "${Tip} 本步骤不涉及重启操作, 请自行重载重启服务 ! "    
    fi

    sleep 2s
    # 返回主菜单
    start_menu
}

geo_check() {
    api_list="https://blog.cloudflare.com/cdn-cgi/trace https://dash.cloudflare.com/cdn-cgi/trace https://cf-ns.com/cdn-cgi/trace"
    ua="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36"
    set -- $api_list
    for url in $api_list; do
        text="$(curl -A "$ua" -m 10 -s $url)"
        endpoint="$(echo $text | sed -n 's/.*h=\([^ ]*\).*/\1/p')"
        if echo $text | grep -qw 'CN'; then
            isCN=true
            break
        elif echo $url | grep -q $endpoint; then
            break
        fi
    done
}

Update_Shell(){
     geo_check
     if [ ! -z "$isCN" ]; then
        shell_url="https://ghproxy.net/https://raw.githubusercontent.com/chentianqihub/surge/main/scripts/snell%2Bstls_new.sh"
     else
        shell_url="https://raw.githubusercontent.com/chentianqihub/surge/main/scripts/snell%2Bstls_new.sh"
     fi

	echo -e "当前版本为 [ ${sh_ver} ],开始检测最新版本..."
	sh_new_ver=$(wget --no-check-certificate -qO- "$shell_url"|grep 'sh_ver="'|awk -F "=" '{print $NF}'|sed 's/\"//g'|head -1)
	[[ -z ${sh_new_ver} ]] && echo -e "${Error} 检测最新版本失败 !" && start_menu
	if [[ ${sh_new_ver} != "${sh_ver}" ]]; then
		echo -e "发现新版本[ ${sh_new_ver} ],是否更新? [Y/n]"
		read -p "(默认: y): " yn
		[[ -z "${yn}" ]] && yn="y"
		if [[ ${yn} == [Yy] ]]; then
			wget -O snell+stls_new.sh --no-check-certificate "$shell_url" && chmod +x snell+stls_new.sh
			echo -e "脚本已更新为最新版本[ ${sh_new_ver} ] !"
			echo -e "3s后执行新脚本"
               sleep 3s
               exec bash snell+stls_new.sh
		else
		    echo && echo " 已取消..." && echo
              sleep 3s
              start_menu
		fi
	else
	    echo -e "${Green_font_prefix}当前已是最新版本[v${sh_new_ver}] !${Font_color_suffix}"
	    sleep 2s
         start_menu
	fi
}

before_start_menu() {
    echo && echo -n -e "${Yellow_font_prefix}* 按回车返回主菜单 *${Font_color_suffix}" && read temp
    start_menu
}

start_menu(){
     clear
     check_root
     check_sys
     sysArch
     action=$1

# 定义菜单项的数组
menu_items=(
    "更新脚本"
    "安装 Snell Server"
    "卸载 Snell Server"
    "启动 Snell Server"
    "停止 Snell Server"
    "重启 Snell Server"
    "设置 Snell 配置信息"
    "查看 Snell 配置信息"
    "查看 Snell 运行状态"
    "查看 Snell 实时日志"
    "手动编辑 Snell 配置"
    "安装 Shadow-TLS"
    "卸载 Shadow-TLS"
    "启动 Shadow-TLS"
    "停止 Shadow-TLS"
    "重启 Shadow-TLS"
    "查看 Shadow-TLS 运行状态"
    "查看 Shadow-TLS 实时日志"
    "查看 Shadow-TLS 服务文件"
    "设置 Shadow-TLS 配置信息"
    "手动编辑 Shadow-TLS 配置"
    "退出脚本"
)

# 输出菜单
echo
echo -e "====================================================="
echo -e "       Surge Snell Server (Shadow-TLS) 管理脚本 ${Red_font_prefix}[v${sh_ver}]${Font_color_suffix}"
echo -e "====================================================="

# 输出菜单项
for i in "${!menu_items[@]}"; do
    index=$(printf "%2d" "$i")  # 格式化序号为两位数字，右对齐
    item="${menu_items[$i]}"

    # 根据序号判断所属模块，添加分隔符和模块标题
    case "$i" in
        1) echo -e " —————— Snell Server 管理 ——————" ;;
        11) echo -e " —————— Shadow-TLS 管理 ——————" ;;
        21) echo -e " ———————— 其他 ————————" ;;
    esac
    
    echo -e " ${Green_font_prefix}$index.${Font_color_suffix} ${item}"
done

echo -e "====================================================="
echo

	if [[ -e ${FILE} ]]; then
	        check_status > /dev/null 2>&1
                ver=$(grep 'version = ' "${Snell_conf}" |awk -F 'version = ' '{print $NF}')
		if [[ "${ver}" = "4" || "${ver}" = "5" ]]; then
		         getVer > /dev/null 2>&1
                   if [[ "$status" == "running" ]]; then
                       echo -e " 当前Snell状态: ${Green_font_prefix}已安装${Yellow_font_prefix}[v${new_ver}]${Font_color_suffix}并${Green_font_prefix}已启动${Font_color_suffix}"
                   else
                       echo -e " 当前Snell状态: ${Green_font_prefix}已安装${Yellow_font_prefix}[v${new_ver}]${Font_color_suffix}但${Red_font_prefix}未启动${Font_color_suffix}"
                   fi
                else
                   if [[ "$status" == "running" ]]; then
                       echo -e " 当前Snell状态: ${Green_font_prefix}已安装${Yellow_font_prefix}[v${ver}]${Font_color_suffix}并${Green_font_prefix}已启动${Font_color_suffix}"
                   else
                       echo -e " 当前Snell状态: ${Green_font_prefix}已安装${Yellow_font_prefix}[v${ver}]${Font_color_suffix}但${Red_font_prefix}未启动${Font_color_suffix}"
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
	read -e -p " 请输入数字[0-21]（默认值: 1）: " num
	
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
		Manual_Edit_Snell
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
		20)
                Manual_Edit_Shadow_TLS
                ;;
                21)
		exit 1
		;;
		*)
		echo -e "${Error} 请输入正确数字${Yellow_font_prefix}[0-21]${Font_color_suffix}"
		;;
	esac
}
start_menu
