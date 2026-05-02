// 步语 demo · mockup + 真实交互
const $ = sel => document.querySelector(sel);
const $$ = sel => Array.from(document.querySelectorAll(sel));
const flash = $('#flash');
const dialog = $('#dialog');
const drawer = $('#dialog-drawer');
const toolLog = $('#tool-log');
const llmRaw = $('#llm-raw');
const amapRaw = $('#amap-raw');

function selectRoute(scenario) {
  window._pendingScenario = scenario;
  // 切换 s3 mockup 上的覆盖层：仅金陵天地有自定义详情，其它路线沿用 mockup 原图
  document.querySelectorAll('.route-detail-overlay').forEach(o => {
    o.style.display = 'none';
  });
  const detail = document.getElementById('route-detail-' + scenario);
  if (detail) detail.style.display = 'block';
  gotoScreen('s3');
}

// ============ 屏切换 ============
let currentScreen = 's1';
let transitioning = false;
const ANIM_MAP = {
  'fade':  ['anim-fade'],
  'slide': ['anim-slide'],
  'up':    ['anim-up'],
  'zoom':  ['anim-zoom'],
};
function gotoScreen(id) {
  if (transitioning || id === currentScreen) return;
  const target = document.getElementById(id);
  if (!target) return;
  transitioning = true;
  const old = document.getElementById(currentScreen);
  const animKind = (target.dataset.anim || 'fade-in')
    .replace('-in','').replace('slide-right','slide').replace('slide-up','up').replace('zoom-in','zoom');
  const enterCls = ANIM_MAP[animKind] ? ANIM_MAP[animKind][0] : 'anim-fade';

  target.classList.add('active', enterCls);
  setTimeout(() => {
    if (old) old.classList.remove('active');
    target.classList.remove(enterCls);
    currentScreen = id;
    transitioning = false;
  }, 380);
}

// hotspot click delegation（仅用于纯 .hot 元素）
$$('.screen').forEach(scr => {
  scr.addEventListener('click', (e) => {
    const r = document.createElement('div');
    r.className = 'ripple';
    const rect = scr.getBoundingClientRect();
    r.style.width = r.style.height = '50px';
    r.style.left = (e.clientX - rect.left - 25) + 'px';
    r.style.top  = (e.clientY - rect.top  - 25) + 'px';
    scr.appendChild(r);
    setTimeout(() => r.remove(), 500);
  });
});

// 通用：所有带 data-go / data-action 的元素
document.body.addEventListener('click', (e) => {
  const el = e.target.closest('[data-go],[data-action]');
  if (!el) return;
  // 跳过技术面板按钮（它们有自己的逻辑）
  if (el.closest('.tech')) return;
  handleAction(el);
});

function handleAction(el) {
  const action = el.dataset.action;
  const scenario = el.dataset.scenario;
  const route = el.dataset.route;
  const go = el.dataset.go;

  if (action === 'start' || action === 'login') {
    fetch('/api/start', { method: 'POST' });
  }
  if (action === 'select-route' && scenario) {
    showFlash(`选择路线：${route || scenario}`);
    selectRoute(scenario);
    return;
  }
  if (action === 'depart') {
    const sc = window._pendingScenario || 'companion';
    resetWalkSession();
    fetch('/api/script/start', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ scenario: sc }),
    });
    setSceneVideo(sc);
    setStopBtn(true);
    showFlash('出发！');
    startWalkClock();
  }
  if (action === 'freemode') {
    fetch('/api/script/stop', { method: 'POST' });
    fetch('/api/start', { method: 'POST' });
    setSceneVideo(null);
    setStopBtn(false);
    showFlash('已进入自由模式');
    resetWalkSession();
    startWalkClock();
  }
  if (action === 'mark') showFlash('已为你标记方向');
  if (action === 'skip') showFlash('跳过');
  if (action === 'poi-yes') {
    showFlash('好，带你过去');
    if (window._currentPoi) {
      const p = window._currentPoi;
      fetch('/api/say', {
        method: 'POST', headers: {'content-type':'application/json'},
        body: JSON.stringify({text: `好，带我去${p.name}`}),
      });
    }
  }
  if (action === 'poi-no') {
    showFlash('好，下一个');
    if (window._currentPoi) {
      fetch('/api/say', {
        method: 'POST', headers: {'content-type':'application/json'},
        body: JSON.stringify({text: '不去这个，继续走'}),
      });
    }
  }
  if (action === 'poi-chat') {
    openDrawer();
    if (window._currentPoi) {
      const p = window._currentPoi;
      $('#text-input').focus();
      $('#text-input').value = `跟我聊聊${p.name}`;
    }
    gotoScreen('s4');
    return;
  }
  if (action === 'end') {
    stopWalkClock();
    setSceneVideo(null);
    setStopBtn(false);
    fetch('/api/end', { method: 'POST' })
      .then(r => r.json()).then(d => {
        if (d.keepsake_url) showKeepsake(d.keepsake_url);
        renderS6Notes();
        renderS7Plog();
      });
  }
  if (action === 'plog') {
    fetch('/api/end', { method: 'POST' })
      .then(r => r.json()).then(d => {
        if (d.keepsake_url) showKeepsake(d.keepsake_url);
        renderS7Plog();
      });
  }
  if (action === 'share') showFlash('已生成分享卡片 ✓');
  if (action === 'save')  showFlash('已保存到相册 ✓');

  if (go) {
    if (go === 's5') ensureDemoPoi();
    if (go === 's6') renderS6Notes();
    if (go === 's7') renderS7Plog();
    gotoScreen(go);
  }
}

// 跳转屏快捷按钮
$$('.screen-jump button').forEach(b => {
  b.onclick = () => {
    if (b.dataset.jump === 's5') ensureDemoPoi();
    if (b.dataset.jump === 's6') renderS6Notes();
    if (b.dataset.jump === 's7') renderS7Plog();
    gotoScreen(b.dataset.jump);
  };
});

// ============ flash + 抽屉 ============
function showFlash(text, ms = 1800) {
  flash.textContent = text;
  flash.classList.add('show');
  setTimeout(() => flash.classList.remove('show'), ms);
}
function openDrawer() {
  drawer.classList.add('open');
  // 抽屉在手机 mockup 的底部，浏览器视口可能装不下整台手机，
  // 打开后把输入框滚到可见位置，避免用户看不到打字框。
  setTimeout(() => {
    const inp = document.getElementById('text-input');
    if (inp) inp.scrollIntoView({ behavior: 'smooth', block: 'center' });
  }, 380);
}

$('#drawer-handle').onclick = openDrawer;
drawer.querySelector('.drawer-grip').onclick = () => drawer.classList.toggle('open');

// ============ 散步状态（用于 s4 hud + s6/s7 渲染） ============
const walkState = {
  start: 0,
  ticking: false,
  timer: null,
  moments: [],     // {label, ts}
  poiCards: [],    // {name, image_url, tagline}
  bubbles: [],     // {role, text, ts}
};

function resetWalkSession() {
  walkState.start = Date.now();
  walkState.moments = [];
  walkState.poiCards = [];
  walkState.bubbles = [];
  $('#walk-time').textContent = '00:00';
  $('#walk-dist').textContent = '0.0';
  if (toolLog) toolLog.innerHTML = '';
  const strip = $('#moments-strip');
  if (strip) strip.innerHTML = '';
  if (llmRaw) llmRaw.textContent = '';
  if (amapRaw) amapRaw.textContent = '';
  dialog.innerHTML = '';
  const finale = document.getElementById('finale-overlay');
  if (finale) finale.style.display = 'none';
  const ks = document.getElementById('keepsake-overlay');
  if (ks) ks.style.display = 'none';
}
function startWalkClock() {
  walkState.start = walkState.start || Date.now();
  walkState.ticking = true;
  if (walkState.timer) clearInterval(walkState.timer);
  walkState.timer = setInterval(() => {
    if (!walkState.ticking) return;
    const sec = Math.floor((Date.now() - walkState.start) / 1000);
    const mm = String(Math.floor(sec / 60)).padStart(2, '0');
    const ss = String(sec % 60).padStart(2, '0');
    $('#walk-time').textContent = `${mm}:${ss}`;
    // 粗略：1 m/s 步行，实际距离前端模拟
    $('#walk-dist').textContent = (sec / 1200).toFixed(1);
  }, 1000);
}
function stopWalkClock() { walkState.ticking = false; }

// ============ 对话气泡 ============
function addBubble(role, text) {
  const div = document.createElement('div');
  div.className = `bubble ${role === 'user' ? 'user' : 'ai'}`;
  div.textContent = text;
  dialog.appendChild(div);
  dialog.scrollTop = dialog.scrollHeight;
  if (role !== 'user') {
    const t = document.getElementById('ai-bubble-text');
    if (t) t.textContent = text;
  }
  if (role === 'user') openDrawer();
  walkState.bubbles.push({ role, text, ts: Date.now() });
  if (walkState.bubbles.length > 200) walkState.bubbles.shift();
}

// ============ POI 卡片（s5） ============
const DEMO_POI = {
  name: '云梦公园',
  tagline: '夜樱倒影，水面像被点亮',
  image_url: '/static/routes/jinling/yunmeng_01_云梦公园_夜樱倒影.jpg',
  distance_m: 220,
  rating: 4.7,
};
function ensureDemoPoi() {
  // 没有任何 POI 被推过的时候，用一张默认图填，让 s5 不至于空白
  // 注意：只填 DOM，不写入 walkState，避免污染 s7 plog
  if (window._currentPoi) return;
  const p = DEMO_POI;
  $('#poi-img').src = p.image_url;
  $('#poi-name').textContent = p.name;
  $('#poi-tag').textContent = p.tagline;
  $('#poi-dist').textContent = `${p.distance_m} m`;
  $('#poi-rating').textContent = `★ ${p.rating}`;
}
function showPoiCard(p) {
  $('#poi-img').src = p.image_url || '';
  $('#poi-name').textContent = p.name || '';
  $('#poi-tag').textContent = p.tagline || '';
  const distEl = $('#poi-dist');
  const rateEl = $('#poi-rating');
  if (distEl) distEl.textContent = (p.distance_m != null ? `${p.distance_m} m` : '');
  if (rateEl) rateEl.textContent = (p.rating != null ? `★ ${p.rating}` : '');
  window._currentPoi = p;
  walkState.poiCards.push({
    name: p.name, image_url: p.image_url, tagline: p.tagline,
  });
  gotoScreen('s5');
}
function swapPoiImage(_id, url) {
  $('#poi-img').src = url;
  // 同时更新最近一张 poiCard 的图，让 plog 用最新内景
  if (walkState.poiCards.length) {
    walkState.poiCards[walkState.poiCards.length - 1].image_url = url;
  }
}

// ============ keepsake ============
function showKeepsake(url) {
  console.log('[keepsake] showKeepsake called with', url);
  // Stop the looping scenario video first so attention shifts to the finale.
  try { setSceneVideo(null); } catch (e) { console.warn(e); }
  try { setStopBtn(false); } catch (e) { console.warn(e); }

  // Primary path: full-phone finale overlay (independent of screen system).
  const finale = document.getElementById('finale-overlay');
  const finaleImg = document.getElementById('finale-img');
  if (finale && finaleImg) {
    finaleImg.src = url + '?t=' + Date.now();
    finale.style.display = 'flex';
    const closeBtn = document.getElementById('finale-close');
    if (closeBtn && !closeBtn._wired) {
      closeBtn._wired = true;
      closeBtn.addEventListener('click', () => {
        finale.style.display = 'none';
      });
    }
    console.log('[keepsake] finale overlay shown');
  } else {
    console.warn('[keepsake] finale overlay missing, falling back to s7');
  }

  // Also populate the s7 keepsake overlay so navigating to s7 still shows it.
  const wrap = document.getElementById('keepsake-overlay');
  const img = document.getElementById('keepsake-img');
  if (wrap && img) {
    img.src = url + '?t=' + Date.now();
    wrap.style.display = 'block';
  }
}

// ============ Concept card (scenario-3 exhibit explanations) ============
function showConceptCard(ev) {
  const overlay = document.getElementById('concept-overlay');
  if (!overlay) return;
  document.getElementById('concept-title').textContent = ev.title || '';
  document.getElementById('concept-subtitle').textContent = ev.subtitle || '';
  const img = document.getElementById('concept-img');
  if (ev.image_url) { img.src = ev.image_url; img.style.display = ''; }
  else { img.removeAttribute('src'); img.style.display = 'none'; }
  document.getElementById('concept-body').textContent = ev.body || '';
  const tagsEl = document.getElementById('concept-tags');
  tagsEl.innerHTML = '';
  (ev.tags || []).forEach(t => {
    const s = document.createElement('span'); s.textContent = t; tagsEl.appendChild(s);
  });
  overlay.style.display = 'flex';
}
function hideConceptCard() {
  const overlay = document.getElementById('concept-overlay');
  if (overlay) overlay.style.display = 'none';
}
// Scripted scenarios can simulate the user tapping the 是/否 button on a
// POI card so the demo reads like a continuous interaction.
function simulatePoiChoice(ev) {
  const sel = ev.choice === 'no'
    ? '.poi-btn[data-action="poi-no"]'
    : '.poi-btn[data-action="poi-yes"]';
  const btn = document.querySelector(sel);
  if (!btn) return;
  // Make the button itself the positioning context for the falling dot.
  if (getComputedStyle(btn).position === 'static') {
    btn.style.position = 'relative';
  }
  // Re-trigger the pulse animation cleanly.
  btn.classList.remove('tap-flash');
  void btn.offsetWidth;
  btn.classList.add('tap-flash');
  // Drop a fingertip dot on top of the button.
  const dot = document.createElement('span');
  dot.className = 'tap-dot';
  btn.appendChild(dot);
  setTimeout(() => dot.remove(), 950);
  setTimeout(() => btn.classList.remove('tap-flash'), 950);
  showFlash(ev.choice === 'no' ? '已跳过' : '好，带你过去');
  // After the tap animation finishes, hop back to s4 like a real tap would.
  setTimeout(() => gotoScreen('s4'), 1000);
}
document.addEventListener('DOMContentLoaded', () => {
  const btn = document.getElementById('concept-close');
  if (btn) btn.onclick = hideConceptCard;
  const ov = document.getElementById('concept-overlay');
  if (ov) ov.addEventListener('click', (e) => {
    if (e.target === ov) hideConceptCard();
  });
});

// ============ moment ============
function recordMoment(label) {
  walkState.moments.push({ label, ts: Date.now() });
  showFlash(`已记下：${label}`);
}

// ============ s6 笔记渲染（覆盖在 mockup 之上） ============
function renderS6Notes() {
  const strip = $('#moments-strip');
  if (!strip) return;
  strip.innerHTML = walkState.moments
    .map(m => `<span class="mt">${m.label}</span>`).join('');
}

// ============ s7 plog 渲染：把沿途看过的真实 POI 图叠到 mockup 的两个相册位上 ============
function renderS7Plog() {
  const cards = walkState.poiCards.filter(p => p.image_url);
  const slots = ['#plog-photo-1', '#plog-photo-2'];
  slots.forEach((sel, i) => {
    const el = $(sel);
    if (!el) return;
    const card = cards[i];
    if (card) {
      el.style.display = 'block';
      el.querySelector('img').src = card.image_url;
      el.querySelector('.plog-caption').textContent = card.name || '';
    } else {
      el.style.display = 'none';
    }
  });
}

// ============ 工具日志 + ptz ============
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

// ============ direction overlay ============
function addDirection(d) {
  const arrows = { left: '←', right: '→', up: '↑', down: '↓' };
  showFlash(`${arrows[d.arrow] || '•'} ${d.label || ''} · ${d.distance_m}m`);
}

// ============ Scene video swap (mjpeg <-> scenario mp4) ============
function setSceneVideo(scenario, opts) {
  const img = document.getElementById('cam-mjpeg');
  const vid = document.getElementById('cam-scene');
  if (!vid || !img) return;
  if (scenario && scenario !== 'free') {
    vid.src = `/static/scenes/${scenario}.mp4`;
    vid.style.display = 'block';
    img.style.display = 'none';
    vid.currentTime = 0;
    vid.loop = !(opts && opts.loop === false);
    vid.play().catch((e) => console.warn('scene video play failed', e));
  } else {
    vid.pause();
    vid.removeAttribute('src');
    vid.load();
    vid.style.display = 'none';
    img.style.display = 'block';
    vid.loop = true; // restore default
  }
}

// ============ SSE ============
const es = new EventSource('/events');
es.onmessage = (e) => {
  let ev;
  try { ev = JSON.parse(e.data); } catch { return; }
  switch (ev.type) {
    case 'dialog':        addBubble(ev.role, ev.text); break;
    case 'assistant.say': addBubble('ai', ev.text); break;
    case 'user.say':      addBubble('user', ev.text); break;
    case 'moment':        recordMoment(ev.label); break;
    case 'poi_card':      showPoiCard(ev); break;
    case 'poi_image_swap':swapPoiImage(ev.poi_id, ev.image_url); break;
    case 'direction':     addDirection(ev); break;
    case 'keepsake':
      console.log('[sse] keepsake', ev.url);
      showKeepsake(ev.url);
      break;
    case 'tool_call':     addToolLog(ev); break;
    case 'ptz':           updatePtz(ev); break;
    case 'amap_raw':      amapRaw.textContent = JSON.stringify(ev, null, 2); break;
    case 'llm_raw': {
      // Scripted scenarios stream "internal monologue" via llm_raw events
      // with a phase tag. Append those so the panel reads as a trace; for
      // free-mode (no phase), keep the old behaviour of pretty-printing.
      if (ev.phase) {
        const ts = new Date().toLocaleTimeString().slice(3, 8);
        const tag = ev.phase === 'thought' ? '🧠 thought'
                  : ev.phase === 'observe' ? '👁 observe'
                  : ev.phase === 'plan'    ? '📝 plan'
                  : ev.phase === 'speak'   ? '🗣 speak'
                  : ev.phase;
        llmRaw.textContent =
          `[${ts}] ${tag}\n${ev.text || ''}\n\n` + (llmRaw.textContent || '');
        // cap to ~6KB to avoid runaway growth during long scenarios
        if (llmRaw.textContent.length > 6000) {
          llmRaw.textContent = llmRaw.textContent.slice(0, 6000);
        }
      } else {
        llmRaw.textContent = JSON.stringify(ev, null, 2);
      }
      break;
    }
    case 'script':        console.debug('script step', ev); break;
    case 'script_state': {
      console.debug('[script_state]', ev);
      const btn = document.getElementById('script-stop-btn');
      if (btn) btn.style.display = ev.playing ? 'inline-block' : 'none';
      if (!ev.playing) setSceneVideo(null);
      break;
    }
    case 'session_reset': {
      // Backend has cleared dialog/moments; mirror it on the client so
      // scenarios stay isolated from each other.
      resetWalkSession();
      hideConceptCard();
      break;
    }
    case 'concept_card':         showConceptCard(ev); break;
    case 'concept_card_dismiss': hideConceptCard(); break;
    case 'poi_choice':           simulatePoiChoice(ev); break;
  }
};

// ============ 输入栏 ============
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

// ============ 演示控制 ============
function setStopBtn(show) {
  const btn = document.getElementById('script-stop-btn');
  if (btn) btn.style.display = show ? 'inline-block' : 'none';
}
$$('.scenario-btns button[data-scenario]').forEach(btn => {
  btn.onclick = async () => {
    const scenario = btn.dataset.scenario;
    if (scenario === 'free') {
      await fetch('/api/script/stop', { method: 'POST' });
      await fetch('/api/start', { method: 'POST' });
      setSceneVideo(null);
      setStopBtn(false);
      resetWalkSession();
      startWalkClock();
      gotoScreen('s4');
      showFlash('已进入自由模式 · LLM/Whisper 已就绪');
      return;
    }
    resetWalkSession();
    const r = await fetch('/api/script/start', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ scenario }),
    });
    if (!r.ok) showFlash('启动失败：' + (await r.text()));
    else {
      // 默认所有场景循环播放（剧本时长大于视频时长）
      setSceneVideo(scenario);
      setStopBtn(true);
      startWalkClock();
      gotoScreen('s4');
    }
  };
});
$('#script-stop-btn').onclick = async () => {
  await fetch('/api/script/stop', { method: 'POST' });
  setSceneVideo(null);
  setStopBtn(false);
  stopWalkClock();
  showFlash('脚本已停止');
};

// ============ 麦克风（Whisper） ============
let recorder = null, chunks = [], stream = null;
const micBtn = $('#mic-fab');

async function startRecording() {
  try {
    stream = await navigator.mediaDevices.getUserMedia({ audio: true });
  } catch { showFlash('麦克风权限被拒'); return; }
  const mime = MediaRecorder.isTypeSupported('audio/webm;codecs=opus')
    ? 'audio/webm;codecs=opus' : 'audio/webm';
  recorder = new MediaRecorder(stream, { mimeType: mime });
  chunks = [];
  recorder.ondataavailable = (e) => { if (e.data.size) chunks.push(e.data); };
  recorder.onstop = async () => {
    const blob = new Blob(chunks, { type: mime });
    stream.getTracks().forEach(t => t.stop());
    micBtn.classList.remove('recording');
    showFlash('转写中…', 1200);
    const fd = new FormData();
    fd.append('audio', blob, 'voice.webm');
    try {
      const r = await fetch('/api/voice', { method: 'POST', body: fd });
      if (!r.ok) {
        const errText = await r.text().catch(() => '');
        if (r.status === 429) showFlash('Whisper 限流(429)，请稍后', 2400);
        else showFlash(`转写失败 ${r.status}: ${errText.slice(0,60)}`, 2400);
        return;
      }
      const d = await r.json();
      if (d.text) {
        openDrawer();
        $('#text-input').value = d.text;
        sendText(d.text);
        $('#text-input').value = '';
      } else showFlash('没听清');
    } catch (e) { showFlash('转写失败：' + e.message, 2400); }
  };
  recorder.start();
  micBtn.classList.add('recording');
}
function stopRecording() {
  if (recorder && recorder.state === 'recording') {
    recorder.stop(); recorder = null;
  }
}
micBtn.onclick = () => {
  if (recorder && recorder.state === 'recording') stopRecording();
  else startRecording();
};

// ============ init ============
// 默认场景：进入 s3 前会通过 selectRoute 切换覆盖层

