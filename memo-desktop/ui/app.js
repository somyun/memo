const { createApp, ref, computed, onMounted, onUnmounted, watch } = Vue;

/** memo-web / Android 와 동일 프로젝트 */
firebase.initializeApp({
  apiKey: 'AIzaSyBdJN2qn4Gox8jpIm8ZfPxzeoIU0G_eA-o',
  authDomain: 'memo-3a7c8.firebaseapp.com',
  projectId: 'memo-3a7c8',
  storageBucket: 'memo-3a7c8.firebasestorage.app',
  messagingSenderId: '674466200117',
  appId: '1:674466200117:web:02cb1572cd0a2597ffcf7c',
});

const db = firebase.firestore();

function memoIdFromHash() {
  const h = location.hash.replace(/^#/, '').trim();
  if (h) return h;
  return Date.now().toString(36) + Math.random().toString(36).slice(2, 6);
}

function formatDate(ts) {
  if (!ts) return '';
  const d = new Date(ts);
  const p = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}.${p(d.getMonth() + 1)}.${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}`;
}

createApp({
  setup() {
    const memoId = ref(memoIdFromHash());
    const text = ref('');
    const updated = ref(Date.now());
    const status = ref('연결 중…');
    const statusError = ref(false);
    const desktopLayer = ref(false);
    const localSave = ref(false);

    let saveTimer = null;
    let unsub = null;

    const footerText = computed(() => formatDate(updated.value));

    const scheduleSave = () => {
      clearTimeout(saveTimer);
      status.value = '저장 중…';
      statusError.value = false;
      saveTimer = setTimeout(persistMemo, 1200);
    };

    const persistMemo = async () => {
      localSave.value = true;
      const payload = {
        id: memoId.value,
        text: text.value,
        images: [],
        files: [],
        pinned: false,
        created: updated.value,
        updated: Date.now(),
      };
      updated.value = payload.updated;
      try {
        await db.collection('memos').doc(memoId.value).set(payload, { merge: true });
        status.value = '저장됨';
        setTimeout(() => {
          if (status.value === '저장됨') status.value = '';
        }, 2000);
      } catch (e) {
        status.value = '저장 실패';
        statusError.value = true;
        console.error(e);
      }
      setTimeout(() => {
        localSave.value = false;
      }, 400);
    };

    const startSnapshot = () => {
      unsub = db
        .collection('memos')
        .doc(memoId.value)
        .onSnapshot(
          (snap) => {
            if (!snap.exists) {
              status.value = '새 메모';
              return;
            }
            const data = snap.data();
            if (localSave.value) return;
            text.value = data.text || '';
            updated.value = data.updated || data.created || Date.now();
            status.value = '';
            statusError.value = false;
          },
          (err) => {
            status.value = '동기화 오류';
            statusError.value = true;
            console.error(err);
          }
        );
    };

    const onInput = () => {
      updated.value = Date.now();
      scheduleSave();
    };

    const closeWindow = () => Bridge.event('closeWindow');

    const deleteMemo = async () => {
      if (!confirm('이 메모를 삭제할까요?')) return;
      localSave.value = true;
      try {
        await db.collection('memos').doc(memoId.value).delete();
      } catch (e) {
        console.error(e);
      }
      closeWindow();
    };

    const onTitleMouseDown = (e) => {
      if (e.button !== 0) return;
      if (e.target.closest('button')) return;
      Bridge.event('dragWindow');
    };

    onMounted(() => {
      Bridge.onMessage((msg) => {
        if (msg?.method === 'hostConfig' && msg.params) {
          desktopLayer.value = !!msg.params.desktopLayer;
          if (msg.params.memoId) memoId.value = msg.params.memoId;
        }
        if (msg?.method === 'windowBounds' && msg.params) {
          Bridge.event('persistBounds', msg.params);
        }
      });

      startSnapshot();
      Bridge.event('ready', { memoId: memoId.value });
    });

    onUnmounted(() => {
      if (unsub) unsub();
      clearTimeout(saveTimer);
    });

    return {
      text,
      status,
      statusError,
      footerText,
      desktopLayer,
      onInput,
      closeWindow,
      deleteMemo,
      onTitleMouseDown,
    };
  },
  template: `
    <div class="memo-shell">
      <div class="titlebar" @mousedown="onTitleMouseDown">
        <span class="status" :class="{ 'sync-error': statusError }">{{ status }}</span>
        <button type="button" title="삭제" @click="deleteMemo">×</button>
      </div>
      <div class="memo-body">
        <textarea
          class="memo-text"
          v-model="text"
          @input="onInput"
          placeholder="메모를 입력하세요…"
          spellcheck="false"
        ></textarea>
        <div class="memo-footer">{{ footerText }}</div>
      </div>
    </div>
  `,
}).mount('#app');
