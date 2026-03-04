const bmwCss = document.getElementById('bmwCss');
const audiCss = document.getElementById('audiCss');

const fobBmw = document.getElementById('fobBmw');
const fobAudi = document.getElementById('fobAudi');

const batteryCircleBmw = document.getElementById('batteryCircleBmw');
const audiLed = document.getElementById('audiLed');

let theme = 'bmw';          // 'bmw' | 'audi'
let battery = 100;
let outOfRange = false;

const clickSound = new Audio("assets/bmw_click.wav");
clickSound.volume = 0.4;

function bootHidden(){
  // 1) garante que nada aparece no boot
  outOfRange = false;
  battery = 100;
  theme = 'bmw';

  document.body.classList.remove('oor');

  // 2) desliga CSS (opcional, mas evita qualquer flash)
  if (bmwCss) bmwCss.disabled = true;
  if (audiCss) audiCss.disabled = true;

  // 3) esconde ambos layouts e remove animação
  if (fobBmw){
    fobBmw.classList.add('hidden');
    fobBmw.classList.remove('show');
  }
  if (fobAudi){
    fobAudi.classList.add('hidden');
    fobAudi.classList.remove('show');
  }

  // 4) (opcional) esconder o body até abrir — zero flicker
  document.body.classList.add('nui-hidden');
}

bootHidden();

function playClick(){
  clickSound.currentTime = 0;
  clickSound.play().catch(()=>{});
}

function setTheme(t){
  theme = (t === 'audi') ? 'audi' : 'bmw';

  // ativa CSS correto
  bmwCss.disabled = (theme !== 'bmw');
  audiCss.disabled = (theme !== 'audi');

  // mostra só o layout correto (mas ainda fechado até open)
  fobBmw.classList.add('hidden'); fobBmw.classList.remove('show');
  fobAudi.classList.add('hidden'); fobAudi.classList.remove('show');

  outOfRange = false;
  document.body.classList.remove('oor');
}

function openFob(level){
  battery = Number(level ?? 100);

  // mostrar UI agora (remove o hide global)
  document.body.classList.remove('nui-hidden');

  // ativa CSS correto
  if (bmwCss) bmwCss.disabled = (theme !== 'bmw');
  if (audiCss) audiCss.disabled = (theme !== 'audi');

  const el = (theme === 'audi') ? fobAudi : fobBmw;
  el.classList.remove('hidden');
  setTimeout(()=> el.classList.add('show'), 10);

  updateIndicators();
}

function closeFob(){
  const el = (theme === 'audi') ? fobAudi : fobBmw;
  el.classList.remove('show');
  setTimeout(()=> {
    el.classList.add('hidden');
    document.body.classList.add('nui-hidden'); // volta a esconder tudo
  }, 350);

  fetch(`https://${GetParentResourceName()}/closeFob`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({})
  }).catch(()=>{});
}

function updateIndicators(){
  // bloqueio visual
  if(outOfRange) document.body.classList.add('oor');
  else document.body.classList.remove('oor');

  // BMW ring
  if (batteryCircleBmw){
    const r = 40;
    const circumference = 2 * Math.PI * r;
    batteryCircleBmw.style.strokeDasharray = `${circumference}`;
    const offset = circumference - (Math.max(0, Math.min(100, battery)) / 100) * circumference;
    batteryCircleBmw.style.strokeDashoffset = `${offset}`;

    // cor
    if (outOfRange){
      batteryCircleBmw.classList.add('out-of-range');
    } else {
      batteryCircleBmw.classList.remove('out-of-range');
      batteryCircleBmw.style.stroke = (battery <= 15) ? "#ff2a2a" : "#00aaff";
    }
  }

  // AUDI led
  if (audiLed){
    if(outOfRange) audiLed.classList.add('out-of-range');
    else audiLed.classList.remove('out-of-range');

    if(!outOfRange){
      if (battery <= 15){
        audiLed.style.background = "#ff2a2a";
        audiLed.style.boxShadow = "0 0 12px rgba(255,0,0,.75)";
      } else {
        audiLed.style.background = "#00aaff";
        audiLed.style.boxShadow = "0 0 12px rgba(0,150,255,.8)";
      }
    }
  }
}

function sendAction(action){
  if (battery <= 0) return;
  if (outOfRange) return;

  fetch(`https://${GetParentResourceName()}/fobAction`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ action })
  }).catch(()=>{});
}

/* CLICK handlers (funciona para os 2 layouts) */
document.addEventListener('click', (e) => {
  const btn = e.target.closest('[data-action]');
  if(!btn) return;

  playClick();
  sendAction(btn.dataset.action);
  closeFob();
});

document.addEventListener('keydown', (e) => {
  if (e.key === "Escape") closeFob();
});

/* Mensagens do client.lua */
window.addEventListener('message', (event) => {
  const data = event.data;
  if (!data || !data.action) return;

  switch(data.action){
    case 'openFob':
      // theme pode vir do lua: 'bmw'|'audi'
      setTheme(data.theme || 'bmw');
      openFob(data.battery ?? 100);
      break;

    case 'outOfRange':
      outOfRange = !!data.state;
      updateIndicators();
      break;

    case 'updateBattery':
      battery = Number(data.level ?? battery);
      updateIndicators();
      break;
  }
});