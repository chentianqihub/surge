 /*
 * Surge Monitor
 *
 * Official metrics:
 *   surge_build_info{version,build,system}
 *   surge_uptime_seconds
 *   surge_memory_bytes
 *   surge_interface_in_bytes_total{interface}
 *   surge_interface_out_bytes_total{interface}
 *
 * API: GET /v1/metrics
 */

const API_KEY = "123";
const METRICS_URL = "http://127.0.0.1:6171/v1/metrics";

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

        const content = [
            "内存占用：  " + formatBytes(memory ? memory.value : NaN),
            "",
            "运行时间：  " + formatUptime(uptime ? uptime.value : NaN),
            "",
            "↓ " + formatBytes(download) + "     ↑ " + formatBytes(upload),
            "",
            "Surge " + version + " · Build " + build + " · " + system
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
