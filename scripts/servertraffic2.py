#!/usr/bin/env python3

import http.server
import socketserver
import json
import time
import psutil
import os  
import platform
import urllib.request
import subprocess
import re
import threading

# ================= 新增：APT 异步缓存机制 =================
# 全局缓存：updates 初始化为 -1 (代表获取中)，last_check 记录上次检查时间戳
PKG_CACHE = {"updates": -1, "last_check": 0}

def fetch_apt_updates():
    """后台线程专用：给足 30 秒时间慢慢执行 APT 检查，绝不卡死主 API"""
    try:
        apt_res = subprocess.run(
            ["apt-get", "-s", "-o", "Debug::NoLocking=true", "upgrade"], 
            capture_output=True, text=True, timeout=30
        )
        match = re.search(r'(\d+)\s+upgraded', apt_res.stdout)
        if match:
            PKG_CACHE["updates"] = int(match.group(1))
        else:
            PKG_CACHE["updates"] = 0
    except Exception:
        # 如果依然失败，至少不让它显示 -1
        if PKG_CACHE["updates"] == -1:
            PKG_CACHE["updates"] = 0
# ========================================================

# ================= 新增：在启动时获取一次公网 IP =================
try:
    PUBLIC_IP = urllib.request.urlopen('https://api.ipify.org', timeout=5).read().decode('utf-8')
except Exception:
    PUBLIC_IP = "Unknown"
# =================================================================

# 监听端口
port = 7133

# ================= 新增安全配置 =================
# 1. 允许访问的 IP 白名单 (支持多个 IP，用逗号分隔)
# 请替换为运行 Surge 的设备或你代理服务器的公网 IP
ALLOWED_IPS = {'127.0.0.1', '172.81.111.116', '104.251.236.208', '23.249.16.200'}

# 2. 访问路径密钥 (必须以 / 开头)
ACCESS_TOKEN = '/vpsinfo2026'
# ================================================

class RequestHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        client_ip = self.client_address[0]
        
        # 验证层 1：IP 白名单拦截
        if client_ip not in ALLOWED_IPS:
            self.send_response(403)
            self.send_header('Content-type', 'text/plain')
            self.end_headers()
            #self.wfile.write(b"403 Forbidden: IP not allowed.")
            #self.wfile.write(f"403 Forbidden: {client_ip} not allowed.".encode('utf-8'))
            self.wfile.write(f"IP Blocked: {client_ip} not allowed.".encode('utf-8'))
            print(f"[*] Blocked IP {client_ip}")
            return

        # 验证层 2：路径密钥拦截
        if self.path != ACCESS_TOKEN:
            self.send_response(403)
            self.send_header('Content-type', 'text/plain')
            self.end_headers()
            #self.wfile.write(b"403 Forbidden: Invalid Token.")
            self.wfile.write(f"Path Blocked: Invalid Access Token for path '{self.path}'.".encode('utf-8'))
            print(f"[*] IP {client_ip} tried invalid path: {self.path}")
            return

        # 验证层 3：自定义密码 Header 验证
        # 要求客户端必须携带一个名为 'X-CatVPS-Auth' 的请求头，且值必须正确
        if self.headers.get('X-CatVPS-Auth') != 'Password':
            self.send_response(403)
            self.send_header('Content-type', 'text/plain')
            self.end_headers()
            #self.wfile.write(b"403 Forbidden: Invalid Header Auth.")
            # 获取访客实际发来的密码（如果没有发，值会是 None）
            provided_auth = self.headers.get('X-CatVPS-Auth')
            # 把访客发来的错误密码用单引号括起来，返回给他
            self.wfile.write(f"Header Blocked: Invalid Header Password '{provided_auth}'.".encode('utf-8'))
            print(f"[*] Blocked invalid header auth ({provided_auth}) from {client_ip}")
            return    

        # 4. 验证层 4：User-Agent 验证
        # 要求客户端必须是 Surge/iOS 才能访问
        if self.headers.get('User-Agent') != 'Surge/iOS':
            self.send_response(403)
            self.send_header('Content-type', 'text/plain')
            self.end_headers()
            #self.wfile.write(b"403 Forbidden: Invalid User-Agent.")
            # 先拿变量 ua_string，再放进去
            ua_string = self.headers.get('User-Agent')
            self.wfile.write(f"UA Blocked: Verification failed for '{ua_string}'.".encode('utf-8'))
            print(f"[*] Blocked invalid User-Agent ({ua_string}) from {client_ip}")
            return

        # --------- 验证通过，收集并返回数据 ---------
        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.end_headers()

        # ================= 新增：内核级 TCP 重传读取函数 =================
        def get_tcp_stats():
            try:
                with open('/proc/net/snmp', 'r') as f:
                    for line in f:
                        # 定位到 Tcp 数值行 (忽略表头)
                        if line.startswith('Tcp:') and 'RtoAlgorithm' not in line:
                            parts = line.split()
                            # 索引 11 为 OutSegs, 12 为 RetransSegs
                            return int(parts[11]), int(parts[12])
            except Exception:
                pass
            return 0, 0
        # ================================================================

        # 1. 记录 1 秒前的网络和磁盘 IO 总数据
        net_before = psutil.net_io_counters()
        disk_before = psutil.disk_io_counters()
        cpu_t_before = psutil.cpu_times()
        tcp_out_before, tcp_retrans_before = get_tcp_stats()

        # ================= 优雅并发：利用测速等待期执行 Ping =================
        ping_targets = ['1.1.1.1', '223.5.5.5']
        ping_procs = {}
        for ip in ping_targets:
            try:
                # 使用 Popen 非阻塞方式在后台发起 Ping，不卡主线程
                ping_procs[ip] = subprocess.Popen(
                    ["ping", "-c", "1", "-W", "1", ip], 
                    stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True
                )
            except Exception:
                ping_procs[ip] = None
                

        # 暂停 1 秒 (既用来防刷限流，也作为测速的时间差)
        # Limit the HTTP server to one request per second
        time.sleep(1)
        

        # 收集并解析 Ping 结果 (零额外耗时)
        ping_results = {}
        for ip, proc in ping_procs.items():
            latency = "超时"
            if proc is not None:
                try:
                    # 读取结果，设置极短超时以防僵死
                    out, _ = proc.communicate(timeout=0.5)
                    if proc.returncode == 0:
                        match = re.search(r'time=([\d.]+)\s*ms', out)
                        if match:
                            latency = f"{float(match.group(1))}ms"
                except subprocess.TimeoutExpired:
                    proc.kill() # 如果卡住则强制猎杀子进程
                except Exception:
                    pass
            ping_results[ip] = latency
        # =====================================================================

        # 2. 记录 1 秒后的各项系统数据
        net_after = psutil.net_io_counters()
        disk_after = psutil.disk_io_counters()
        cpu_t_after = psutil.cpu_times()
        tcp_out_after, tcp_retrans_after = get_tcp_stats()
        
        # Obtain CPU/MEM usage and network traffic info
        cpu_usage = psutil.cpu_percent()
        mem_usage = psutil.virtual_memory().percent
        # 计算当前总流量与实时流速 (每秒字节数)
        bytes_sent = net_after.bytes_sent
        bytes_recv = net_after.bytes_recv
        bytes_total = bytes_sent + bytes_recv
        speed_sent = bytes_sent - net_before.bytes_sent
        speed_recv = bytes_recv - net_before.bytes_recv

        # 计算磁盘读写流速 (防报错兼容)
        disk_read_speed = (disk_after.read_bytes - disk_before.read_bytes) if disk_after and disk_before else 0
        disk_write_speed = (disk_after.write_bytes - disk_before.write_bytes) if disk_after and disk_before else 0

        # 获取 CPU 进阶信息
        cpu_usage = psutil.cpu_percent()
        cpu_per_core = psutil.cpu_percent(percpu=True)
        cpu_freq_info = psutil.cpu_freq()
        cpu_freq = int(cpu_freq_info.current) if cpu_freq_info else 0 # 某些虚拟机获取不到频率时设为0
        cpu_cores = psutil.cpu_count(logical=True)

        # 获取内存与 Swap 具体数据
        mem = psutil.virtual_memory()
        swap = psutil.swap_memory()
        # 磁盘数据 (获取根目录 / 的使用情况)
        disk_info = psutil.disk_usage('/')

        # 获取磁盘 Inode 使用率
        try:
            st = os.statvfs('/')
            inode_total = st.f_files
            inode_used = inode_total - st.f_ffree
            inode_percent = (inode_used / inode_total) * 100 if inode_total > 0 else 0.0
        except Exception:
            inode_percent = 0.0

        # 进程数与网络连接数 (捕获权限不足时的异常)
        process_count = len(psutil.pids())

        # ================= 全局文件描述符 (FD) 使用率 =================
        try:
            # 读取 Linux 内核态实时的 FD 分配情况
            with open('/proc/sys/fs/file-nr', 'r') as f:
                fd_data = f.read().split()
                fd_allocated = int(fd_data[0])
                fd_unused = int(fd_data[1])
                fd_max = int(fd_data[2])
                
                # 实际使用 = 已分配 - 分配但未使用
                fd_used = fd_allocated - fd_unused
                fd_percent = (fd_used / fd_max * 100) if fd_max > 0 else 0.0
        except Exception:
            fd_percent = 0.0
        # ====================================================================
        
        try:
            net_connections = len(psutil.net_connections(kind='inet'))
            tcp_connections = len(psutil.net_connections(kind='tcp')) # TCP连接
            udp_connections = len(psutil.net_connections(kind='udp')) # UDP连接
        except Exception:
            net_connections = 0
            tcp_connections = 0
            udp_connections = 0
        
        # Get UTC timestamp and uptime
        utc_timestamp = int(time.time())
        uptime = int(time.time() - psutil.boot_time())
        # Get the last statistics time (保留供参考，Surge 建议使用 utc_timestamp)
        #last_time = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime())
        os_name = platform.system()       # 例如 'Linux', 'Windows'
        os_version = platform.release()   # 例如 '5.15.0-60-generic'

        # 系统负载 Load Average (1, 5, 15 分钟)
        try:
            load1, load5, load15 = os.getloadavg()
            # 保留两位小数
            load1, load5, load15 = round(load1, 2), round(load5, 2), round(load15, 2)
        except AttributeError:
            # 兼容非 Unix 系统
            load1, load5, load15 = 0.0, 0.0, 0.0

            # 仅限 Linux/Unix 系统
        try:
            st = os.statvfs('/')
            inodes_total = st.f_files
            inodes_free = st.f_ffree
            inodes_used = inodes_total - inodes_free
            inode_percent = round((inodes_used / inodes_total) * 100, 2) if inodes_total > 0 else 0
        except Exception:
            inode_percent = 0

        # ================= 新增：应用状态与网络延迟 =================
        # 1. 获取 Docker 运行中容器数量
        # 改进：避免 shell=True，限制执行时间，在 Python 内统计行数
        try:
            result = subprocess.run(["docker", "ps", "-q"], capture_output=True, text=True, timeout=2, check=True)
            # 通过换行符分割并过滤掉空行，得出容器数量
            docker_count = len([line for line in result.stdout.splitlines() if line.strip()])
        except (subprocess.SubprocessError, FileNotFoundError, TimeoutError):
            docker_count = 0

        # 2. 获取 Fail2ban 封禁 IP 数量 
        # 改进：直接读取状态，用 Python 逐行解析提取数据，而非依赖 grep
        try:
            result = subprocess.run(["fail2ban-client", "status", "sshd"], capture_output=True, text=True, timeout=2, check=True)
            fail2ban_count = 0
            for line in result.stdout.splitlines():
                if "Currently banned:" in line:
                    parts = line.split(":")
                    if len(parts) > 1:
                        fail2ban_count = int(parts[1].strip())
                    break
        except (subprocess.SubprocessError, FileNotFoundError, TimeoutError, ValueError):
            fail2ban_count = 0

        # ================= 优雅遍历：单次扫描所有核心进程 =================
        target_processes = {'realm', 'snell'}  # 在此添加任意多个需要监控的程序名
        process_status = {name: False for name in target_processes}
        
        try:
            # 仅遍历一次系统进程树 (O(N) 复杂度)
            for p in psutil.process_iter(['name']):
                try:
                    p_name = p.info['name']
                    if p_name:
                        p_name_lower = p_name.lower()
                        # 检查当前进程是否属于我们的目标
                        for target in target_processes:
                            if target in p_name_lower:
                                process_status[target] = True
                except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess):
                    continue
        except Exception:
            pass
        # ====================================================================

        # ================= 高阶指标计算 (I/O Wait, TCP 重传) =================
        # 计算 TCP 重传率
        delta_out = tcp_out_after - tcp_out_before
        delta_retrans = tcp_retrans_after - tcp_retrans_before
        tcp_retrans_total_pct = (tcp_retrans_after / tcp_out_after * 100) if tcp_out_after > 0 else 0.0
        tcp_retrans_realtime_pct = (delta_retrans / delta_out * 100) if delta_out > 0 else 0.0

        # 计算 CPU iowait 占比 (兼容 macOS/Windows 无该属性的情况)
        try:
            io_delta = cpu_t_after.iowait - cpu_t_before.iowait
            total_delta = sum(cpu_t_after) - sum(cpu_t_before)
            cpu_iowait = (io_delta / total_delta * 100) if total_delta > 0 else 0.0
        except AttributeError:
            cpu_iowait = 0.0
        # =========================================================================

        # ================= 包更新、重启提醒、vnStat 月流量 =================
        global PKG_CACHE
        # 设置缓存有效期为 3600 秒 (1小时)，避免频繁唤醒 APT 消耗性能
        if time.time() - PKG_CACHE["last_check"] > 3600:
            PKG_CACHE["last_check"] = time.time()
            # 开启后台守护线程执行耗时任务，主程序立刻继续往下走 (Non-blocking)
            threading.Thread(target=fetch_apt_updates, daemon=True).start()
            
        pkg_updates = PKG_CACHE["updates"]
        reboot_required = os.path.exists('/var/run/reboot-required')

        vnstat_month_total = -1
        try:
            # 提取 vnStat 记录的当月总流量
            v_res = subprocess.run(["vnstat", "--json"], capture_output=True, text=True, timeout=1.0)
            if v_res.returncode == 0:
                v_data = json.loads(v_res.stdout)
                # 获取第一块网卡的当月 (最后一条) 数据
                month_data = v_data['interfaces'][0]['traffic']['month'][-1]
                vnstat_month_total = month_data['rx'] + month_data['tx']
        except Exception:
            pass
        # =======================================================================




        # Construct JSON dictionary
        response_dict = {
            "utc_timestamp": utc_timestamp,
            "uptime": uptime,
            "os_info": f"{os_name} {os_version}",                  # 系统信息
            "public_ip": PUBLIC_IP,                                # IP信息
            "cpu_usage": cpu_usage,
            "cpu_cores": cpu_cores,                                # CPU核心数
            "cpu_per_core": cpu_per_core,                          # 各核心使用率(列表)
            "cpu_freq": cpu_freq,                                  # CPU频率
            "mem_usage": mem_usage,
            "mem_used": mem.used,                                  # 已用内存
            "mem_total": mem.total,                                # 总内存
            "swap_percent": swap.percent,
            "swap_used": swap.used,                                # 已用Swap
            "swap_total": swap.total,                              # 总Swap
            "bytes_sent": str(bytes_sent),
            "bytes_recv": str(bytes_recv),
            "bytes_total": str(bytes_total),
            "speed_sent": speed_sent,                              # 上传流速
            "speed_recv": speed_recv,                              # 下载流速
            "disk_percent": disk_info.percent,
            "disk_used": disk_info.used,                           # 磁盘已用
            "disk_total": disk_info.total,                         # 磁盘总容量
            "disk_inode_percent": inode_percent,                   # Inode 使用率
            "disk_read_speed": disk_read_speed,                    # 磁盘读速率
            "disk_write_speed": disk_write_speed,                  # 磁盘写速率
            "process_count": process_count,                        # 进程总数
            "fd_percent": fd_percent,                              # FD 使用率
            "net_connections": net_connections,                    # 网络连接数
            "tcp_connections": tcp_connections,                    # TCP 连接
            "udp_connections": udp_connections,                    # UDP 连接
            "load1": load1,
            "load5": load5,
            "load15": load15,
            "docker_count": docker_count,        
            "fail2ban_count": fail2ban_count,     
            "process_status": process_status,                      # <--- 例如: {"realm": True, "snell": False}
            "ping_results": ping_results,                          # <--- 例如: {"1.1.1.1": "12.3ms", "223.5.5.5": "超时"}
            "cpu_iowait": cpu_iowait,                              # IO阻塞等待时间
            "tcp_retrans_total_pct": tcp_retrans_total_pct,        # 累计重传率
            "tcp_retrans_realtime_pct": tcp_retrans_realtime_pct,  # 实时重传率
            "pkg_updates": pkg_updates,                            # 软件包
            "reboot_required": reboot_required,                    # 重启提示
            "vnstat_month_total": vnstat_month_total,              # 当月流量
        }

        # Convert JSON dictionary to JSON string
        response_json = json.dumps(response_dict).encode('utf-8')
        self.wfile.write(response_json)

# 允许端口复用，防止重启服务时报 Address already in use
socketserver.ThreadingTCPServer.allow_reuse_address = True
with socketserver.ThreadingTCPServer(("", port), RequestHandler) as httpd:
    try:
        print(f"Serving at port {port}")
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("KeyboardInterrupt is captured, program exited")
