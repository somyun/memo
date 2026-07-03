const { createApp, ref, computed, onMounted, onUnmounted, nextTick } = Vue;

const GITHUB_OWNER = 'somyun';
const GITHUB_REPO = 'memo';
const GITHUB_BRANCH = 'main';

const firebaseConfig = {
  apiKey: 'AIzaSyBdJN2qn4Gox8jpIm8ZfPxzeoIU0G_eA-o',
  authDomain: 'memo-3a7c8.firebaseapp.com',
  projectId: 'memo-3a7c8',
  storageBucket: 'memo-3a7c8.firebasestorage.app',
  messagingSenderId: '674466200117',
  appId: '1:674466200117:web:02cb1572cd0a2597ffcf7c',
};

let db = null;
let firebaseInitError = '';
let desktopHost = { machineKey: 'default', machineName: '', localInstallId: '' };
let githubToken = null;

function reportClientError(message, extra = {}) {
  try {
    Bridge.event('clientError', {
      message: String(message || 'unknown client error'),
      source: extra.source || '',
      line: extra.line || 0,
      column: extra.column || 0,
      stack: extra.stack || '',
      route: location.hash || '',
    });
  } catch {
    // 브리지 자체가 준비되지 않은 초기 오류는 콘솔에만 남긴다.
  }
}

window.addEventListener('error', (event) => {
  reportClientError(event.message, {
    source: event.filename,
    line: event.lineno,
    column: event.colno,
    stack: event.error?.stack || '',
  });
});

window.addEventListener('unhandledrejection', (event) => {
  const reason = event.reason;
  reportClientError(reason?.message || reason, {
    stack: reason?.stack || '',
  });
});

try {
  if (!window.firebase) {
    throw new Error('Firebase SDK를 로드하지 못했습니다.');
  }

  if (!firebase.apps.length) {
    firebase.initializeApp(firebaseConfig);
  }

  db = firebase.firestore();
} catch (error) {
  firebaseInitError = error?.message || String(error);
  reportClientError(firebaseInitError, { stack: error?.stack || '' });
  console.error(error);
}

const hash = decodeURIComponent(location.hash.replace(/^#/, '').trim());

function now() {
  return Date.now();
}

function requireDb() {
  if (!db) {
    throw new Error(firebaseInitError || 'Firestore를 사용할 수 없습니다.');
  }
  return db;
}

function errorText(error) {
  return error?.message || String(error) || '알 수 없는 오류';
}

function isBridgeTrue(value) {
  return value === true || value === 1;
}

function newMemoId() {
  return now().toString(36) + Math.random().toString(36).slice(2, 8);
}

function formatDate(ts) {
  if (!ts) return '';
  const d = new Date(ts);
  const p = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}.${p(d.getMonth() + 1)}.${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}`;
}

function normalizeLinkHref(url) {
  return /^https?:\/\//i.test(url) ? url : `https://${url}`;
}

function trimUrlPunctuation(url) {
  return String(url || '').replace(/[.,!?;:\)\]\}]+$/g, '');
}

function linkifyText(text) {
  const value = String(text || '');
  const regex = /(?:https?:\/\/|www\.)[^\s<>"']+/gi;
  const parts = [];
  let cursor = 0;

  for (const match of value.matchAll(regex)) {
    const linkedText = trimUrlPunctuation(match[0]);
    if (!linkedText) continue;

    const start = match.index;
    const end = start + linkedText.length;
    if (start > cursor) {
      parts.push({ text: value.slice(cursor, start), href: '' });
    }
    parts.push({ text: linkedText, href: normalizeLinkHref(linkedText) });
    cursor = end;
  }

  if (cursor < value.length) {
    parts.push({ text: value.slice(cursor), href: '' });
  }
  return parts;
}

function isImageFile(file) {
  return file?.type?.startsWith('image/') || /\.(png|jpe?g|gif|webp|bmp|svg)$/i.test(file?.name || '');
}

function fileNameFromUrl(url, fallback = 'attachment') {
  const clean = String(url || '').split(/[?#]/)[0];
  const last = clean.slice(clean.lastIndexOf('/') + 1);
  try {
    return decodeURIComponent(last) || fallback;
  } catch {
    return last || fallback;
  }
}

function safeZipName(name, fallback = 'attachment') {
  return String(name || fallback)
    .replace(/[\\/:*?"<>|\x00-\x1f]/g, '_')
    .replace(/^\.+$/, fallback)
    .slice(0, 160) || fallback;
}

function attachmentItems(images = [], files = []) {
  return [
    ...images.map((url, index) => ({
      kind: 'image',
      name: `이미지 ${index + 1}`,
      zipName: fileNameFromUrl(url, `image-${index + 1}.jpg`),
      url,
    })),
    ...files.map((file, index) => ({
      kind: 'file',
      name: file.name || fileNameFromUrl(file.url, `file-${index + 1}`),
      zipName: file.name || fileNameFromUrl(file.url, `file-${index + 1}`),
      url: file.url,
    })),
  ].filter((item) => item.url);
}

function blobToDataUrl(blob) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result);
    reader.onerror = (error) => reject(error);
    reader.readAsDataURL(blob);
  });
}

async function desktopConfirm(message, title = 'Memo Desktop') {
  if (Bridge.isWebView()) {
    try {
      const result = await Bridge.request('desktopConfirm', { message, title });
      return isBridgeTrue(result?.confirmed);
    } catch (error) {
      console.warn('desktopConfirm failed:', error);
    }
  }
  return confirm(message);
}

async function desktopMessage(message, title = 'Memo Desktop', icon = 'info') {
  if (Bridge.isWebView()) {
    try {
      await Bridge.request('desktopMessage', { message, title, icon });
      return;
    } catch (error) {
      console.warn('desktopMessage failed:', error);
    }
  }
  alert(message);
}

async function triggerDownload(blob, fileName) {
  if (Bridge.isWebView()) {
    const dataUrl = await blobToDataUrl(blob);
    return Bridge.request('saveDataUrl', {
      fileName,
      dataUrl,
      title: '첨부 압축파일 저장',
    });
  }

  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = fileName;
  document.body.appendChild(link);
  link.click();
  link.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
  return { saved: true };
}

let crcTable = null;

function getCrcTable() {
  if (crcTable) return crcTable;
  crcTable = new Uint32Array(256);
  for (let n = 0; n < 256; n += 1) {
    let c = n;
    for (let k = 0; k < 8; k += 1) {
      c = (c & 1) ? (0xedb88320 ^ (c >>> 1)) : (c >>> 1);
    }
    crcTable[n] = c >>> 0;
  }
  return crcTable;
}

function crc32(bytes) {
  const table = getCrcTable();
  let c = 0xffffffff;
  for (let i = 0; i < bytes.length; i += 1) {
    c = table[(c ^ bytes[i]) & 0xff] ^ (c >>> 8);
  }
  return (c ^ 0xffffffff) >>> 0;
}

function dosDateTime(date = new Date()) {
  const year = Math.max(1980, date.getFullYear());
  const time = (date.getHours() << 11) | (date.getMinutes() << 5) | Math.floor(date.getSeconds() / 2);
  const day = (date.getDate() || 1);
  const dosDate = ((year - 1980) << 9) | ((date.getMonth() + 1) << 5) | day;
  return { time, date: dosDate };
}

function makeZip(files) {
  const encoder = new TextEncoder();
  const localParts = [];
  const centralParts = [];
  const usedNames = new Map();
  let offset = 0;

  files.forEach((file, index) => {
    const baseName = safeZipName(file.name, `attachment-${index + 1}`);
    const seen = usedNames.get(baseName) || 0;
    usedNames.set(baseName, seen + 1);
    const name = seen ? baseName.replace(/(\.[^.]*)?$/, `-${seen + 1}$1`) : baseName;
    const nameBytes = encoder.encode(name);
    const data = file.data;
    const crc = crc32(data);
    const stamp = dosDateTime();

    const local = new Uint8Array(30 + nameBytes.length);
    const localView = new DataView(local.buffer);
    localView.setUint32(0, 0x04034b50, true);
    localView.setUint16(4, 20, true);
    localView.setUint16(6, 0x0800, true);
    localView.setUint16(8, 0, true);
    localView.setUint16(10, stamp.time, true);
    localView.setUint16(12, stamp.date, true);
    localView.setUint32(14, crc, true);
    localView.setUint32(18, data.length, true);
    localView.setUint32(22, data.length, true);
    localView.setUint16(26, nameBytes.length, true);
    local.set(nameBytes, 30);

    const central = new Uint8Array(46 + nameBytes.length);
    const centralView = new DataView(central.buffer);
    centralView.setUint32(0, 0x02014b50, true);
    centralView.setUint16(4, 20, true);
    centralView.setUint16(6, 20, true);
    centralView.setUint16(8, 0x0800, true);
    centralView.setUint16(10, 0, true);
    centralView.setUint16(12, stamp.time, true);
    centralView.setUint16(14, stamp.date, true);
    centralView.setUint32(16, crc, true);
    centralView.setUint32(20, data.length, true);
    centralView.setUint32(24, data.length, true);
    centralView.setUint16(28, nameBytes.length, true);
    centralView.setUint32(42, offset, true);
    central.set(nameBytes, 46);

    localParts.push(local, data);
    centralParts.push(central);
    offset += local.length + data.length;
  });

  const centralSize = centralParts.reduce((sum, part) => sum + part.length, 0);
  const end = new Uint8Array(22);
  const endView = new DataView(end.buffer);
  endView.setUint32(0, 0x06054b50, true);
  endView.setUint16(8, files.length, true);
  endView.setUint16(10, files.length, true);
  endView.setUint32(12, centralSize, true);
  endView.setUint32(16, offset, true);

  return new Blob([...localParts, ...centralParts, end], { type: 'application/zip' });
}

async function downloadAttachmentsZip(attachments, zipName, setProgress = () => {}) {
  if (attachments.length < 2) return;
  setProgress('첨부 압축 중...');

  const files = [];
  for (let i = 0; i < attachments.length; i += 1) {
    const attachment = attachments[i];
    setProgress(`첨부 다운로드 중... ${i + 1}/${attachments.length}`);
    const response = await fetch(attachment.url);
    if (!response.ok) {
      throw new Error(`${attachment.name} 다운로드 실패 (${response.status})`);
    }
    const data = new Uint8Array(await response.arrayBuffer());
    files.push({ name: attachment.zipName || attachment.name, data });
  }

  const result = await triggerDownload(makeZip(files), zipName);
  if (result?.saved === false) {
    setProgress('');
    return result;
  }
  setProgress(Bridge.isWebView() ? '압축파일 저장됨' : '압축파일 생성됨');
  return result;
}

function fileToBase64(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result);
    reader.onerror = (error) => reject(error);
    reader.readAsDataURL(file);
  });
}

async function compressImage(file, maxDimension = 1600, quality = 0.82) {
  if (file.size < 500 * 1024) return file;

  return new Promise((resolve) => {
    const img = new Image();
    const blobUrl = URL.createObjectURL(file);

    img.onload = () => {
      URL.revokeObjectURL(blobUrl);

      let { width, height } = img;
      if (width > maxDimension || height > maxDimension) {
        if (width > height) {
          height = Math.round(height * (maxDimension / width));
          width = maxDimension;
        } else {
          width = Math.round(width * (maxDimension / height));
          height = maxDimension;
        }
      }

      const canvas = document.createElement('canvas');
      canvas.width = width;
      canvas.height = height;
      canvas.getContext('2d').drawImage(img, 0, 0, width, height);
      canvas.toBlob((blob) => {
        if (!blob || blob.size >= file.size) {
          resolve(file);
          return;
        }
        const newName = file.name.replace(/\.\w+$/, '.jpg') || 'image.jpg';
        resolve(new File([blob], newName, { type: 'image/jpeg' }));
      }, 'image/jpeg', quality);
    };

    img.onerror = () => {
      URL.revokeObjectURL(blobUrl);
      resolve(file);
    };
    img.src = blobUrl;
  });
}

async function loadGithubToken() {
  if (githubToken) return githubToken;

  const docSnap = await requireDb().collection('config').doc('github').get();
  if (!docSnap.exists) throw new Error('GitHub 토큰 설정 없음');

  const data = docSnap.data() || {};
  if (!data.token) throw new Error('토큰 없음');

  githubToken = data.token;
  return githubToken;
}

async function uploadContentToGithub(fileName, base64Content, message) {
  const token = await loadGithubToken();
  const response = await fetch(
    `https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPO}/contents/${fileName}`,
    {
      method: 'PUT',
      headers: {
        Authorization: `token ${token}`,
        Accept: 'application/vnd.github+json',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        message,
        content: base64Content,
        branch: GITHUB_BRANCH,
      }),
    },
  );

  if (!response.ok) {
    throw new Error(await response.text());
  }
}

async function uploadImageAttachment(file) {
  const compressed = await compressImage(file);
  const base64 = await fileToBase64(compressed);
  const pureBase64 = base64.split(',')[1];
  const ext = (compressed.type.split('/')[1] || 'png').replace('jpeg', 'jpg');
  const fileName = `uploads/${Date.now()}_${Math.random().toString(36).slice(2)}.${ext}`;

  await uploadContentToGithub(fileName, pureBase64, `Upload image ${fileName}`);
  return `https://cdn.jsdelivr.net/gh/${GITHUB_OWNER}/${GITHUB_REPO}@${GITHUB_BRANCH}/${fileName}`;
}

async function uploadFileAttachment(file) {
  const base64 = await fileToBase64(file);
  const pureBase64 = base64.split(',')[1];
  const safeName = file.name.replace(/[^a-zA-Z0-9가-힣._-]/g, '_') || 'attachment';
  const fileName = `uploads/${Date.now()}_${safeName}`;

  await uploadContentToGithub(fileName, pureBase64, `Upload file ${fileName}`);
  return {
    name: file.name || safeName,
    url: `https://raw.githubusercontent.com/${GITHUB_OWNER}/${GITHUB_REPO}/${GITHUB_BRANCH}/${fileName}`,
  };
}

function extractGithubPath(url) {
  let match = String(url || '').match(/\/gh\/[^/]+\/[^@]+@[^/]+\/(.+)$/);
  if (match) return match[1];
  match = String(url || '').match(/raw\.githubusercontent\.com\/[^/]+\/[^/]+\/[^/]+\/(.+)$/);
  return match ? match[1] : null;
}

async function deleteGithubFile(url) {
  const filePath = extractGithubPath(url);
  if (!filePath) return;

  const token = await loadGithubToken();
  const apiUrl = `https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPO}/contents/${filePath}?ref=${GITHUB_BRANCH}`;
  const infoRes = await fetch(apiUrl, {
    headers: {
      Authorization: `token ${token}`,
      Accept: 'application/vnd.github+json',
    },
  });

  if (!infoRes.ok) throw new Error(`SHA 조회 실패 (${infoRes.status})`);
  const info = await infoRes.json();

  const delRes = await fetch(
    `https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPO}/contents/${filePath}`,
    {
      method: 'DELETE',
      headers: {
        Authorization: `token ${token}`,
        Accept: 'application/vnd.github+json',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        message: `Delete ${filePath}`,
        sha: info.sha,
        branch: GITHUB_BRANCH,
      }),
    },
  );

  if (!delRes.ok) throw new Error(`삭제 실패 (${delRes.status})`);
}

function defaultBounds() {
  return { x: 120, y: 120, w: 300, h: 320 };
}

function normalizeMachineKey(value, fallback = 'default') {
  return String(value || '').replace(/[^A-Za-z0-9_-]/g, '_').toLowerCase() || fallback;
}

function applyHostConfig(params = {}) {
  const host = params.host || params;
  const localInstallId = normalizeMachineKey(host.localInstallId || '', '');
  desktopHost = {
    machineKey: localInstallId || normalizeMachineKey(host.machineKey || desktopHost.machineKey),
    machineName: String(host.machineName || desktopHost.machineName || ''),
    localInstallId: localInstallId || desktopHost.localInstallId || '',
  };
}

function boundsForCurrentMachine(data) {
  const byMachine = data.desktopBoundsByMachine || {};
  const machineBounds = byMachine[desktopHost.machineKey];
  return machineBounds || data.desktopBounds || null;
}

function normalizeMemo(doc) {
  const data = doc.data() || {};
  return {
    id: doc.id,
    text: data.text || '',
    images: Array.isArray(data.images) ? data.images : [],
    files: Array.isArray(data.files) ? data.files : [],
    pinned: !!data.pinned,
    pinnedAt: data.pinnedAt || 0,
    desktopPinned: data.desktopPinned === true,
    desktopPinnedAt: data.desktopPinnedAt || 0,
    created: data.created || now(),
    updated: data.updated || data.created || now(),
    desktopVisible: data.desktopVisible === true,
    desktopBounds: data.desktopBounds || null,
    currentDesktopBounds: boundsForCurrentMachine(data),
    desktopBoundsByMachine: data.desktopBoundsByMachine && typeof data.desktopBoundsByMachine === 'object'
      ? data.desktopBoundsByMachine
      : {},
    desktopUpdated: data.desktopUpdated || 0,
  };
}

function baseMemo(id, text = '') {
  const ts = now();
  return {
    id,
    text,
    images: [],
    files: [],
    pinned: false,
    desktopPinned: false,
    desktopPinnedAt: 0,
    created: ts,
    updated: ts,
    desktopVisible: true,
    desktopBounds: defaultBounds(),
    desktopBoundsByMachine: {},
    desktopUpdated: ts,
  };
}

async function setDesktopVisible(memoId, visible) {
  await requireDb().collection('memos').doc(memoId).set({
    desktopVisible: visible,
    desktopUpdated: now(),
  }, { merge: true });
}

async function hideAllVisibleMemos() {
  const store = requireDb();
  const snapshot = await store.collection('memos').where('desktopVisible', '==', true).get();
  const batch = store.batch();
  const ts = now();

  snapshot.docs.forEach((doc) => {
    batch.set(doc.ref, {
      desktopVisible: false,
      desktopUpdated: ts,
    }, { merge: true });
  });

  await batch.commit();
}

function mountHost() {
  createApp({
    setup() {
      let unsub = null;
      let lastSnapshot = null;
      let listenerStarted = false;
      let hostConfigReceived = false;

      const syncVisible = (snapshot) => {
        lastSnapshot = snapshot;
        const items = snapshot.docs
          .map(normalizeMemo)
          .map((memo) => ({
            id: memo.id,
            bounds: memo.currentDesktopBounds,
            pinned: memo.desktopPinned,
            pinnedAt: memo.desktopPinnedAt || 0,
          }));
        Bridge.event('syncVisibleMemos', { items });
      };

      const hideAll = async () => {
        try {
          await hideAllVisibleMemos();
          Bridge.event('syncVisibleMemos', { items: [] });
        } catch (error) {
          console.error(error);
        }
      };

      const startVisibleListener = () => {
        if (listenerStarted || !db) return;
        listenerStarted = true;
        unsub = db.collection('memos').where('desktopVisible', '==', true).onSnapshot(syncVisible, (error) => {
          console.error(error);
        });
      };

      onMounted(() => {
        Bridge.onMessage((msg) => {
          if (msg?.method === 'hostConfig' && msg.params) {
            applyHostConfig(msg.params);
            hostConfigReceived = true;
            if (listenerStarted && lastSnapshot) {
              syncVisible(lastSnapshot);
            } else {
              startVisibleListener();
            }
          }
          if (msg?.method === 'hideAllVisible') {
            hideAll();
          }
        });

        if (!db) {
          Bridge.event('ready', { mode: 'host', error: firebaseInitError });
          return;
        }

        Bridge.event('ready', { mode: 'host' });
        if (!Bridge.isWebView()) {
          startVisibleListener();
        } else {
          setTimeout(() => {
            if (!hostConfigReceived) startVisibleListener();
          }, 1500);
        }
      });

      onUnmounted(() => {
        if (unsub) unsub();
      });

      return {};
    },
    template: '<div class="host-shell"></div>',
  }).mount('#app');
}

function mountManager() {
  createApp({
    setup() {
      const memos = ref([]);
      const query = ref('');
      const status = ref(firebaseInitError ? `동기화 오류: ${firebaseInitError}` : '동기화 중...');
      const statusError = ref(!!firebaseInitError);
      const loaded = ref(false);
      const firestoreState = ref(firebaseInitError ? 'error' : 'connecting');
      let unsub = null;

      const filteredMemos = computed(() => {
        const q = query.value.trim().toLowerCase();
        const list = [...memos.value].sort((a, b) => b.updated - a.updated);
        if (!q) return list;
        return list.filter((memo) => memo.text.toLowerCase().includes(q));
      });

      const diagnosticItems = computed(() => [
        { label: 'WebView', state: 'ready', text: 'HTML/JS 준비됨' },
        { label: 'Bridge', state: Bridge.isWebView() ? 'ready' : 'warn', text: Bridge.isWebView() ? 'AHK 연결됨' : '브라우저 미리보기' },
        {
          label: 'Firestore',
          state: firestoreState.value,
          text: firestoreState.value === 'ready' ? '동기화 연결됨' : firestoreState.value === 'error' ? '오류' : '연결 중',
        },
      ]);

      const setError = (prefix, error) => {
        status.value = `${prefix}: ${errorText(error)}`;
        statusError.value = true;
        firestoreState.value = 'error';
      };

      const createMemo = async () => {
        try {
          const id = newMemoId();
          await requireDb().collection('memos').doc(id).set(baseMemo(id));
          status.value = '새 메모 표시 요청됨';
          statusError.value = false;
        } catch (error) {
          setError('새 메모 생성 실패', error);
        }
      };

      const setMemoVisible = async (memo, visible) => {
        try {
          await setDesktopVisible(memo.id, visible);
          status.value = visible ? '메모 표시 요청됨' : '메모 숨김 요청됨';
          statusError.value = false;
        } catch (error) {
          setError(visible ? '표시 실패' : '숨김 실패', error);
        }
      };

      const toggleMemo = (memo) => {
        setMemoVisible(memo, !memo.desktopVisible);
      };

      const showMemo = (memo) => {
        if (!memo.desktopVisible) {
          setMemoVisible(memo, true);
        }
      };

      const deleteMemo = async (memo) => {
        if (!(await desktopConfirm('이 메모를 삭제할까요?', '메모 삭제'))) return;
        try {
          await requireDb().collection('memos').doc(memo.id).delete();
        } catch (error) {
          setError('삭제 실패', error);
        }
      };

      onMounted(() => {
        if (!db) {
          loaded.value = true;
          Bridge.event('ready', { mode: 'manager', error: firebaseInitError });
          return;
        }

        unsub = db.collection('memos').onSnapshot((snapshot) => {
          memos.value = snapshot.docs.map(normalizeMemo);
          status.value = `${memos.value.length}개 메모`;
          statusError.value = false;
          firestoreState.value = 'ready';
          loaded.value = true;
        }, (error) => {
          setError('동기화 오류', error);
          loaded.value = true;
        });
        Bridge.event('ready', { mode: 'manager' });
      });

      onUnmounted(() => {
        if (unsub) unsub();
      });

      return {
        query,
        status,
        statusError,
        loaded,
        diagnosticItems,
        filteredMemos,
        formatDate,
        linkifyText,
        createMemo,
        toggleMemo,
        showMemo,
        deleteMemo,
      };
    },
    template: `
      <main class="manager-shell">
        <header class="manager-header">
          <div>
            <h1>Memo Desktop</h1>
            <p :class="{ 'sync-error': statusError }">{{ status }}</p>
          </div>
          <button class="primary-button" type="button" @click="createMemo">새 메모</button>
        </header>

        <section class="manager-tools">
          <input v-model="query" class="search-input" type="search" placeholder="메모 검색">
        </section>

        <section class="diagnostic-bar" aria-label="WebView 상태">
          <span
            v-for="item in diagnosticItems"
            :key="item.label"
            class="diag-pill"
            :class="item.state"
          >
            {{ item.label }}: {{ item.text }}
          </span>
        </section>

        <p v-if="statusError" class="status-banner">{{ status }}</p>

        <section class="memo-list">
          <article v-for="memo in filteredMemos" :key="memo.id" class="memo-row" @dblclick="showMemo(memo)">
            <div class="memo-row-main">
              <button
                class="visible-pill"
                :class="{ off: !memo.desktopVisible }"
                type="button"
                :title="memo.desktopVisible ? '숨김으로 전환' : '표시로 전환'"
                :aria-pressed="memo.desktopVisible ? 'true' : 'false'"
                @click.stop="toggleMemo(memo)"
              >
                {{ memo.desktopVisible ? '표시중' : '숨김' }}
              </button>
              <p>
                <template v-for="(part, index) in linkifyText(memo.text.trim() || '(빈 메모)')" :key="index">
                  <a
                    v-if="part.href"
                    class="memo-link"
                    :href="part.href"
                    target="_blank"
                    rel="noopener"
                    @click.stop
                  >{{ part.text }}</a>
                  <span v-else>{{ part.text }}</span>
                </template>
              </p>
              <time>{{ formatDate(memo.updated) }}</time>
            </div>
            <div class="memo-row-actions">
              <button class="danger-button" type="button" @click="deleteMemo(memo)">삭제</button>
            </div>
          </article>
          <p v-if="loaded && filteredMemos.length === 0" class="empty-state">
            {{ query.trim() ? '검색 결과가 없습니다.' : '아직 메모가 없습니다. 새 메모를 눌러 시작하세요.' }}
          </p>
        </section>
      </main>
    `,
  }).mount('#app');
}

function mountMemo(memoId, createIfMissing = false) {
  createApp({
    setup() {
      const text = ref('');
      const images = ref([]);
      const files = ref([]);
      const editing = ref(createIfMissing);
      const pinned = ref(false);
      const updated = ref(now());
      const status = ref(firebaseInitError ? `동기화 오류: ${firebaseInitError}` : '동기화 중...');
      const statusError = ref(!!firebaseInitError);
      const uploadCount = ref(0);
      const lightboxUrl = ref('');
      let unsub = null;
      let textTimer = null;
      let boundsTimer = null;
      let localSaveUntil = 0;
      let lastLocalUpdated = 0;
      let lastBounds = null;
      let initialized = false;
      let mayCreateMissing = createIfMissing;

      const footerText = computed(() => status.value || formatDate(updated.value));
      const textParts = computed(() => linkifyText(text.value));
      const attachments = computed(() => attachmentItems(images.value, files.value));
      const canDownloadAll = computed(() => attachments.value.length >= 2);
      const isUploading = computed(() => uploadCount.value > 0);
      const memoRef = db ? db.collection('memos').doc(memoId) : null;

      const startEditing = () => {
        editing.value = true;
        nextTick(() => {
          const editor = document.querySelector('.memo-text-editor');
          if (editor) editor.focus();
        });
      };

      const stopEditing = () => {
        editing.value = false;
      };

      const markLocalSave = (duration = 5000) => {
        localSaveUntil = now() + duration;
      };

      const setError = (prefix, error) => {
        status.value = `${prefix}: ${errorText(error)}`;
        statusError.value = true;
      };

      const setStatus = (message, isError = false) => {
        status.value = message;
        statusError.value = isError;
      };

      const saveText = async () => {
        if (!memoRef) {
          setError('저장 실패', new Error(firebaseInitError || 'Firestore를 사용할 수 없습니다.'));
          return;
        }

        markLocalSave();
        const ts = now();
        lastLocalUpdated = ts;
        updated.value = ts;
        status.value = '저장 중...';
        statusError.value = false;
        try {
          await memoRef.set({
            id: memoId,
            text: text.value,
            updated: ts,
            desktopVisible: true,
            desktopUpdated: ts,
          }, { merge: true });
          status.value = '저장됨';
          setTimeout(() => {
            if (status.value === '저장됨') status.value = '';
          }, 1200);
        } catch (error) {
          setError('저장 실패', error);
          console.error(error);
        }
      };

      const togglePinned = async () => {
        if (!memoRef) {
          setError('고정 실패', new Error(firebaseInitError || 'Firestore를 사용할 수 없습니다.'));
          return;
        }

        const nextPinned = !pinned.value;
        const ts = now();
        lastLocalUpdated = ts;
        pinned.value = nextPinned;
        status.value = nextPinned ? '상단 고정됨' : '고정 해제됨';
        statusError.value = false;

        try {
          await memoRef.set({
            desktopPinned: nextPinned,
            desktopPinnedAt: nextPinned ? ts : 0,
            updated: ts,
            desktopUpdated: ts,
          }, { merge: true });
          setTimeout(() => {
            if (status.value === '상단 고정됨' || status.value === '고정 해제됨') status.value = '';
          }, 1200);
        } catch (error) {
          pinned.value = !nextPinned;
          setError('고정 실패', error);
          console.error(error);
        }
      };

      const scheduleTextSave = () => {
        clearTimeout(textTimer);
        status.value = '저장 중...';
        statusError.value = false;
        textTimer = setTimeout(saveText, 1000);
      };

      const saveAttachments = async () => {
        if (!memoRef) {
          setError('첨부 저장 실패', new Error(firebaseInitError || 'Firestore를 사용할 수 없습니다.'));
          return false;
        }

        markLocalSave();
        const ts = now();
        lastLocalUpdated = ts;
        updated.value = ts;
        setStatus('첨부 저장 중...');

        let saved = false;
        try {
          await memoRef.set({
            id: memoId,
            images: [...images.value],
            files: files.value.map((file) => ({
              name: file?.name || fileNameFromUrl(file?.url, 'attachment'),
              url: file?.url || '',
            })).filter((file) => file.url),
            updated: ts,
            desktopVisible: true,
            desktopUpdated: ts,
          }, { merge: true });
          saved = true;
          setStatus('첨부 저장됨');
          setTimeout(() => {
            if (status.value === '첨부 저장됨') status.value = '';
          }, 1200);
        } catch (error) {
          setError('첨부 저장 실패', error);
          lastLocalUpdated = 0;
          console.error(error);
        }
        return saved;
      };

      const attachFile = async (file) => {
        if (!file) return;
        if (!memoRef) {
          setError('첨부 실패', new Error(firebaseInitError || 'Firestore를 사용할 수 없습니다.'));
          return;
        }

        uploadCount.value += 1;
        setStatus(isImageFile(file) ? '이미지 업로드 중...' : '파일 업로드 중...');

        try {
          if (isImageFile(file)) {
            const url = await uploadImageAttachment(file);
            images.value = [...images.value, url];
          } else {
            const fileObj = await uploadFileAttachment(file);
            files.value = [...files.value, fileObj];
          }
          await saveAttachments();
        } catch (error) {
          setError('첨부 실패', error);
          console.error(error);
        } finally {
          uploadCount.value = Math.max(0, uploadCount.value - 1);
        }
      };

      const pasteFiles = async (event) => {
        const clipboardFiles = Array.from(event.clipboardData?.files || []);
        const itemFiles = Array.from(event.clipboardData?.items || [])
          .filter((item) => item.kind === 'file')
          .map((item) => item.getAsFile())
          .filter(Boolean);
        const pastedFiles = clipboardFiles.length ? clipboardFiles : itemFiles;
        if (!pastedFiles.length) return;

        event.preventDefault();
        for (const file of pastedFiles) {
          await attachFile(file);
        }
      };

      const removeAttachment = async (attachment) => {
        const target = attachment.kind === 'image' ? '이미지' : `"${attachment.name}" 첨부`;
        if (!(await desktopConfirm(`${target}를 삭제할까요?\nGitHub에 업로드된 파일도 함께 삭제됩니다.`, '첨부 삭제'))) return;

        const previousImages = [...images.value];
        const previousFiles = files.value.map((file) => ({ ...file }));

        if (attachment.kind === 'image') {
          images.value = images.value.filter((url) => url !== attachment.url);
        } else {
          files.value = files.value.filter((file) => file.url !== attachment.url);
        }

        const saved = await saveAttachments();
        if (!saved) {
          images.value = previousImages;
          files.value = previousFiles;
          return;
        }

        deleteGithubFile(attachment.url).catch((error) => console.warn('GitHub 첨부 삭제 실패:', error));
      };

      const openAttachment = (event, attachment) => {
        if (attachment.kind !== 'image') return;
        event.preventDefault();
        event.stopPropagation();
        lightboxUrl.value = attachment.url;
      };

      const closeLightbox = () => {
        lightboxUrl.value = '';
      };

      const downloadAllAttachments = async () => {
        try {
          const result = await downloadAttachmentsZip(
            attachments.value,
            `memo-${memoId}-attachments.zip`,
            (message) => setStatus(message),
          );
          if (result?.saved && Bridge.isWebView()) {
            await desktopMessage(
              result.path ? `압축파일을 저장했습니다.\n${result.path}` : '압축파일을 저장했습니다.',
              '다운로드 완료',
            );
          }
          setTimeout(() => {
            if (status.value === '압축파일 생성됨' || status.value === '압축파일 저장됨') status.value = '';
          }, 1600);
        } catch (error) {
          setError('압축 다운로드 실패', error);
          if (Bridge.isWebView()) {
            await desktopMessage(`압축 다운로드 실패:\n${errorText(error)}`, '다운로드 실패', 'error');
          }
          console.error(error);
        }
      };

      const saveBounds = async () => {
        if (!lastBounds) return;
        try {
          if (memoRef) {
            const key = normalizeMachineKey(desktopHost.machineKey);
            const ts = now();
            await memoRef.set({
              desktopBounds: lastBounds,
              [`desktopBoundsByMachine.${key}`]: lastBounds,
              [`desktopBoundsHostMeta.${key}`]: {
                machineName: desktopHost.machineName,
                localInstallId: desktopHost.localInstallId || key,
                updated: ts,
              },
              desktopUpdated: ts,
            }, { merge: true });
          }
          Bridge.event('persistBounds', lastBounds);
        } catch (error) {
          console.error(error);
        }
      };

      const scheduleBoundsSave = (bounds) => {
        lastBounds = bounds;
        clearTimeout(boundsTimer);
        boundsTimer = setTimeout(saveBounds, 500);
      };

      const hideMemo = async () => {
        try {
          if (memoRef) {
            await setDesktopVisible(memoId, false);
          }
        } catch (error) {
          console.error(error);
        } finally {
          Bridge.event('closeWindow');
        }
      };

      const deleteMemo = async () => {
        if (!(await desktopConfirm('이 메모를 삭제할까요?', '메모 삭제'))) return;
        try {
          if (memoRef) {
            await memoRef.delete();
          }
        } catch (error) {
          setError('삭제 실패', error);
          console.error(error);
          return;
        }
        Bridge.event('closeWindow');
      };

      const onTitleMouseDown = (event) => {
        if (event.button !== 0 || event.target.closest('button')) return;
        Bridge.event('dragWindow');
      };

      onMounted(() => {
        Bridge.onMessage((msg) => {
          if (msg?.method === 'hostConfig' && msg.params) {
            applyHostConfig(msg.params);
          }
          if (msg?.method === 'windowBounds' && msg.params) {
            scheduleBoundsSave(msg.params);
          }
        });

        if (!memoRef) {
          initialized = true;
          Bridge.event('ready', { mode: 'memo', memoId, error: firebaseInitError });
          return;
        }

        unsub = memoRef.onSnapshot((snap) => {
          if (!snap.exists) {
            initialized = true;

            if (mayCreateMissing) {
              mayCreateMissing = false;
              markLocalSave();
              memoRef.set(baseMemo(memoId), { merge: true }).catch((error) => {
                setError('새 메모 생성 실패', error);
              });
              return;
            }

            status.value = '삭제된 메모';
            setTimeout(() => Bridge.event('closeWindow'), 500);
            return;
          }

          initialized = true;
          const data = snap.data() || {};
          const localWriteActive = now() < localSaveUntil;
          const staleLocalWriteSnapshot = lastLocalUpdated
            && (data.updated || 0) < lastLocalUpdated
            && now() < lastLocalUpdated + 10000;
          if (localWriteActive || staleLocalWriteSnapshot) return;

          text.value = data.text || '';
          images.value = Array.isArray(data.images) ? data.images : [];
          files.value = Array.isArray(data.files) ? data.files : [];
          pinned.value = data.desktopPinned === true;
          updated.value = data.updated || data.created || now();
          status.value = '';
          statusError.value = false;
        }, (error) => {
          setError('동기화 오류', error);
          console.error(error);
        });

        Bridge.event('ready', { mode: 'memo', memoId });
      });

      onUnmounted(() => {
        if (unsub) unsub();
        clearTimeout(textTimer);
        clearTimeout(boundsTimer);
      });

      return {
        text,
        attachments,
        canDownloadAll,
        isUploading,
        editing,
        textParts,
        pinned,
        footerText,
        statusError,
        lightboxUrl,
        startEditing,
        stopEditing,
        scheduleTextSave,
        pasteFiles,
        removeAttachment,
        openAttachment,
        closeLightbox,
        downloadAllAttachments,
        togglePinned,
        hideMemo,
        deleteMemo,
        onTitleMouseDown,
      };
    },
    template: `
      <div class="memo-shell">
        <div class="titlebar" @mousedown="onTitleMouseDown">
          <span class="status" :class="{ 'sync-error': statusError }">{{ footerText }}</span>
          <button
            class="icon-button pin-button"
            :class="{ active: pinned }"
            type="button"
            :title="pinned ? '상단 고정 해제' : '상단 고정'"
            :aria-pressed="pinned ? 'true' : 'false'"
            @click="togglePinned"
          >📌</button>
          <button class="icon-button close-button" type="button" title="숨김" aria-label="숨김" @click="hideMemo">×</button>
        </div>
        <div class="memo-body">
          <div
            v-if="!editing"
            class="memo-text memo-text-rendered"
            :class="{ empty: !text }"
            tabindex="0"
            @click="startEditing"
            @keydown.enter.prevent="startEditing"
            @keydown.f2.prevent="startEditing"
            @paste="pasteFiles"
          >
            <template v-if="text">
              <template v-for="(part, index) in textParts" :key="index">
                <a
                  v-if="part.href"
                  class="memo-link"
                  :href="part.href"
                  target="_blank"
                  rel="noopener"
                  @click.stop
                >{{ part.text }}</a>
                <span v-else>{{ part.text }}</span>
              </template>
            </template>
            <span v-else class="memo-placeholder">메모를 입력하세요</span>
          </div>
          <textarea
            v-show="editing"
            class="memo-text memo-text-editor"
            v-model="text"
            @input="scheduleTextSave"
            @paste="pasteFiles"
            @blur="stopEditing"
            placeholder="메모를 입력하세요"
            spellcheck="false"
          ></textarea>
        </div>
        <div class="memo-footer">
          <div
            v-if="attachments.length || isUploading"
            class="memo-attachments"
            :class="{ 'has-zip': canDownloadAll }"
            aria-label="첨부 파일"
          >
            <button
              v-if="canDownloadAll"
              class="zip-button"
              type="button"
              title="첨부 전체 압축 다운로드"
              @click="downloadAllAttachments"
            ><span>전체</span><span>다운</span></button>
            <div class="attachment-list">
              <div v-if="isUploading" class="attachment-progress">첨부 업로드 중...</div>
              <div
                v-for="attachment in attachments"
                :key="attachment.kind + ':' + attachment.url"
                class="attachment-row"
              >
                <a
                  class="attachment-link"
                  :href="attachment.url"
                  target="_blank"
                  rel="noopener"
                  :download="attachment.kind === 'file' ? attachment.name : null"
                  :title="attachment.kind === 'image' ? '이미지 열기' : attachment.name"
                  @click="openAttachment($event, attachment)"
                >{{ attachment.name }}</a>
                <button
                  class="attachment-remove"
                  type="button"
                  title="첨부 제거"
                  aria-label="첨부 제거"
                  @click="removeAttachment(attachment)"
                >×</button>
              </div>
            </div>
          </div>
          <button class="trash-button" type="button" title="삭제" aria-label="삭제" @click="deleteMemo">
            <img class="trash-icon" src="./assets/trash-can.png" alt="" aria-hidden="true">
          </button>
        </div>
        <div v-if="lightboxUrl" class="memo-lightbox" @click="closeLightbox">
          <img :src="lightboxUrl" alt="첨부 이미지">
        </div>
      </div>
    `,
  }).mount('#app');
}

if (hash === 'host') {
  mountHost();
} else if (hash === 'manager' || hash === '') {
  mountManager();
} else if (hash.startsWith('new:')) {
  mountMemo(hash.slice(4) || newMemoId(), true);
} else {
  mountMemo(hash, false);
}
