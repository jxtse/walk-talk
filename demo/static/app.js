// 步语 demo 前端：SSE 分发 + 控制
const $ = sel => document.querySelector(sel);
const dialog = $('#dialog');
const flash = $('#flash');
const toolLog = $('#tool-log');
const llmRaw = $('#llm-raw');
const amapRaw = $('#amap-raw');

function addBubble(role, text) {
  const div = document.createElement('div');
  div.className = `bubble ${role === 'user' ? 'user' : 'ai'}`;
  div.textContent = text;
  dialog.appendChild(div);
  dialog.scrollTop = dialog.scrollHeight;
}

function showFlash(text, ms = 2200) {
  flash.textContent = text;
  flash.classList.add('show');
  setTimeout(() => flash.classList.remove('show'), ms);
}

function addPoiCard(p) {
  const card = document.createElement('div');
  card.className = 'poi-card';
  card.dataset.poiId = p.poi_id;
  card.innerHTML = `
    <img class="poi-img" src="${p.image_url}" alt="${p.name}">
    <div class="poi-body">
      <div class="poi-name">${p.name}</div>
      <div class="poi-meta">
        ${p.rating ? `${p.rating}★ · ` : ''}
        ${p.cost ? `¥${p.cost} · ` : ''}
        ${p.distance_m}m · 步行约 ${Math.max(1, Math.round(p.distance_m / 80))} 分钟
      </div>
      <div class="poi-tag">${p.tagline || ''}</div>
      <div class="poi-actions">
        <button class="btn-go">去看看</button>
        <button class="btn-chat">聊聊它</button>
      </div>
    </div>`;
  card.querySelector('.btn-go').onclick = () => {
    showFlash(`已为你标记方向：${p.name}`);
  };
  card.querySelector('.btn-chat').onclick = () => {
    sendText(`聊聊${p.name}`);
  };
  dialog.appendChild(card);
  dialog.scrollTop = dialog.scrollHeight;
}

function swapPoiImage(poi_id, image_url) {
  const card = dialog.querySelector(`.poi-card[data-poi-id="${poi_id}"]`);
  if (!card) return;
  const img = card.querySelector('.poi-img');
  if (img) img.src = image_url;
}

function addDirection(d) {
  const arrows = { left: '←', right: '→', up: '↑', down: '↓' };
  const div = document.createElement('div');
  div.className = 'direction-bar';
  div.innerHTML = `<span class="arrow">${arrows[d.arrow] || '•'}</span>
    <span>${d.label || ''} · ${d.distance_m}m · 步行约 ${d.eta_min} 分钟</span>`;
  dialog.appendChild(div);
  dialog.scrollTop = dialog.scrollHeight;
}

function addKeepsake(url) {
  const div = document.createElement('div');
  div.className = 'keepsake';
  div.innerHTML = `<img src="${url}?t=${Date.now()}" alt="散步合影">`;
  dialog.appendChild(div);
  dialog.scrollTop = dialog.scrollHeight;
}

function addToolLog(ev) {
  const ts = new Date().toLocaleTimeString().slice(3, 8);
  const row = document.createElement('div');
  row.className = 'log-row';
  row.innerHTML = `<span class="ts">${ts}</span>
    <span class="name">${ev.name}</span>
    <span class="src">[${ev.source || '?'}]</span>
    <span>${JSON.stringify(ev.args || {}).slice(0, 80)}</span>`;
  toolLog.prepend(row);
  while (toolLog.childElementCount > 50) toolLog.lastChild.remove();
}

function updatePtz(ev) {
  $('#ptz-pan').textContent = ev.pan ?? '-';
  $('#ptz-tilt').textContent = ev.tilt ?? '-';
  $('#ptz-zoom').textContent = ev.zoom ?? '-';
  $('#ptz-src').textContent = ev.source || '-';
}

// ============ SSE ============
const es = new EventSource('/events');
es.onmessage = (e) => {
  let ev;
  try { ev = JSON.parse(e.data); } catch { return; }
  switch (ev.type) {
    case 'dialog': addBubble(ev.role, ev.text); break;
    case 'assistant.say': addBubble('ai', ev.text); break;
    case 'user.say': addBubble('user', ev.text); break;
    case 'moment': showFlash(`已记下：${ev.label}`); break;
    case 'poi_card': addPoiCard(ev); break;
    case 'poi_image_swap': swapPoiImage(ev.poi_id, ev.image_url); break;
    case 'direction': addDirection(ev); break;
    case 'keepsake': addKeepsake(ev.url); break;
    case 'tool_call': addToolLog(ev); break;
    case 'ptz': updatePtz(ev); break;
    case 'amap_raw':
      amapRaw.textContent = JSON.stringify(ev, null, 2);
      break;
    case 'llm_raw':
      llmRaw.textContent = JSON.stringify(ev, null, 2);
      break;
    case 'script':
      console.debug('script step', ev);
      break;
  }
};

// ============ 控制 ============
async function sendText(text) {
  if (!text.trim()) return;
  await fetch('/api/say', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ text }),
  });
}

$('#send-btn').onclick = () => {
  const inp = $('#text-input');
  const t = inp.value;
  inp.value = '';
  sendText(t);
};
$('#text-input').addEventListener('keydown', (e) => {
  if (e.key === 'Enter') $('#send-btn').click();
});

$('#start-btn').onclick = async () => {
  await fetch('/api/start', { method: 'POST' });
};
$('#end-btn').onclick = async () => {
  const r = await fetch('/api/end', { method: 'POST' });
  const d = await r.json();
  if (d.keepsake_url) addKeepsake(d.keepsake_url);
};

// 场景按钮
document.querySelectorAll('.scenario-btns button[data-scenario]').forEach(btn => {
  btn.onclick = async () => {
    const scenario = btn.dataset.scenario;
    if (scenario === 'free') {
      await fetch('/api/script/stop', { method: 'POST' });
      showFlash('已切到自由模式');
      return;
    }
    const r = await fetch('/api/script/start', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ scenario }),
    });
    if (!r.ok) showFlash('启动失败：' + (await r.text()));
  };
});
$('#script-stop-btn').onclick = async () => {
  await fetch('/api/script/stop', { method: 'POST' });
  showFlash('脚本已停止');
};
