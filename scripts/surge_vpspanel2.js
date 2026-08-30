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
  
  // 时间处理 (使用绝对时间，解决时区错乱)
  const updateTime = new Date(jsonData.utc_timestamp * 1000);
  // 只取时间部分 (如 16:30:00) 节约面板空间，如果你想保留日期，可改回 toLocaleString()
  const timeString = updateTime.toLocaleString('zh-CN', { hour12: false }); 

  // 数据解析
  const cpuUsage = `${jsonData.cpu_usage.toFixed(1)}%`;
  const memUsage = `${jsonData.mem_usage.toFixed(1)}%`;
  // 新增：磁盘解析
  const diskUsage = `${jsonData.disk_percent.toFixed(1)}%`;
  
  // 新增：负载解析
  const load1 = jsonData.load1;
  const load5 = jsonData.load5;
  const load15 = jsonData.load15;

  const inTraffic = jsonData.bytes_recv; // 下载 (VPS接收)
  const outTraffic = jsonData.bytes_sent; // 上传 (VPS发送)
  const totalTraffic = jsonData.bytes_total;

  // === 新增：解析实时流速 ===
  const speedRecv = jsonData.speed_recv || 0;
  const speedSent = jsonData.speed_sent || 0;

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
  // Line 1: 核心资源占用 (CPU | 内存 | 磁盘)
  // Line 2: 负载均值 (1分钟, 5分钟, 15分钟)
  // Line 3: 网络流量 (⇣ 下载 | ⇡ 上传 | ∑ 总计)
  // Line 4: 运行时间 和 最后更新时间
  // ====== Panel Emoji 增强版 ======
  panel.content = [
    `🖥️ 资源: ${cpuUsage} (C) | ${memUsage} (M) | ${diskUsage} (D)`,
    `⚙️ 负载: ${load1} ∷ ${load5} ∷ ${load15}`,
    `🌐 流量: ⇣ ${bytesToSize(inTraffic)} | ⇡ ${bytesToSize(outTraffic)} | ∑ ${bytesToSize(totalTraffic)}`,
    `🚀 速率: ⇣ ${bytesToSize(speedRecv)}/s   |   ⇡ ${bytesToSize(speedSent)}/s`,
    `⏱️ 状态: 已运行 ${formatUptime(jsonData.uptime)}`,
    `🔄 更新: ${timeString}`
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
