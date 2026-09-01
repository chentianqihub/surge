(async () => {
  let params = getParams($argument);
  let stats = await httpAPI(params.url);

  // ================= 错误状态码拦截 =================
  // 如果 Python 服务器返回的不是 200 OK，说明被安全机制拦截了
  if (stats.status !== 200) {
      // 抛出 Python 返回的具体错误文本 (stats.body)，交给下面的 catch 处理
      throw new Error(stats.body || `HTTP 状态码异常: ${stats.status}`);
  }
  // ========================================================
  const jsonData = JSON.parse(stats.body);

  // === 数据统一解析与格式化 ===
  // 系统与进程
  const sysOS = jsonData.os_info;
  const procCount = jsonData.process_count;
  const netConns = jsonData.net_connections;
  const tcpConns = jsonData.tcp_connections || 0; 
  const udpConns = jsonData.udp_connections || 0;

  // ================= 新增：IP 处理逻辑 =================
  // 判断 argument 中是否带有 full_ip=true (注意 Surge 参数全为字符串)
  const showFullIp = params.full_ip === 'true';
  let serverIp = jsonData.public_ip || "Unknown";  
  // 如果为 false 且获取到了正常 IP，则进行打码 (兼容 IPv4 和 IPv6)
  if (!showFullIp && serverIp !== "Unknown") {
      if (serverIp.includes('.')) {
          let p = serverIp.split('.');
          if (p.length === 4) serverIp = `${p[0]}.${p[1]}.**.**`;
      } else if (serverIp.includes(':')) {
          let p = serverIp.split(':');
          if (p.length >= 3) serverIp = `${p[0]}:${p[1]}:**:**`;
      }
  }
  // =====================================================

  // CPU 详情
  const cpuCores = jsonData.cpu_cores;
  const cpuFreq = jsonData.cpu_freq;
  const cpuUsage = `${jsonData.cpu_usage.toFixed(1)}%`;
  // 处理 CPU 多核数据 (大于 8 核时隐藏分核详情防面板错位)
  const perCoreStr = jsonData.cpu_per_core.length <= 8 
    ? `[${jsonData.cpu_per_core.map(c => Math.round(c)).join(',')}]` 
    : '';

  // 内存与 Swap
  const memUsage = `${jsonData.mem_usage.toFixed(1)}%`;
  const memUsed = bytesToSize(jsonData.mem_used);
  const memTotal = bytesToSize(jsonData.mem_total);
  
  const swapUsage = `${jsonData.swap_percent.toFixed(1)}%`;
  const swapUsed = bytesToSize(jsonData.swap_used);
  const swapTotal = bytesToSize(jsonData.swap_total);

  // 磁盘 IO
  const diskUsage = `${jsonData.disk_percent.toFixed(1)}%`;
  const diskUsed = bytesToSize(jsonData.disk_used);     
  const diskTotal = bytesToSize(jsonData.disk_total);
  const inodeUsage = `${(jsonData.disk_inode_percent || 0).toFixed(1)}%`;
  const diskRead = `${bytesToSize(jsonData.disk_read_speed)}/s`;
  const diskWrite = `${bytesToSize(jsonData.disk_write_speed)}/s`;

  // 系统负载
  const load1 = jsonData.load1;
  const load5 = jsonData.load5;
  const load15 = jsonData.load15;

  // 网络总计与实时流速
  const netRecv = bytesToSize(jsonData.bytes_recv);
  const netSent = bytesToSize(jsonData.bytes_sent);
  const netTotal = bytesToSize(jsonData.bytes_total);
  const speedRecv = `${bytesToSize(jsonData.speed_recv)}/s`;
  const speedSent = `${bytesToSize(jsonData.speed_sent)}/s`;

  // 运行时间
  const uptimeStr = formatUptime(jsonData.uptime);  
  
  // 时间处理 (使用绝对时间，解决时区错乱)
  const updateTime = new Date(jsonData.utc_timestamp * 1000);
  // 只取时间部分 (如 16:30:00) 节约面板空间，如果你想保留日期，可改回 toLocaleString()
  const timeString = updateTime.toLocaleString('zh-CN', { hour12: false }); 

  // ================= 应用状态与延迟 =================
  const dockerCnt = jsonData.docker_count || 0;
  const f2bCnt = jsonData.fail2ban_count || 0;
  // 安全提取进程状态 (如果 JSON 没有该字段则默认 false)
  const procs = jsonData.process_status || {};
  const realmStatus = procs['realm'] ? '🟢' : '🔴';
  const snellStatus = procs['snell'] ? '🟢' : '🔴';
  // 安全提取 Ping 延迟
  const pings = jsonData.ping_results || {};
  const pingCF = pings['1.1.1.1'] || "超时";
  const pingAli = pings['223.5.5.5'] || "超时";
  // ========================================================

  // ================= 进阶运维指标 =================
  const iowait = `${(jsonData.cpu_iowait || 0).toFixed(1)}%`;
  const retransTotal = `${(jsonData.tcp_retrans_total_pct || 0).toFixed(2)}%`;
  const retransReal = `${(jsonData.tcp_retrans_realtime_pct || 0).toFixed(2)}%`;
  // 兼容异步架构：如果 Python 返回 -1，说明后台线程还在算，面板优雅提示 "计算中"
  const pkgUpdates = jsonData.pkg_updates === -1 ? '计算中' : jsonData.pkg_updates;
  const rebootReq = jsonData.reboot_required ? '⚠️需重启' : '✅正常';
  
  let vnstatMonth = "未配置";
  if (jsonData.vnstat_month_total >= 0) {
      vnstatMonth = bytesToSize(jsonData.vnstat_month_total);
  }
  // =====================================================


  // === 面板状态颜色配置 ===
  let panel = {};
  let shifts = {
    '1': '#06D6A0', // 绿 (健康)
    '2': '#FFD166', // 黄 (警告)
    '3': '#EF476F'  // 红 (危险)
  };
  
  // 依旧根据内存使用率来决定图标颜色
  const col = Diydecide(0, 50, 85, parseInt(jsonData.mem_usage));
  
  panel.title = params.name || 'Server Info';
  panel.icon = params.icon || 'server.rack';
  panel["icon-color"] = shifts[col];
  
  // ====== 重新排版面板内容 ======
  // ====== Panel Emoji 增强版 ======
  panel.content = [
    // 【系统与状态】
    `🖥️ 概览: ${sysOS} (${serverIp})`,
    `📦 系统: 待更新 ${pkgUpdates} 个 | ${rebootReq} | 进程 ${procCount}`,
    // 【计算与负载】
    `⚡ CPU (${cpuCores}C / ${cpuFreq}MHz) : ${cpuUsage} ${perCoreStr}`,
    `📈 L/A: 1m ${load1} ∷ 5m ${load5} ∷ 15m ${load15} (IOw: ${iowait})`,
    // 【内存与存储】
    `🧠 RAM: ${memUsed} / ${memTotal} (${memUsage})`,
    `🔄 Swp: ${swapUsed} / ${swapTotal} (${swapUsage})`,
    `💾 DSK: ${diskUsed} / ${diskTotal} (${diskUsage} | 🗂️ Inode: ${inodeUsage})`,        
    `💿 I/O: R ${diskRead}  |  W ${diskWrite}`,   
    // 【网络与流量】
    `📊 流量: 本月 ${vnstatMonth} | 总计 ⇣ ${netRecv} | ⇡ ${netSent} | ∑ ${netTotal}`,
    `🚀 速率: ⇣ ${speedRecv}  |  ⇡ ${speedSent}`,
    `🕸️ 连接: ${netConns} (T/U: ${tcpConns}/${udpConns}) | 重传: 实时 ${retransReal} / 累计 ${retransTotal}`,
    `🏓 延迟: CF ${pingCF} | Ali ${pingAli}`,
    // 【应用与安全】
    `🛡️ 进程: Dkr ${dockerCnt} | ⛔ 拦截 ${f2bCnt} | Rlm ${realmStatus} Snl ${snellStatus}`,
    // 【时间底栏】
    `⏳ 状态: 已运行 ${uptimeStr}`,
    `⏰ 更新: ${timeString}`
].join('\n');

$done(panel);
  
})().catch((e) => {
  console.log('CatVPS Error: ' + e.message);
  
  // 提取具体的错误信息（去掉默认的 "Error: " 前缀）
  let errorMsg = e.message ? e.message.replace('Error: ', '') : e;

  $done({
    title: '连接拒绝 / 验证失败',
    // 将 Python 返回的具体错误原因展示在面板上
    content: `🚨 拦截原因：${errorMsg}\n⚠️ 请检查 Surge 模块配置或 VPS 状态`,
    icon: 'exclamationmark.shield.fill',
    'icon-color': '#EF476F' // 红色警告图标
  });
});

// --- 下方基础函数保持不变 ---
function httpAPI(path = '') {
  let headers = {
    'User-Agent': 'Surge/iOS',
    'X-CatVPS-Auth': 'Password'
  };
  return new Promise((resolve, reject) => {
    $httpClient.get({
      url: path,
      headers: headers,
    }, (err, resp, body) => {
      if (err) {
        reject(err);
      } else {
        resp.body = body;
        resp.statusCode = resp.status ? resp.status : resp.statusCode;
        resp.status = resp.statusCode;
        resolve(resp);
      }
    });
  });
}

function getParams(param) {
  return Object.fromEntries(
    $argument
      .split('&')
      .map((item) => item.split('='))
      .map(([k, v]) => [k, decodeURIComponent(v)])
  );
}

function formatUptime(seconds) {
  const d = Math.floor(seconds / 86400);
  const h = Math.floor(seconds / 3600) % 24;
  const m = Math.floor(seconds / 60) % 60;
  const s = Math.floor(seconds % 60); // 获取不足一分钟的剩余秒数

  let res = '';
  // 巧妙利用 res 字符串的隐式类型转换：只要前面加过内容，res 就不是空字符串（true）
  if (d) res += `${d}d `;
  if (res || h) res += `${h}h `;
  if (res || m) res += `${m}m `;
  if (!res || s) res += `${s}s`; // 如果前面全为空，或者秒数大于0，则显示秒

  return res.trim(); // 去掉末尾可能多余的空格
}

function bytesToSize(bytes) {
  if (bytes === 0) return '0 B';
  let k = 1024;
  let sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
  let i = Math.floor(Math.log(bytes) / Math.log(k));
  return `${(bytes / Math.pow(k, i)).toFixed(2)} ${sizes[i]}`;
}

function Diydecide(x, y, z, item) {
  let array = [x, y, z];
  array.push(item);
  return array.sort((a, b) => a - b).findIndex(i => i === item);
}
