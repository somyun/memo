/**
 * WebView2 ↔ AHK JSON 브리지
 */
const Bridge = (() => {
  const pending = new Map();
  let seq = 0;

  const isWebView = () => window.chrome?.webview;

  const send = (payload) => {
    if (isWebView()) {
      window.chrome.webview.postMessage(payload);
    } else {
      console.log('[AHK mock]', payload);
    }
  };

  const request = (method, params = {}) =>
    new Promise((resolve, reject) => {
      const id = `r${++seq}`;
      pending.set(id, { resolve, reject });
      send({ id, kind: 'request', method, params });
      setTimeout(() => {
        if (pending.has(id)) {
          pending.delete(id);
          reject(new Error(`timeout: ${method}`));
        }
      }, 8000);
    });

  const event = (method, params = {}) => send({ kind: 'event', method, params });

  const onMessage = (handler) => {
    if (!isWebView()) return;
    window.chrome.webview.addEventListener('message', (ev) => {
      const msg = ev.data;
      if (msg?.kind === 'response' && msg.id && pending.has(msg.id)) {
        const { resolve, reject } = pending.get(msg.id);
        pending.delete(msg.id);
        msg.ok ? resolve(msg.result) : reject(msg.result);
        return;
      }
      handler(msg);
    });
  };

  return { request, event, onMessage, isWebView };
})();
