'use strict';
const byId = id => document.getElementById(id);
const levelNames = ['紧急', '警报', '严重', '错误', '警告', '通知', '信息', '调试'];
let rawLines = [];
let loadedAt = '';
let busy = false;

function parseLine(line) {
  const match = line.match(/^<(\d+)>/);
  // 原始值包含 facility；最低三位才是严重程度，保留原文便于追溯。
  const severity = match && Number(match[1]) <= 191 ? Number(match[1]) % 8 : null;
  return { raw:line, severity, level:severity === null ? 'unknown' : severity <= 3 ? 'error' : severity === 4 ? 'warning' : 'info' };
}
function render() {
  const keyword = byId('keyword').value.trim().toLowerCase();
  const selected = byId('level').value;
  const visible = rawLines.filter(item => (!keyword || item.raw.toLowerCase().includes(keyword)) && (selected === 'all' || item.level === selected));
  const output = byId('kernel-output');
  output.textContent = '';
  if (!visible.length) {
    const empty = document.createElement('p');
    empty.className = 'empty';
    empty.textContent = rawLines.length ? '没有符合筛选条件的日志。' : '暂无日志。';
    output.appendChild(empty);
  } else {
    const fragment = document.createDocumentFragment();
    visible.forEach(item => {
      const row = document.createElement('div');
      row.className = `log-line level-${item.level}`;
      const badge = document.createElement('span');
      badge.className = 'log-level';
      badge.textContent = item.severity === null ? '未知' : levelNames[item.severity];
      const text = document.createElement('code');
      // 日志是外部文本，不能作为 HTML 插入或拼入 root 命令。
      text.textContent = item.raw;
      row.append(badge, text);
      fragment.appendChild(row);
    });
    output.appendChild(fragment);
  }
  byId('summary').textContent = loadedAt ? `显示 ${visible.length}/${rawLines.length} 行 · ${loadedAt}` : '尚未读取';
}
async function refresh() {
  if (busy) return;
  busy = true;
  byId('refresh').disabled = true;
  byId('message').textContent = '正在读取最近的内核日志…';
  byId('message').classList.remove('error');
  try {
    const logs = await exec(`${CONTROL} kernel-logs`);
    rawLines = logs.replace(/\n$/, '').split('\n').filter(line => line.length).map(parseLine);
    loadedAt = new Date().toLocaleTimeString('zh-CN', { hour12:false });
    byId('message').textContent = rawLines.length ? '已读取快照，最新记录在下方。筛选只作用于本次快照。' : '本次未读取到日志，不代表设备没有发生过错误。';
    render();
  } catch (error) {
    byId('message').textContent = `读取失败：${error.message}${loadedAt ? ' 下方保留上次成功读取的快照。' : ''}`;
    byId('message').classList.add('error');
  } finally {
    busy = false;
    byId('refresh').disabled = false;
  }
}
byId('keyword').addEventListener('input', render);
byId('level').addEventListener('change', render);
byId('refresh').addEventListener('click', refresh);
if (!window.ksu || typeof window.ksu.exec !== 'function') {
  byId('message').textContent = '请从 KernelSU 管理器中打开本模块的 WebUI，普通浏览器无法读取手机日志。';
  byId('message').classList.add('error');
  byId('refresh').disabled = true;
} else {
  refresh();
}
