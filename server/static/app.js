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
    if (btn.dataset.tab === 'playbacks') loadPlaybacks();
    if (btn.dataset.tab === 'settings') loadStatus();
  });
});

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
        <a class="btn sm" href="/api/playback/${lessonId}/dl">下载</a>`;
    }
  } else {
    el.textContent = it && it.status === 0 ? '正在生成中, 稍后自动更新' : '暂无';
  }
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
      op = `<a class="btn sm" target="_blank" href="/api/playback/${x.lesson_id}/media">观看</a>
            <a class="btn sm" href="/api/playback/${x.lesson_id}/dl">下载</a>`;
    } else if (x.status === 0) {
      op = '<span class="hint">生成中…</span>';
    } else if (x.expired) {
      op = '<span class="hint">待同步刷新</span>';
    }
    return `<tr>
      <td>${fmtDate(x.start, false)}</td>
      <td>${fmtDate(x.start).slice(11)} - ${fmtDate(x.start + (x.start_end || 0)).slice(11)}</td>
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
