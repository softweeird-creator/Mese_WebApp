/* =====================================================================
   MESE · Capa de marca "bonita" (comportamiento)
   - Pone el confeti de fondo (anillos abiertos y astillas de la marca).
   - Lanza una lluvia de confeti al guardar un registro, terminar una visita,
     reactivar a alguien, importar un respaldo o entrar al sistema.
   - Decora la pantalla de inicio de sesión.
   No cambia datos ni lógica: solo decoración. Respeta "reducir movimiento".
   ===================================================================== */
(()=>{
 const C={az:'#263675',vb:'#4cb263',mg:'#e0218a',am:'#fbbe37',bl:'#ffffff'};
 const NS='http://www.w3.org/2000/svg';
 const quieto=matchMedia('(prefers-reduced-motion: reduce)');

 /* Anillo abierto: un círculo con un hueco, como en el logo */
 const anillo=(x,y,r,g,col,rot,hueco=18,op=1)=>`<circle cx="${x}" cy="${y}" r="${r}" fill="none" stroke="${col}" stroke-opacity="${op}" stroke-width="${g}" pathLength="100" stroke-dasharray="${100-hueco} ${hueco}" transform="rotate(${rot} ${x} ${y})"/>`;
 /* Astilla: cuadrilátero inclinado */
 const astilla=(x,y,w,h,col,rot,op=1)=>`<polygon points="0,${h*.35} ${w*.75},0 ${w},${h*.45} ${w*.05},${h}" fill="${col}" fill-opacity="${op}" transform="translate(${x} ${y}) rotate(${rot})"/>`;
 const svg=(cls,vb,inner)=>`<svg class="${cls}" xmlns="${NS}" viewBox="${vb}" aria-hidden="true" focusable="false">${inner}</svg>`;

 const abajo=svg('mx-ab','0 0 400 400',
  anillo(300,300,110,34,C.vb,-30)+anillo(120,250,28,9,C.mg,40)+anillo(210,130,20,7,C.am,150,20)+
  anillo(90,360,40,10,C.az,200,18,.7)+astilla(170,200,40,22,C.am,-25)+astilla(330,110,30,18,C.mg,60)+astilla(40,150,36,20,C.vb,-30)+astilla(250,40,26,14,C.az,20,.7));
 const arriba=svg('mx-ar','0 0 400 400',
  anillo(110,110,110,34,C.vb,150)+anillo(300,90,40,10,C.bl,30,20,.9)+anillo(80,300,22,7,C.am,250)+
  astilla(250,220,38,20,C.mg,-30)+astilla(330,250,28,16,C.am,15)+astilla(40,240,24,14,C.bl,-40,.8));
 /* Forma escalonada verde de la papelería oficial */
 const escalon=svg('mx-esc','0 0 720 300',`<path fill="${C.vb}" d="M640 0H720V300H0V290A35 35 0 0 1 35 255H425A35 35 0 0 0 460 220A35 35 0 0 1 495 185H605A35 35 0 0 0 640 150Z"/>`);

 const fondo=document.createElement('div');
 fondo.className='mx-fondo';fondo.setAttribute('aria-hidden','true');
 fondo.innerHTML=abajo+arriba+escalon;
 document.body.prepend(fondo);

 /* ---------- Lluvia de confeti ---------- */
 const lluvia=(n=70)=>{
  if(quieto.matches)return;
  const capa=document.createElement('div');capa.className='mx-lluvia';capa.setAttribute('aria-hidden','true');
  const cols=[C.vb,C.mg,C.am,C.az];const W=innerWidth,H=innerHeight;let fin=0;
  for(let i=0;i<n;i++){
   const p=document.createElement('i'),col=cols[i%4],tam=8+Math.random()*14;
   if(Math.random()<.45){p.className='mx-p r';const g=Math.max(2,tam*.22);p.style.cssText=`width:${tam}px;height:${tam}px;border-width:${g}px;border-color:${col}`}
   else{p.className='mx-p s';p.style.cssText=`width:${tam*1.4}px;height:${tam*.8}px;background:${col}`}
   p.style.left=(Math.random()*W)+'px';capa.appendChild(p);
   const dx=(Math.random()-.5)*240,giro=(Math.random()-.5)*900,dur=1600+Math.random()*1400,ret=Math.random()*350;
   fin=Math.max(fin,dur+ret);
   p.animate([{transform:'translate(0,0) rotate(0deg)',opacity:1},{transform:`translate(${dx*.6}px,${H*.55}px) rotate(${giro*.6}deg)`,opacity:1,offset:.6},{transform:`translate(${dx}px,${H+60}px) rotate(${giro}deg)`,opacity:0}],{duration:dur,delay:ret,easing:'cubic-bezier(.2,.6,.4,1)',fill:'both'});
  }
  document.body.appendChild(capa);setTimeout(()=>capa.remove(),fin+100);
 };
 window.meseConfeti=lluvia;

 /* Festejar los avisos de logro (el aviso verde de abajo, #ok) */
 const LOGRO=/registro agregado|visita guardada|participante reactivado|respaldo importado|usuario agregado|^hola,/i;
 const ok=document.getElementById('ok');
 if(ok)new MutationObserver(()=>{if(!ok.hidden&&LOGRO.test(ok.textContent))lluvia()}).observe(ok,{attributes:true,attributeFilter:['hidden'],childList:true,characterData:true,subtree:true});

 /* ---------- Pantalla de inicio de sesión ---------- */
 /* En el sistema con servidor, #login es una capa fija encima de todo: le ponemos su propio confeti. */
 const login=document.getElementById('login');
 if(login){
  const capa=document.createElement('div');capa.className='mx-fondo mx-fondo-login';capa.setAttribute('aria-hidden','true');
  capa.innerHTML=abajo+arriba+escalon;login.prepend(capa);
  const f=login.querySelector('form');f&&f.classList.add('mx-tarjeta');
 }
 /* Bienvenida con confeti una vez por sesión (solo en la demostración sin inicio de sesión;
    con servidor, el festejo sale con el aviso "Hola, ..." al entrar) */
 setTimeout(()=>{try{if(!login&&!sessionStorage.getItem('mx_hola')){sessionStorage.setItem('mx_hola','1');lluvia(60)}}catch(e){}},500);
})();
