/* xdf-api 前端 */
let cal = null;

async function api(path, opts = {}) {
  const r = await fetch(path, { headers: { 'Content-Type': 'application/json' }, ...opts });
  if (!r.ok) throw new Error('HTTP ' + r.status);
  return r.json();
}

function fmtDate(ts, withTime = true) {
  const d = new Date(ts * 1000);
  const p = (n) => String(n).padStart(2, '0');
  const date = `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
  return withTime ? `${date} ${p(d.getHours())}:${p(d.getMinutes())}` : date;
}

/* ---------- Tab ---------- */
document.querySelectorAll('.tab').forEach((btn) => {
  btn.addEventListener('click', () => {
    document.querySelectorAll('.tab').forEach((b) => b.classList.remove('active'));
    btn.classList.add('active');
    document.querySelectorAll('.tabpane').forEach((p) => p.classList.remove('active'));
    document.getElementById('tab-' + btn.dataset.tab).classList.add('active');
    if (btn.dataset.tab === 'calendar' && cal) cal.render();
    if (btn.dataset.tab === 'classes') loadClasses();
    if (btn.dataset.tab === 'playbacks') loadPlaybacks();
    if (btn.dataset.tab === 'settings') loadStatus();
  });
});

/* ---------- 下载(代理/直连, 由设置页开关控制) ---------- */
let downloadDirect = false;

function dlLink(lessonId, label) {
  if (downloadDirect) {
    return `<a class="btn sm" href="javascript:void(0)" onclick="downloadDirectCDN('${lessonId}', this)" title="CDN 直连下载(浏览器直接拉取 CDN, 不占服务器流量; 浏览器无法保存时直接打开 CDN 链接)">${label}</a>`;
  }
  return `<a class="btn sm" href="/api/playback/${lessonId}/dl" title="服务器代理下载(文件名按模板, 支持断点续传)">${label}</a>`;
}

// CDN 直连下载(严格模式): 浏览器 fetch 流式拉取 CDN 后本地保存为模板文件名, 不经过服务器代理。
// 1) File System Access API(Chromium): 流式写盘, 带进度, 保存框预填模板文件名
// 2) 回退 Blob 下载(文件名仍按模板; >1.5GB 且无流式能力时改为打开 CDN 链接, 避免爆内存)
// 3) fetch 被跨域白名单拦截等无法保存时: 直接打开 CDN 链接(浏览器播放/右键另存), 不回退服务器代理
const CDN_BLOCK_KEY = 'xdf_cdn_direct_blocked'; // 无法保存的记忆(仅当前标签页会话), 避免反复浪费请求

async function downloadDirectCDN(lessonId, el) {
  const orig = el.textContent;
  const fmtSize = (n) => n > 1048576 ? (n / 1048576).toFixed(0) + 'MB' : (n / 1024).toFixed(0) + 'KB';
  const finish = (msg) => { el.textContent = msg; setTimeout(() => { el.textContent = orig; }, 3000); };
  const openCDN = (url) => {
    const w = window.open(url, '_blank');
    finish(w ? '已打开 CDN 链接' : '弹窗被拦截, 请允许后重试');
  };

  let info;
  try {
    el.textContent = '连接 CDN…';
    info = await api(`/api/playback/${lessonId}/link`);
  } catch (e) {
    finish(String(e).includes('HTTP 410') ? '签名已过期, 稍后重试' : '获取直连地址失败');
    return;
  }
  if (sessionStorage.getItem(CDN_BLOCK_KEY)) { openCDN(info.url); return; } // 本会话已知无法保存: 直接打开

  let resp;
  try {
    resp = await fetch(info.url); // 跨域白名单拦截时在此抛 TypeError
  } catch (e) {
    sessionStorage.setItem(CDN_BLOCK_KEY, '1');
    console.warn('浏览器无法直连保存(跨域限制等), 改为打开 CDN 链接:', e);
    openCDN(info.url);
    return;
  }
  if (!resp.ok) {
    finish('CDN 返回 ' + resp.status + ', 待同步刷新后重试');
    return;
  }
  sessionStorage.removeItem(CDN_BLOCK_KEY);
  const total = parseInt(resp.headers.get('Content-Length') || '0', 10);
  try {
    if (window.showSaveFilePicker) {
      let handle;
      try {
        handle = await window.showSaveFilePicker({ suggestedName: info.name });
      } catch (e) {
        if (resp.body) await resp.body.cancel();
        if (e.name === 'AbortError') { el.textContent = orig; return; } // 用户取消保存
        throw e;
      }
      const writable = await handle.createWritable();
      const reader = resp.body.getReader();
      let received = 0;
      for (;;) {
        const { done, value } = await reader.read();
        if (done) break;
        await writable.write(value);
        received += value.length;
        el.textContent = total ? `下载 ${Math.round(received / total * 100)}%` : `下载 ${fmtSize(received)}`;
      }
      await writable.close();
      finish('✓ 完成');
    } else if (total > 1610612736) {
      if (resp.body) await resp.body.cancel();
      openCDN(info.url); // >1.5GB 且无流式保存能力, 打开 CDN 链接避免 Blob 爆内存
    } else {
      const blob = await resp.blob();
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = info.name;
      document.body.appendChild(a);
      a.click();
      a.remove();
      setTimeout(() => URL.revokeObjectURL(url), 120000);
      finish('✓ 完成');
    }
  } catch (e) {
    console.warn('CDN 直连保存中断:', e);
    finish('保存中断, 请重试');
  }
}

/* ---------- 状态栏 ---------- */
async function loadStatus() {
  try {
    const s = await api('/api/status');
    const bits = [];
    if (s.token_mask) {
      let t = `Token ${s.token_mask}`;
      if (s.token_exp >= 0) {
        const days = Math.floor(s.token_exp / 86400);
        bits.push(t + `（剩余${days}天）`);
      } else bits.push(t);
    } else bits.push('未配置 Token');
    if (s.last_sync) bits.push('上次同步 ' + new Date(s.last_sync * 1000).toLocaleString());
    if (!s.last_sync_err) bits.push(`课表 ${s.lesson_count} · 回放 ${s.playback_count}`);
    document.getElementById('statusbar').textContent = bits.join(' · ');
    document.getElementById('s-token-hint').textContent = s.token_mask || '';
    downloadDirect = !!s.download_direct;
    const ck = document.getElementById('s-direct');
    if (ck) ck.checked = downloadDirect;
    const tpl = document.getElementById('s-dltpl');
    if (tpl && !tpl.value) tpl.value = s.dl_name_template || '';
  } catch (e) { /* 忽略 */ }
}

/* ---------- 日历 ---------- */
function initCalendar() {
  const el = document.getElementById('calendar');
  cal = new FullCalendar.Calendar(el, {
    locale: 'zh-cn',
    initialView: 'dayGridMonth',
    height: 'auto',
    headerToolbar: { left: 'prev,next today', center: 'title', right: 'dayGridMonth,dayGridWeek' },
    eventTimeFormat: { hour: '2-digit', minute: '2-digit', hour12: false },
    eventClick: (info) => showLesson(info.event),
    events: (info, success, failure) => {
      const from = Math.floor(new Date(info.startStr).getTime() / 1000) - 86400;
      const to = Math.floor(new Date(info.endStr).getTime() / 1000) + 86400;
      api(`/api/lessons?from=${from}&to=${to}`).then(success).catch(() => success([]));
    },
  });
  cal.render();
}

function showLesson(ev) {
  const p = ev.extendedProps || {};
  const st = {
    0: '未开始',
    1: '进行中',
    2: '已完成',
  }[ev.start && new Date(ev.end) < new Date() ? 2 : 1] || '';
  document.getElementById('m-title').textContent = ev.title;
  const body = document.getElementById('m-body');
  body.innerHTML = `
    <div class="kv"><span>日期</span><b>${fmtDate(Math.floor(new Date(ev.start) / 1000))}</b></div>
    <div class="kv"><span>时间</span><b>${ev.start.slice(11, 16)} - ${ev.end.slice(11, 16)}</b></div>
    <div class="kv"><span>主讲</span><b>${p.teacher || '-'}</b></div>
    <div class="kv"><span>房间</span><b>${p.roomCode || '-'}</b></div>
    <div class="kv"><span>录像</span><b>${p.record ? '有' : '无'}</b></div>
    ${p.record ? `<div class="kv"><span>回放</span><b id="m-pb-status">加载中…</b></div>` : ''}`;
  if (p.record) checkPlaybackInModal(p.lessonId);
  document.getElementById('modal').style.display = 'flex';
}

async function checkPlaybackInModal(lessonId) {
  const list = await api('/api/playbacks');
  const it = list.find((x) => x.lesson_id === lessonId);
  const el = document.getElementById('m-pb-status');
  if (!el) return;
  if (it && it.status === 1 && it.has_url) {
    if (it.expired) {
      el.textContent = '签名已过期, 等待自动刷新';
    } else {
      el.innerHTML = `<a class="btn sm" target="_blank" href="/api/playback/${lessonId}/media">在线观看</a>
        ${dlLink(lessonId, '下载')}`;
    }
  } else {
    el.textContent = it && it.status === 0 ? '正在生成中, 稍后自动更新' : '暂无';
  }
}

/* ---------- 课程(按班级分类) ---------- */
let classCache = [];
let activeClassId = null;

async function loadClasses() {
  const list = await api('/api/classes');
  classCache = list;
  const aside = document.getElementById('class-list');
  const stText = { active: '已开课', ended: '已结课', upcoming: '未开课' };
  aside.innerHTML = list.map((c) => `
    <div class="class-item${c.class_id === activeClassId ? ' active' : ''}" data-cid="${c.class_id}">
      <div class="ci-head">
        <span class="ci-name">${c.name || '未命名课程'}</span>
        <span class="badge ${c.status === 'active' ? 'ok' : 'idle'}">${stText[c.status] || ''}</span>
      </div>
      <div class="ci-sub">${fmtDate(c.first_lesson, false)} ~ ${fmtDate(c.last_lesson, false)}</div>
      <div class="ci-sub">班级编码: ${c.code || '-'} · 共 ${c.lesson_count} 讲 · 回放 ${c.playback_count}</div>
      ${c.teacher ? `<div class="ci-sub">主讲: ${c.teacher}</div>` : ''}
    </div>`).join('') || '<div class="hint" style="padding:12px">暂无课程数据，请先在设置页配置 token 并同步</div>';
  aside.querySelectorAll('.class-item').forEach((el) => {
    el.addEventListener('click', () => {
      activeClassId = el.dataset.cid;
      aside.querySelectorAll('.class-item').forEach((x) => x.classList.toggle('active', x === el));
      loadClassLessons(activeClassId);
    });
  });
  if (activeClassId && !list.some((c) => c.class_id === activeClassId)) activeClassId = null;
  if (activeClassId) loadClassLessons(activeClassId);
}

async function loadClassLessons(classId) {
  const c = classCache.find((x) => x.class_id === classId);
  document.getElementById('class-title').textContent = c ? c.name : classId;
  document.getElementById('class-hint').textContent = c ? `共 ${c.lesson_count} 讲 · 回放 ${c.playback_count} 讲` : '';
  const lessons = await api(`/api/classes/${classId}/lessons`);
  const tbody = document.querySelector('#class-table tbody');
  tbody.innerHTML = lessons.map((x) => {
    let st = '<span class="badge idle">未生成</span>';
    if (x.status === 1 && x.has_url) st = x.expired ? '<span class="badge warn">已过期</span>' : '<span class="badge ok">可观看</span>';
    else if (x.status === 0) st = '<span class="badge idle">生成中</span>';
    let op = '<span class="hint">-</span>';
    if (x.status === 1 && x.has_url && !x.expired) {
      op = `<a class="btn sm" target="_blank" href="/api/playback/${x.lesson_id}/media">观看</a>${dlLink(x.lesson_id, '下载')}`;
    }
    if (x.report_url) op += `<a class="btn sm" target="_blank" href="${x.report_url}" title="学习报告">报告</a>`;
    return `<tr>
      <td>${fmtDate(x.start, false)}</td>
      <td>${fmtDate(x.start).slice(11)} - ${fmtDate(x.end).slice(11)}</td>
      <td>${x.title}</td>
      <td>${x.teacher || '-'}</td>
      <td>${st}</td><td>${op}</td></tr>`;
  }).join('') || '<tr><td colspan="6" class="hint">该课程暂无讲次记录</td></tr>';
}

/* ---------- 回放 ---------- */
async function loadPlaybacks() {
  const list = await api('/api/playbacks');
  const tbody = document.querySelector('#pb-table tbody');
  const withRec = list.filter((x) => x.status === 1 || x.start > Math.floor(Date.now() / 1000) - 86400 * 60);
  document.getElementById('pb-hint').textContent = `共 ${withRec.length} 节`;
  tbody.innerHTML = withRec.map((x) => {
    let st = '<span class="badge idle">未生成</span>';
    if (x.status === 1 && x.has_url) st = x.expired ? '<span class="badge warn">已过期</span>' : '<span class="badge ok">可观看</span>';
    let op = '<span class="hint">-</span>';
    if (x.status === 1 && x.has_url && !x.expired) {
      op = `<a class="btn sm" target="_blank" href="/api/playback/${x.lesson_id}/media">观看</a>${dlLink(x.lesson_id, '下载')}`;
    } else if (x.status === 0) {
      op = '<span class="hint">生成中…</span>';
    } else if (x.expired) {
      op = '<span class="hint">待同步刷新</span>';
    }
    return `<tr>
      <td>${fmtDate(x.start, false)}</td>
      <td>${fmtDate(x.start).slice(11)} - ${fmtDate(x.end).slice(11)}</td>
      <td>${x.title}</td>
      <td>${x.teacher ? x.teacher : '-'}</td>
      <td>${st}</td><td>${op}</td></tr>`;
  }).join('');
}

/* ---------- 设置 ---------- */
async function saveSettings() {
  const body = {
    token: document.getElementById('s-token').value,
    webhook_url: document.getElementById('s-whook').value,
    webhook_type: document.getElementById('s-wtype').value,
    notify_minutes: parseInt(document.getElementById('s-nmin').value || '5', 10),
    download_direct: document.getElementById('s-direct').checked,
    dl_name_template: document.getElementById('s-dltpl').value,
  };
  try {
    await api('/api/settings', { method: 'POST', body: JSON.stringify(body) });
    document.getElementById('s-token').value = '';
    alert('已保存, 后台正在同步课表');
    loadStatus();
  } catch (e) { alert('保存失败: ' + e.message); }
}

async function testNotify() {
  try { await api('/api/notify/test', { method: 'POST' }); alert('测试通知已发送'); }
  catch (e) { alert('发送失败: ' + e.message); }
}

async function doSync() {
  await api('/api/sync', { method: 'POST' });
  alert('已触发同步, 稍后刷新页面查看');
  setTimeout(loadStatus, 2000);
}

function closeModal() { document.getElementById('modal').style.display = 'none'; }

initCalendar();
loadStatus();
