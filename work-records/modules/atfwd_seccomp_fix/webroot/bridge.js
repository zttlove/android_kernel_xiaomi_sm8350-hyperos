'use strict';
const CONTROL = '/system/bin/sh /data/adb/modules/atfwd_seccomp_fix/control.sh';
let serviceFixSequence = 0;

// Dock 是同级页面切换，不累积历史，避免侧滑返回在两页之间反复回退。
document.querySelectorAll('.dock a').forEach(link => {
  link.addEventListener('click', event => {
    event.preventDefault();
    if (link.getAttribute('aria-current') === 'page') return;
    window.location.replace(link.href);
  });
});

// 复用 KernelSU 原生桥接，页面只传入模块内固定命令，不接受外部脚本。
function exec(command) {
  return new Promise((resolve, reject) => {
    const callback = `serviceFixCallback${Date.now()}_${serviceFixSequence++}`;
    const timeout = setTimeout(() => {
      delete window[callback];
      reject(new Error('读取超时，请稍后刷新。'));
    }, 15000);
    window[callback] = (errno, stdout, stderr) => {
      clearTimeout(timeout);
      delete window[callback];
      if (errno !== 0) reject(new Error((stderr || stdout || '执行失败').trim()));
      else resolve(stdout);
    };
    try { window.ksu.exec(command, '{}', callback); }
    catch (error) {
      clearTimeout(timeout);
      delete window[callback];
      reject(error);
    }
  });
}
