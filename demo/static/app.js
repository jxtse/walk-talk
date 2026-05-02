const log = document.getElementById('log');
const flash = document.getElementById('flash');
const text = document.getElementById('text');

function appendTurn(role, content){
  const div = document.createElement('div');
  div.className = `turn ${role}`;
  div.textContent = content;
  log.appendChild(div);
  log.scrollTop = log.scrollHeight;
}
function flashMsg(s){flash.textContent=s;flash.style.opacity=1;
  setTimeout(()=>flash.style.opacity=0,1500);}

const es = new EventSource('/events');
es.onmessage = (e)=>{
  const ev = JSON.parse(e.data);
  if(ev.type==='user.say') appendTurn('user', `你：${ev.text}`);
  else if(ev.type==='assistant.say') appendTurn('assistant', `AI：${ev.text}`);
  else if(ev.type==='moment') flashMsg(`记下了：${ev.label}`);
};

async function send(t){
  if(!t) return;
  text.value='';
  await fetch('/api/say',{method:'POST',headers:{'content-type':'application/json'},
    body:JSON.stringify({text:t})});
}
document.getElementById('send').onclick=()=>send(text.value.trim());
text.addEventListener('keydown',(e)=>{if(e.key==='Enter')send(text.value.trim());});
document.getElementById('start').onclick=async()=>{
  await fetch('/api/start',{method:'POST'});appendTurn('system','— 开始散步 —');};
document.getElementById('end').onclick=async()=>{
  appendTurn('system','— 生成纪念品中… —');
  const r = await fetch('/api/end',{method:'POST'});
  const d = await r.json();
  if(d.keepsake_url){
    const panel = document.getElementById('keepsake-panel');
    panel.innerHTML = `<div class="keepsake"><img src="${d.keepsake_url}"></div>`;
  }};
