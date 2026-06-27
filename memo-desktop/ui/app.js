const { createApp, ref, computed, onMounted, onUnmounted } = Vue;

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

function newMemoId() {
  return now().toString(36) + Math.random().toString(36).slice(2, 8);
}

function formatDate(ts) {
  if (!ts) return '';
  const d = new Date(ts);
  const p = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}.${p(d.getMonth() + 1)}.${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}`;
}

function defaultBounds() {
  return { x: 120, y: 120, w: 300, h: 320 };
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

      const syncVisible = (snapshot) => {
        const items = snapshot.docs
          .map(normalizeMemo)
          .filter((memo) => memo.desktopVisible)
          .map((memo) => ({
            id: memo.id,
            bounds: memo.desktopBounds || null,
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

      onMounted(() => {
        Bridge.onMessage((msg) => {
          if (msg?.method === 'hideAllVisible') {
            hideAll();
          }
        });

        if (!db) {
          Bridge.event('ready', { mode: 'host', error: firebaseInitError });
          return;
        }

        unsub = db.collection('memos').onSnapshot(syncVisible, (error) => {
          console.error(error);
        });
        Bridge.event('ready', { mode: 'host' });
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

      const toggleMemo = async (memo, event) => {
        const visible = event.target.checked;
        try {
          await setDesktopVisible(memo.id, visible);
          status.value = visible ? '메모 표시 요청됨' : '메모 숨김 요청됨';
          statusError.value = false;
        } catch (error) {
          event.target.checked = !visible;
          setError(visible ? '표시 실패' : '숨김 실패', error);
        }
      };

      const deleteMemo = async (memo) => {
        if (!confirm('이 메모를 삭제할까요?')) return;
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
        createMemo,
        toggleMemo,
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
          <article v-for="memo in filteredMemos" :key="memo.id" class="memo-row">
            <div class="memo-row-main">
              <span class="visible-pill" :class="{ off: !memo.desktopVisible }">
                {{ memo.desktopVisible ? '표시중' : '숨김' }}
              </span>
              <p>{{ memo.text.trim() || '(빈 메모)' }}</p>
              <time>{{ formatDate(memo.updated) }}</time>
            </div>
            <div class="memo-row-actions">
              <label class="toggle-switch" :title="memo.desktopVisible ? '숨김으로 전환' : '표시로 전환'">
                <input
                  type="checkbox"
                  :checked="memo.desktopVisible"
                  @change="toggleMemo(memo, $event)"
                >
                <span class="toggle-track">
                  <span class="toggle-thumb"></span>
                </span>
                <span class="toggle-label">{{ memo.desktopVisible ? '표시' : '숨김' }}</span>
              </label>
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
      const pinned = ref(false);
      const updated = ref(now());
      const status = ref(firebaseInitError ? `동기화 오류: ${firebaseInitError}` : '동기화 중...');
      const statusError = ref(!!firebaseInitError);
      let unsub = null;
      let textTimer = null;
      let boundsTimer = null;
      let localSaveUntil = 0;
      let lastBounds = null;
      let initialized = false;
      let mayCreateMissing = createIfMissing;

      const footerText = computed(() => status.value || formatDate(updated.value));
      const memoRef = db ? db.collection('memos').doc(memoId) : null;

      const markLocalSave = () => {
        localSaveUntil = now() + 650;
      };

      const setError = (prefix, error) => {
        status.value = `${prefix}: ${errorText(error)}`;
        statusError.value = true;
      };

      const saveText = async () => {
        if (!memoRef) {
          setError('저장 실패', new Error(firebaseInitError || 'Firestore를 사용할 수 없습니다.'));
          return;
        }

        markLocalSave();
        const ts = now();
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

      const saveBounds = async () => {
        if (!lastBounds) return;
        try {
          if (memoRef) {
            await memoRef.set({
              desktopBounds: lastBounds,
              desktopUpdated: now(),
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
        if (!confirm('이 메모를 삭제할까요?')) return;
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
          if (now() < localSaveUntil) return;

          text.value = data.text || '';
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
        pinned,
        footerText,
        statusError,
        scheduleTextSave,
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
          <textarea
            class="memo-text"
            v-model="text"
            @input="scheduleTextSave"
            placeholder="메모를 입력하세요"
            spellcheck="false"
          ></textarea>
        </div>
        <div class="memo-footer">
          <button class="trash-button" type="button" title="삭제" aria-label="삭제" @click="deleteMemo">
            <img class="trash-icon" src="./assets/trash-can.png" alt="" aria-hidden="true">
          </button>
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
