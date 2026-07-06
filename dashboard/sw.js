// claude-rc dashboard service worker.
// 目的は「ホーム画面に追加してアプリ化」できること。状態は常に新しくしたいので
// API はキャッシュせず素通し、シェル(HTML/アイコン)だけ軽くキャッシュする。
const SHELL = ['/', '/index.html', '/icon.svg', '/manifest.webmanifest'];
const CACHE = 'claude-rc-shell-v1';

self.addEventListener('install', e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(SHELL)).catch(() => {}));
  self.skipWaiting();
});
self.addEventListener('activate', e => {
  e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== CACHE).map(k => caches.delete(k)))));
  self.clients.claim();
});
self.addEventListener('fetch', e => {
  const url = new URL(e.request.url);
  if (url.pathname.startsWith('/api/')) return;            // API は常にネットワーク
  e.respondWith(
    fetch(e.request).then(r => {
      if (e.request.method === 'GET' && r.ok) {
        const cp = r.clone(); caches.open(CACHE).then(c => c.put(e.request, cp)).catch(() => {});
      }
      return r;
    }).catch(() => caches.match(e.request).then(r => r || caches.match('/')))
  );
});
