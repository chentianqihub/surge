 /*
 * Surge Monitor
 *
 * Official metrics:
 *   surge_build_info{version,build,system}
 *   surge_uptime_seconds
 *   surge_memory_bytes
 *   surge_active_requests
 *   surge_dns_cache_entries	
 *   surge_active_bans
 *   surge_interface_in_bytes_total{interface}
 *   surge_interface_out_bytes_total{interface}
 *
 * API: GET /v1/metrics
 */

// ========================================

// 1. 优雅、安全地解析 $argument 字符串
const args = (() => {
    if (typeof $argument !== "string" || !$argument.trim()) {
        return {};
    }
    
    return $argument.split(/[,&]/).reduce((acc, curr) => {
        const [k, ...v] = curr.split("=");
        if (k) {
            acc[k.trim()] = v.join("=").trim();
        }
        return acc;
    }, {});
})();

// 2. 严格从传入参数读取，不再使用默认回退
const API_KEY = args.key;
const METRICS_PORT = args.port;

// 3. 安全前置校验 (Fail-Fast)
// 既然取消了回退，当缺失必填参数时，主动在面板展示报错并阻断运行
if (!API_KEY || !METRICS_PORT) {
    $done({
        title: "Surge Monitor",
        content: "配置参数缺失\n请检查 argument=key=xxx&port=xxx",
        style: "error",
        icon: "xmark.octagon.fill",
        "icon-color": "#FF3B30"
    });
    // 抛出异常以终止后续所有请求，避免发起无效的 HTTP 请求
    throw new Error("Surge Monitor 运行中止：缺失必须的 key 或 port 参数");
}

const METRICS_URL = `http://127.0.0.1:${METRICS_PORT}/v1/metrics`;

// ========================================

// 新增：安全的当前时间格式化函数（保证输出 HH:mm:ss 格式，补齐首位 0）
function formatCurrentTime() {
    const now = new Date();
    const pad = (n) => n.toString().padStart(2, "0");
    return `${pad(now.getHours())}:${pad(now.getMinutes())}:${pad(now.getSeconds())}`;
}

function isFiniteNumber(value) {
    return isFinite(Number(value));
}

function formatBytes(value) {
    if (!isFiniteNumber(value)) {
        return "—";
    }

    let bytes = Math.max(0, Number(value));
    const units = ["B", "KB", "MB", "GB", "TB"];
    let unitIndex = 0;

    while (bytes >= 1024 && unitIndex < units.length - 1) {
        bytes /= 1024;
        unitIndex++;
    }

    return bytes.toFixed(2) + " " + units[unitIndex];
}

function formatUptime(value) {
    if (!isFiniteNumber(value)) {
        return "—";
    }

    let seconds = Math.max(0, Math.floor(Number(value)));
    const days = Math.floor(seconds / 86400);
    seconds -= days * 86400;

    const hours = Math.floor(seconds / 3600);
    seconds -= hours * 3600;

    const minutes = Math.floor(seconds / 60);
    seconds -= minutes * 60;

    const parts = [];
    if (days > 0) {
        parts.push(days + "天");
    }
    if (hours > 0 || days > 0) {
        parts.push(hours + "小时");
    }
    if (minutes > 0 || hours > 0 || days > 0) {
        parts.push(minutes + "分钟");
    }
    if (parts.length === 0) {
        parts.push(seconds + "秒");
    }

    return parts.join(" ");
}

function parseMetrics(text) {
    const metrics = [];
    const lines = String(text).split(/\r?\n/);
    const metricPattern =
        /^([a-zA-Z_:][a-zA-Z0-9_:]*)(?:\{([^}]*)\})?\s+([-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?)$/;
    const labelPattern =
        /([a-zA-Z_][a-zA-Z0-9_]*)="((?:\\.|[^"])*)"/g;

    for (let i = 0; i < lines.length; i++) {
        const line = lines[i].trim();
        if (!line || line.charAt(0) === "#") {
            continue;
        }

        const match = line.match(metricPattern);
        if (!match) {
            continue;
        }

        const labels = {};
        const labelText = match[2] || "";
        let labelMatch;

        labelPattern.lastIndex = 0;
        while ((labelMatch = labelPattern.exec(labelText)) !== null) {
            labels[labelMatch[1]] = labelMatch[2]
                .replace(/\\"/g, '"')
                .replace(/\\\\/g, "\\");
        }

        metrics.push({
            name: match[1],
            labels: labels,
            value: Number(match[3])
        });
    }

    return metrics;
}

function getMetric(metrics, metricName) {
    for (let i = 0; i < metrics.length; i++) {
        if (metrics[i].name === metricName) {
            return metrics[i];
        }
    }
    return null;
}

function sumMetrics(metrics, metricName) {
    let total = 0;
    let found = false;

    for (let i = 0; i < metrics.length; i++) {
        if (
            metrics[i].name === metricName &&
            isFiniteNumber(metrics[i].value)
        ) {
            total += Number(metrics[i].value);
            found = true;
        }
    }

    return found ? total : NaN;
}

function finishPanel(title, content, style, icon, iconColor) {
    const result = {
        title: title,
        content: content
    };

    if (style) {
        result.style = style;
    }
    if (icon) {
        result.icon = icon;
    }
    if (iconColor) {
        result["icon-color"] = iconColor;
    }

    $done(result);
}

$httpClient.get(
    {
        url: METRICS_URL,
        headers: {
            Accept: "text/plain",
            "X-Key": API_KEY
        }
    },
    function (error, response, body) {
        if (error) {
            finishPanel(
                "Surge Monitor",
                "无法获取 Metrics\n\n" + String(error),
                "error",
                "exclamationmark.triangle.fill",
                "#FF3B30"
            );
            return;
        }

        if (
            response &&
            response.status &&
            (response.status < 200 || response.status >= 300)
        ) {
            finishPanel(
                "Surge Monitor",
                "Metrics 请求失败\n\nHTTP " + response.status,
                "error",
                "exclamationmark.triangle.fill",
                "#FF3B30"
            );
            return;
        }

        if (!body) {
            finishPanel(
                "Surge Monitor",
                "Metrics 返回为空",
                "error",
                "exclamationmark.triangle.fill",
                "#FF3B30"
            );
            return;
        }

        const metrics = parseMetrics(body);
        const buildInfo = getMetric(metrics, "surge_build_info");
        const uptime = getMetric(metrics, "surge_uptime_seconds");
        const memory = getMetric(metrics, "surge_memory_bytes");

        const version = buildInfo && buildInfo.labels.version
            ? buildInfo.labels.version
            : "未知";
        const build = buildInfo && buildInfo.labels.build
            ? buildInfo.labels.build
            : "未知";
        const system = buildInfo && buildInfo.labels.system
            ? buildInfo.labels.system
            : "未知";

        const download = sumMetrics(
            metrics,
            "surge_interface_in_bytes_total"
        );
        const upload = sumMetrics(
            metrics,
            "surge_interface_out_bytes_total"
        );
     
        // 1. 新增：安全提取指标数值的辅助工具（利用闭包访问 metrics，避免冗余代码）
        const getSafeValue = (metricName) => {
        const m = getMetric(metrics, metricName);
        return m && isFiniteNumber(m.value) ? m.value : "—";
        };

        // 2. 提取新增的三个状态指标
        const activeRequests = getSafeValue("surge_active_requests");
        const dnsCache = getSafeValue("surge_dns_cache_entries");
        const activeBans = getSafeValue("surge_active_bans");
     
        const content = [
            // --- 第一组：基础运行状态 ---
            "内存占用：  " + formatBytes(memory ? memory.value : NaN),
            "运行时间：  " + formatUptime(uptime ? uptime.value : NaN),
            // --- 第二组：全局流量统计 ---
            "↓ 下载流量： " + formatBytes(download),
            "↑ 上传流量： " + formatBytes(upload),
            // --- 第三组：连接与安全状态 ---
            "活跃请求：  " + activeRequests,
            "DNS 缓存：  " + dnsCache,
            "拦截封禁：  " + activeBans,
            // --- 第四组：系统与面板信息 ---
            "Surge " + version + " · Build " + build + " · " + system,
            "最后更新：  " + formatCurrentTime()
        ].join("\n");

        finishPanel(
            "Surge Monitor",
            content,
            null,
            "chart.bar.xaxis",
            "#4A90E2"
        );
    }
);
