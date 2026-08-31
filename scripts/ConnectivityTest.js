const sites = {
  Baidu: 'https://www.baidu.com',
  Bilibili: 'https://www.bilibili.com',
  Github: 'https://www.github.com',
  Google: 'https://www.google.com/generate_204',
  Youtube: 'https://www.youtube.com/generate_204',
  Microsoft: 'https://www.microsoft.com',
  ChatGPT: 'https://chatgpt.com',
  Twitter: 'https://x.com',
  V2ex: 'https://www.v2ex.com',
  Apple: 'https://www.apple.com'
};

!(async () => {
  // 动态遍历字典，自动生成测试任务，后续增加网址更方便
  const promises = Object.entries(sites).map(([name, url]) => ping(name, url));
  const results = await Promise.all(promises);

  $done({
    title: 'Network Connectivity',
    content: results.join('\n'),
    icon: 'network',            // 换成了更符合网络测试的图标
    'icon-color': '#0B84FF',
  });
})();

// 🪄 黑科技：计算文字的“视觉宽度”并智能补齐空格
function formatName(name, targetWidth) {
  let visualLength = 0;
  for (let char of name) {
    if (/[ilI1jtr]/.test(char)) {
      visualLength += 0.5; // 遇到窄字母，宽度只算一半
    } else if (/[mWmwM]/.test(char)) {
      visualLength += 1.5; // 遇到宽字母，宽度算一点五倍
    } else {
      visualLength += 1;   // 普通字母算正常宽度
    }
  }
  // 计算需要补充多少个空格，向上取整
  const spacesToAdd = Math.ceil(targetWidth - visualLength);
  return name + ' '.repeat(Math.max(0, spacesToAdd));
}

function ping(name, url) {
  return new Promise((resolve) => {
    const start = Date.now();
    
    // 优化1：使用 GET 请求
    // 优化2：增加 timeout 参数（3秒超时），防止面板无限卡加载
    $httpClient.get({ url: url, timeout: 3 }, (err, resp, data) => {
      const time = Date.now() - start;

      // 这里的目标视觉宽度设为 10
      const displayName = formatName(name, 10);
      
      // 优化3：增加错误处理机制
      if (err || !resp || resp.status !== 204 && resp.status !== 200) {
        resolve(`${displayName}\t: 🔴 Error/Timeout`);
      } else {
        // 优化4：根据延迟动态分配红黄绿状态指示灯
        let status = '🟢';
        if (time > 800) status = '🔴'; 
        else if (time > 300) status = '🟡';
        
        resolve(`${displayName}\t: ${status} ${time} ms`);
      }
    });
  });
}
