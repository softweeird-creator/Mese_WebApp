/* MESE · service worker: permite abrir la app y capturar visitas sin internet.
   Cambie el número de versión cada vez que publique cambios en index.html. */
const C='mese-v3';
const ARCHIVOS=['./','./index.html','./manifest.webmanifest','./icon-192.png','./icon-512.png','./logo.png'];
self.addEventListener('install',e=>e.waitUntil(caches.open(C).then(c=>c.addAll(ARCHIVOS)).then(()=>self.skipWaiting())));
self.addEventListener('activate',e=>e.waitUntil(caches.keys().then(ks=>Promise.all(ks.filter(k=>k!==C).map(k=>caches.delete(k)))).then(()=>self.clients.claim())));
const guardar=(req,res)=>{if(res&&res.ok){const cp=res.clone();caches.open(C).then(c=>c.put(req,cp))}return res};
/* Red primero (para recibir actualizaciones); si no hay señal o tarda más de 4 s, usa la copia guardada */
const conTiempo=req=>new Promise((ok,ko)=>{const t=setTimeout(()=>ko(new Error('lento')),4000);fetch(req).then(r=>{clearTimeout(t);ok(r)},e=>{clearTimeout(t);ko(e)})});
self.addEventListener('fetch',e=>{const req=e.request;if(req.method!=='GET')return;const u=new URL(req.url);
  if(u.origin===location.origin){
    e.respondWith(conTiempo(req).then(r=>guardar(req,r)).catch(()=>caches.match(req,{ignoreSearch:true}).then(m=>m||(req.mode==='navigate'?caches.match('./index.html'):Response.error()))));
    if(req.mode==='navigate')e.waitUntil(fetch(req).then(r=>guardar(req,r)).catch(()=>{}));
  }else if(/fonts\.(googleapis|gstatic)\.com$/.test(u.hostname)){
    e.respondWith(caches.match(req).then(m=>m||fetch(req).then(r=>guardar(req,r))));
  }});
