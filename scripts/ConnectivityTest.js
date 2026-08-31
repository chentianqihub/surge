const sites = {
  Baidu: 'https://www.baidu.com',
  Bilibili: 'https://www.bilibili.com',
  Github: 'https://www.github.com',
  Google: 'https://www.google.com/generate_204',
  Youtube: 'https://www.youtube.com/generate_204', // 替换为更轻量的无内容返回地址
  // 👇 在这里按照格式添加你想要的网站，注意每行结尾要有英文逗号 ,
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

function ping(name, url) {
  return new Promise((resolve) => {
    const start = Date.now();
    
    // 优化1：使用 GET 请求
    // 优化2：增加 timeout 参数（3秒超时），防止面板无限卡加载
    $httpClient.get({ url: url, timeout: 3 }, (err, resp, data) => {
      const time = Date.now() - start;
      const displayName = name.padEnd(10, ' '); // 名字补全空格，让后面的延迟数值尽量对齐
      
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
