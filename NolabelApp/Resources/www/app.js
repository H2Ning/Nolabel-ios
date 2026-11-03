(() => {
  'use strict';

  /* -------------------------------------------------------
     面额与 3D 边色
     ------------------------------------------------------- */
  const DENOMS = [
    { value: 10000, key: '100', name: '100元', img: 'assets/notes/100.jpg', phys: 155, ratio: 640 / 314, side: '#c98d9b', sideLine: '#a16b79', sideDark: '#83515f' },
    { value: 5000, key: '50', name: '50元', img: 'assets/notes/50.jpg', phys: 150, ratio: 600 / 280, side: '#89a991', sideLine: '#677f6e', sideDark: '#506452' },
    { value: 2000, key: '20', name: '20元', img: 'assets/notes/20.jpg', phys: 145, ratio: 638 / 311, side: '#b39580', sideLine: '#8b705d', sideDark: '#6d5646' },
    { value: 1000, key: '10', name: '10元', img: 'assets/notes/10.jpg', phys: 140, ratio: 432 / 211, side: '#819ab6', sideLine: '#607892', sideDark: '#4b5e75' },
    { value: 500, key: '5', name: '5元', img: 'assets/notes/5.jpg', phys: 135, ratio: 640 / 306, side: '#9c8eae', sideLine: '#786c89', sideDark: '#5c526a' },
    { value: 100, key: '1', name: '1元', img: 'assets/notes/1.jpg', phys: 130, ratio: 640 / 310, side: '#93b18e', sideLine: '#6f8b6a', sideDark: '#576c53' },
    { value: 50, key: '0.5', name: '5角', img: 'assets/notes/0.5.jpg', phys: 125, ratio: 600 / 274, side: '#ad8a9b', sideLine: '#876978', sideDark: '#66515e' },
    { value: 20, key: '0.2', name: '2角', img: 'assets/notes/0.2.jpg', phys: 120, ratio: 640 / 298, side: '#93a9a0', sideLine: '#6f857c', sideDark: '#576861' },
    { value: 10, key: '0.1', name: '1角', img: 'assets/notes/0.1.jpg', phys: 115, ratio: 440 / 195, side: '#9d8b79', sideLine: '#7b6b5b', sideDark: '#5e5246' },
    { value: 5, key: '0.05', name: '5分', img: 'assets/notes/0.05.jpg', phys: 112, ratio: 640 / 304, side: '#98aa9b', sideLine: '#748779', sideDark: '#57695c' },
    { value: 2, key: '0.02', name: '2分', img: 'assets/notes/0.02.jpg', phys: 110, ratio: 640 / 303, side: '#8fa6bc', sideLine: '#6c8298', sideDark: '#516577' },
    { value: 1, key: '0.01', name: '1分', img: 'assets/notes/0.01.jpg', phys: 108, ratio: 640 / 306, side: '#c0a48d', sideLine: '#997f6b', sideDark: '#735d4d' }
  ].map((d) => {
    const baseW = 240 * d.phys / 155;
    return { ...d, baseW, baseH: baseW / d.ratio };
  });

  const BILLS_KEY = 'nolabel-bills-v1';
  const BILLS_OWNER_KEY = 'nolabel-bills-owner';
  const ACCOUNT_APP = 'nolabel';
  const ACCOUNT_KEY = 'bills';
  const NOTE_THICKNESS_MM = 0.12; // 旧钞厚度：新钞 0.1mm × 1.2
  const GRID_VIRTUAL_THRESHOLD = 600;
  const PACKAGE_TILT = 46;
  const PACKAGE_VISIBLE_LIMIT = 10;
  const PITCH_LIMIT = 20;
  const PITCH_PER_PX = 0.3;
  const PITCH_REF_HEIGHT = 300;
  const OP_ORDER = ['+', '-', '*', '/'];
  const OP_TAP_WINDOW = 700;
  // Box projection expands when rotated; draw smaller than its slot to keep clearance.
  const PACKAGE_BOX_DRAW_SCALE = 0.82;
  const moneyFmt = new Intl.NumberFormat('zh-CN', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2
  });
  const compactFmt = new Intl.NumberFormat('zh-CN', {
    maximumFractionDigits: 2
  });

  const $ = (id) => document.getElementById(id);
  const make = (tag, className, text) => {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined) node.textContent = text;
    return node;
  };

  /* -------------------------------------------------------
     DOM
     ------------------------------------------------------- */
  const app = $('app');
  const billsView = $('billsView');
  const billsScroll = $('billsScroll');
  const monthLabel = $('monthLabel');
  const summaryPeriod = $('summaryPeriod');
  const monthExpense = $('monthExpense');
  const monthIncome = $('monthIncome');
  const monthMeta = $('monthMeta');
  const billCount = $('billCount');
  const billList = $('billList');
  const addBillBtn = $('addBillBtn');
  const billsLive = $('billsLive');
  const entryView = $('entryView');
  const closeEntryBtn = $('closeEntryBtn');
  const entryHeading = $('entryHeading');
  const stage = $('stage');
  const stageCanvas = $('stageCanvas');
  const scene3d = $('scene3d');
  const grid2d = $('grid2d');
  const stageEmpty = $('stageEmpty');
  const entryDate = $('entryDate');
  const dateDialog = $('dateDialog');
  const dateInput = $('dateInput');
  const timeInput = $('timeInput');
  const dateCancelBtn = $('dateCancelBtn');
  const dateApplyBtn = $('dateApplyBtn');
  const amountDisplay = $('amountDisplay');
  const amountNumber = $('amountNumber');
  const typeSeg = $('typeSeg');
  const noteInput = $('noteInput');
  const opBtn = $('opBtn');
  const equalsBtn = $('equalsBtn');
  const saveBtn = $('saveBtn');
  const backspaceBtn = $('backspaceBtn');
  const breakdownText = $('breakdownText');
  const stateLive = $('stateLive');
  const prevMonthBtn = $('prevMonthBtn');
  const nextMonthBtn = $('nextMonthBtn');
  const sortToggle = $('sortToggle');
  const settingsBtn = $('settingsBtn');
  const settingsDialog = $('settingsDialog');
  const settingsTitle = $('settingsTitle');
  const settingsCloseBtn = $('settingsCloseBtn');
  const settingsBackBtn = $('settingsBackBtn');
  const settingsMain = $('settingsMain');
  const appearanceView = $('appearanceView');
  const appearanceBtn = $('appearanceBtn');
  const appearanceValue = $('appearanceValue');
  const accountCard = $('accountCard');
  const accountForm = $('accountForm');
  const accountUsername = $('accountUsername');
  const accountPassword = $('accountPassword');
  const accountLoginBtn = $('accountLoginBtn');
  const accountMessage = $('accountMessage');
  const accountUser = $('accountUser');
  const accountAvatar = $('accountAvatar');
  const accountUserName = $('accountUserName');
  const accountLogoutBtn = $('accountLogoutBtn');
  const accountImportBtn = $('accountImportBtn');
  const accountExportBtn = $('accountExportBtn');
  const accountImportFile = $('accountImportFile');
  const transferGroup = $('transferGroup');
  const themeOptions = Array.from(document.querySelectorAll('.theme-option'));
  const themeMedia = window.matchMedia
    ? window.matchMedia('(prefers-color-scheme: dark)')
    : null;
  const THEME_NAMES = { light: '浅色', dark: '深色', system: '跟随系统' };
  let themeMode = document.documentElement.getAttribute('data-theme-mode') || 'system';

  /* -------------------------------------------------------
     状态
     ------------------------------------------------------- */
  const state = {
    bills: [],
    billsMonth: null,
    sortDesc: true,
    amountStr: '',
    type: 'expense',
    calc: { left: null, op: null, fresh: false },
    groups: [],
    count: 0,
    kinds: 0,
    packages: null,
    mode: 1,
    yaw: -30,
    pitchOffset: 0,
    basePitch: PACKAGE_TILT,
    opTapIndex: 0,
    opTapAt: 0,
    level1Piles: 1,
    editingId: null,
    returnBillId: null,
    entryIso: '',
    entryTime: '',
    entryOpen: false,
    stageRaf: 0,
    lastBillId: null,
    suppressBackspaceClick: false,
    momentumRaf: 0,
    dragVelocity: 0,
    lastMoveTime: 0,
    focusPullId: 0,
    gridRaf: 0,
    virtualGrid: null
  };

  /* -------------------------------------------------------
     日期
     ------------------------------------------------------- */
  const pad2 = (n) => String(n).padStart(2, '0');

  function dateLabel(d) {
    return `${d.getMonth() + 1}月${d.getDate()}日`;
  }

  function timeLabel(d) {
    return `${pad2(d.getHours())}:${pad2(d.getMinutes())}`;
  }

  function isoDate(d) {
    return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`;
  }

  function monthLabelOf(d) {
    return `${d.getFullYear()}年${d.getMonth() + 1}月`;
  }

  function dateFromParts(iso, time) {
    const date = new Date(`${iso}T${time || '00:00'}:00`);
    return Number.isNaN(date.getTime()) ? new Date() : date;
  }

  function syncEntryDate() {
    const date = dateFromParts(state.entryIso, state.entryTime);
    const label = `${dateLabel(date)} · ${state.entryTime}`;
    entryDate.textContent = label;
    entryDate.setAttribute('aria-label', `修改日期和时间，当前${dateLabel(date)} ${state.entryTime}`);
  }

  const now = new Date();
  const todayIso = isoDate(now);
  const todayText = dateLabel(now);
  state.billsMonth = new Date(now.getFullYear(), now.getMonth(), 1);
  entryDate.textContent = `${todayText} · ${timeLabel(now)}`;

  /* -------------------------------------------------------
     账单存储
     ------------------------------------------------------- */
  function normalizeBills(raw) {
    if (!raw) return null;
    try {
      const value = JSON.parse(raw);
      const bills = Array.isArray(value) ? value : (value && Array.isArray(value.bills) ? value.bills : null);
      if (!bills) return null;
      return {
        updatedAt: value && Number.isFinite(value.updatedAt) ? value.updatedAt : 0,
        bills: bills.filter((b) => b && Number.isFinite(b.cents) && b.cents > 0 && b.iso)
      };
    } catch (err) {
      return null;
    }
  }

  function nativeStore() {
    return window.webkit && window.webkit.messageHandlers
      ? window.webkit.messageHandlers.nolabelStore
      : null;
  }

  function sendToNative(raw) {
    const bridge = nativeStore();
    if (!bridge) return;
    try {
      bridge.postMessage(raw);
    } catch (err) {}
  }

  function loadBills() {
    let local = null;
    try {
      local = normalizeBills(localStorage.getItem(BILLS_KEY));
    } catch (err) {}
    const native = normalizeBills(
      typeof window.__nolabelNativeBills === 'string' ? window.__nolabelNativeBills : ''
    );
    const chosen = native && (!local || native.updatedAt > local.updatedAt) ? native : local;
    if (!chosen) return [];
    const raw = JSON.stringify({ v: 1, updatedAt: chosen.updatedAt, bills: chosen.bills });
    if (chosen === native) {
      try {
        localStorage.setItem(BILLS_KEY, raw);
      } catch (err) {}
    } else {
      sendToNative(raw);
    }
    return chosen.bills;
  }

  const ACCOUNT_MODE = nativeStore() || /(^|\.)h2ning\.com$/i.test(location.hostname);
  const auth = {
    user: null,
    ready: false,
    loading: false,
    accountLoaded: false,
    message: '',
    tone: ''
  };
  let writing = false;
  let accountView = null;

  function billsPayload(bills, updatedAt) {
    return JSON.stringify({ v: 1, updatedAt: updatedAt || Date.now(), bills });
  }

  function cacheBills(bills, updatedAt, owner) {
    const raw = billsPayload(bills, updatedAt);
    try {
      localStorage.setItem(BILLS_KEY, raw);
      if (owner) localStorage.setItem(BILLS_OWNER_KEY, owner);
      else localStorage.removeItem(BILLS_OWNER_KEY);
    } catch (err) {}
    sendToNative(raw);
  }

  async function postAccountValue(raw) {
    try {
      const response = await fetch('/api/user/set', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        credentials: 'same-origin',
        body: JSON.stringify({ app: ACCOUNT_APP, key: ACCOUNT_KEY, value: raw })
      });
      let data = null;
      try { data = await response.json(); } catch (err) {}
      if (response.status === 401) {
        auth.user = null;
        auth.accountLoaded = false;
        auth.message = '登录已过期，请重新登录';
        auth.tone = 'error';
        updateAccountUI();
        return { ok: false, code: 'auth' };
      }
      if (!response.ok || !data || !data.ok) {
        return { ok: false, code: 'server', message: data && data.message };
      }
      return { ok: true };
    } catch (err) {
      return { ok: false, code: 'network' };
    }
  }

  async function saveBills(bills, updatedAt) {
    if (ACCOUNT_MODE) {
      if (!auth.user) return { ok: false, code: 'auth' };
      if (!auth.accountLoaded) return { ok: false, code: 'not-ready' };
      const raw = billsPayload(bills, updatedAt);
      const result = await postAccountValue(raw);
      if (result.ok) cacheBills(bills, updatedAt, auth.user.name);
      return result;
    }
    cacheBills(bills, updatedAt, '');
    return { ok: true };
  }

  function monthBills(d) {
    const prefix = `${d.getFullYear()}-${pad2(d.getMonth() + 1)}`;
    return state.bills.filter((b) => String(b.iso).startsWith(prefix));
  }

  function updateSortToggle() {
    if (!sortToggle) return;
    const descending = state.sortDesc;
    sortToggle.textContent = descending ? '按时间倒序' : '按时间正序';
    sortToggle.setAttribute('aria-pressed', String(descending));
    sortToggle.setAttribute(
      'aria-label',
      descending ? '当前按时间倒序，点击切换为按时间正序' : '当前按时间正序，点击切换为按时间倒序'
    );
  }

  function renderBills() {
    updateSortToggle();
    const current = state.billsMonth || new Date();
    const currentBills = monthBills(current);
    const expense = currentBills.filter((b) => b.type === 'expense').reduce((sum, b) => sum + b.cents, 0);
    const income = currentBills.filter((b) => b.type === 'income').reduce((sum, b) => sum + b.cents, 0);
    const notes = currentBills.reduce((sum, b) => sum + (b.count || 0), 0);

    monthLabel.textContent = monthLabelOf(current);
    summaryPeriod.textContent = `${current.getMonth() + 1}月`;
    monthExpense.textContent = formatMoney(expense);
    monthExpense.classList.toggle('is-long', formatMoney(expense).length > 8);
    monthIncome.textContent = formatMoney(income);
    monthMeta.textContent = `${currentBills.length} 笔 · ${notes} 张现钞`;
    billCount.textContent = `${currentBills.length} 笔`;

    billList.replaceChildren();

    if (!currentBills.length) {
      buildEmptyBills(state.bills.length > 0);
      return;
    }

    const direction = state.sortDesc ? -1 : 1;
    const sorted = currentBills.slice().sort((a, b) => {
      if (a.iso !== b.iso) return a.iso < b.iso ? -direction : direction;
      return direction * ((a.createdAt || 0) - (b.createdAt || 0));
    });

    const groups = new Map();
    sorted.forEach((bill) => {
      if (!groups.has(bill.iso)) groups.set(bill.iso, []);
      groups.get(bill.iso).push(bill);
    });

    groups.forEach((items, iso) => {
      const group = make('section', 'bill-group');
      const head = make('div', 'bill-date');
      const date = new Date(`${iso}T12:00:00`);
      head.appendChild(make('strong', '', dateLabel(date)));
      if (iso === todayIso) head.appendChild(make('span', 'today', '今天'));
      head.appendChild(make('span', 'rule'));

      const dayExpense = items.reduce(
        (sum, bill) => sum + (bill.type === 'expense' ? bill.cents : 0),
        0
      );
      const dayIncome = items.reduce(
        (sum, bill) => sum + (bill.type === 'income' ? bill.cents : 0),
        0
      );
      const net = dayIncome - dayExpense;
      const total = make(
        'span',
        'day-total',
        `${net > 0 ? '+' : net < 0 ? '−' : ''}¥${formatMoney(Math.abs(net))}`
      );
      if (net < 0) total.classList.add('is-expense');
      else if (net > 0) total.classList.add('is-income');
      total.setAttribute(
        'aria-label',
        `当日支出 ${formatMoney(dayExpense)} 元，收入 ${formatMoney(dayIncome)} 元`
      );
      head.appendChild(total);
      group.appendChild(head);

      items.forEach((bill) => {
        const swipe = make('div', 'bill-swipe');
        swipe.dataset.billId = bill.id;
        const row = make('button', bill.id === state.lastBillId ? 'bill-row is-new' : 'bill-row');
        row.type = 'button';
        row.dataset.billId = bill.id;
        const action = bill.type === 'expense' ? '支出' : '收入';
        row.setAttribute(
          'aria-label',
          `编辑 ${dateLabel(date)} ${bill.time || ''} ${action} ${formatMoney(bill.cents)} 元`
        );
        row.appendChild(make('span', `bill-dot is-${bill.type}`));

        const info = make('span', 'bill-info');
        const fallback = bill.type === 'expense' ? '现金支出' : '现金收入';
        info.appendChild(make('span', 'bill-title', bill.note || fallback));
        const metaParts = [];
        if (bill.time) metaParts.push(bill.time);
        if (bill.count) metaParts.push(`${bill.count} 张`);
        if (bill.kinds) metaParts.push(`${bill.kinds} 种面额`);
        info.appendChild(make('span', 'bill-meta', metaParts.join(' · ')));
        row.appendChild(info);

        const amount = make(
          'span',
          `bill-amount is-${bill.type}`,
          `${bill.type === 'expense' ? '−' : '+'}¥${formatMoney(bill.cents)}`
        );
        row.appendChild(amount);

        const remove = make('button', 'bill-delete');
        remove.type = 'button';
        remove.innerHTML = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4 7h16"></path><path d="M9 7V5h6v2"></path><path d="M6.5 7l.9 13h9.2l.9-13"></path><path d="M10 11v5M14 11v5"></path></svg>';
        remove.dataset.deleteBill = bill.id;
        remove.setAttribute(
          'aria-label',
          '删除 ' + dateLabel(date) + ' ' + (bill.time || '') + ' ' + action + ' ' + formatMoney(bill.cents) + ' 元'
        );

        swipe.appendChild(row);
        swipe.appendChild(remove);
        group.appendChild(swipe);
      });

      billList.appendChild(group);
    });
  }

  function buildEmptyBills(hasOtherBills) {
    const empty = make('div', 'empty-bills');
    empty.appendChild(make('div', 'empty-illustration'));
    empty.appendChild(make('h3', '', hasOtherBills ? '这个月还没有账单' : '还没有账单'));
    const btn = make('button', 'empty-add', '记一笔');
    btn.type = 'button';
    btn.dataset.addBill = 'true';
    empty.appendChild(btn);
    billList.appendChild(empty);
  }

  const DELETE_REVEAL = 68;

  function deleteAppearProgress(offset) {
    return Math.max(0, Math.min(1, (offset / DELETE_REVEAL - 0.5) / 0.5));
  }

  function closeBillSwipes(except) {
    billList.querySelectorAll('.bill-swipe.is-open').forEach((swipe) => {
      if (swipe === except) return;
      swipe.classList.remove('is-open');
      swipe.style.removeProperty('--reveal');
      swipe.style.removeProperty('--delete-progress');
    });
  }

  async function deleteBill(id) {
    if (writing) return;
    if (!ensureAccountForWrite('delete')) return;

    const index = state.bills.findIndex((item) => item.id === id);
    if (index < 0) return;
    const nextBills = state.bills.slice();
    nextBills.splice(index, 1);

    writing = true;
    let result = { ok: false, code: 'network' };
    try {
      result = await saveBills(nextBills, Date.now());
    } catch (err) {}
    writing = false;

    if (!result.ok) {
      if (result.code === 'auth') {
        billsLive.textContent = '登录已过期，请重新登录';
        openSettings();
      } else if (result.code === 'not-ready') {
        billsLive.textContent = '账号数据还没加载好';
        openSettings();
      } else {
        billsLive.textContent = '删除失败，请检查网络后重试';
      }
      return;
    }

    state.bills = nextBills;
    if (state.lastBillId === id) state.lastBillId = null;
    renderBills();
    billsLive.textContent = '已删除一笔账单';
    vibrate(10);
  }

  function mergeBillLists(primary, secondary) {
    const ids = new Set(primary.map((bill) => bill.id));
    return primary.concat(secondary.filter((bill) => !ids.has(bill.id)));
  }

  function updateThemeUI() {
    appearanceValue.textContent = THEME_NAMES[themeMode];
    themeOptions.forEach((option) => {
      const active = option.dataset.themeMode === themeMode;
      option.classList.toggle('is-active', active);
      option.setAttribute('aria-pressed', String(active));
    });
  }

  function showSettingsMain() {
    settingsTitle.textContent = '设置';
    settingsBackBtn.hidden = true;
    settingsMain.hidden = false;
    appearanceView.hidden = true;
    updateThemeUI();
  }

  function showAppearanceView() {
    settingsTitle.textContent = '外观';
    settingsBackBtn.hidden = false;
    settingsMain.hidden = true;
    appearanceView.hidden = false;
    updateThemeUI();
    const active = appearanceView.querySelector('.theme-option.is-active') || settingsBackBtn;
    window.requestAnimationFrame(() => active.focus({ preventScroll: true }));
  }

  function applyTheme(mode, persist) {
    if (!Object.prototype.hasOwnProperty.call(THEME_NAMES, mode)) return;
    themeMode = mode;
    const resolved = mode === 'system'
      ? (themeMedia && themeMedia.matches ? 'dark' : 'light')
      : mode;
    document.documentElement.setAttribute('data-theme', resolved);
    document.documentElement.setAttribute('data-theme-mode', mode);
    const meta = document.querySelector('meta[name="theme-color"]');
    if (meta) meta.setAttribute('content', resolved === 'dark' ? '#0b1310' : '#f2f0e8');
    if (persist) {
      try { localStorage.setItem('nolabel-theme', mode); } catch (err) {}
    }
    updateThemeUI();
  }

  function updateAccountUI() {
    if (!ACCOUNT_MODE) {
      accountCard.hidden = true;
      accountForm.hidden = true;
      accountUser.hidden = true;
      accountMessage.hidden = true;
      transferGroup.hidden = true;
      return;
    }

    accountCard.hidden = !auth.ready;
    accountForm.hidden = !auth.ready || Boolean(auth.user);
    accountUser.hidden = !auth.user;
    accountMessage.hidden = !auth.message || auth.tone !== 'error';
    accountMessage.textContent = auth.message || '';
    accountMessage.classList.remove('is-ok');

    if (!auth.user && !accountUsername.value) {
      try {
        accountUsername.value = localStorage.getItem('h2ning_username') || '';
      } catch (err) {}
    }

    if (auth.user) {
      accountUserName.textContent = auth.user.name;
      accountAvatar.textContent = (auth.user.name || '?').slice(0, 1).toUpperCase();
      accountImportBtn.disabled = auth.loading;
      accountExportBtn.disabled = auth.loading || state.bills.length === 0;
      accountLogoutBtn.disabled = auth.loading;
    }

    transferGroup.hidden = !auth.user || !auth.accountLoaded;
    accountLoginBtn.disabled = auth.loading;
    accountLoginBtn.textContent = auth.loading && !auth.user ? '登录中…' : '登录';
    accountLoginBtn.classList.toggle('is-loading', Boolean(auth.loading && !auth.user));
    accountUsername.disabled = auth.loading;
    accountPassword.disabled = auth.loading;

    const nextView = auth.user ? 'user' : (auth.ready ? 'form' : '');
    if (nextView !== accountView) {
      accountView = nextView;
      const visible = nextView === 'user' ? accountUser : (nextView === 'form' ? accountForm : null);
      if (visible) {
        visible.classList.remove('is-entering');
        void visible.offsetWidth;
        visible.classList.add('is-entering');
      }
    }
  }

  async function loadAccount() {
    if (!auth.user) return;
    auth.loading = true;
    auth.accountLoaded = false;
    auth.message = '';
    auth.tone = '';
    updateAccountUI();

    try {
      const response = await fetch(
        '/api/user/get?app=' + encodeURIComponent(ACCOUNT_APP) + '&key=' + encodeURIComponent(ACCOUNT_KEY),
        { credentials: 'same-origin', cache: 'no-store' }
      );
      if (response.status === 401) {
        auth.user = null;
        auth.accountLoaded = false;
        auth.message = '登录已过期，请重新登录';
        auth.tone = 'error';
        return;
      }

      let data = null;
      try { data = await response.json(); } catch (err) {}
      if (!response.ok || !data || !data.ok) {
        auth.message = '账号数据加载失败';
        auth.tone = 'error';
        return;
      }

      const account = typeof data.value === 'string'
        ? normalizeBills(data.value)
        : (data.value ? normalizeBills(JSON.stringify(data.value)) : null);
      if (data.value && !account) {
        auth.message = '账号数据格式异常';
        auth.tone = 'error';
        return;
      }

      let local = null;
      let localOwner = null;
      try {
        local = normalizeBills(localStorage.getItem(BILLS_KEY));
        localOwner = localStorage.getItem(BILLS_OWNER_KEY);
      } catch (err) {}

      let bills = [];
      let updatedAt = Date.now();
      let needUpload = false;

      if (account) {
        bills = account.bills;
        updatedAt = account.updatedAt || Date.now();
        if (!localOwner && local && local.bills.length) {
          const merged = mergeBillLists(account.bills, local.bills);
          if (merged.length > account.bills.length) {
            bills = merged;
            updatedAt = Date.now();
            needUpload = true;
          }
        }
      } else if (local && local.bills.length && (!localOwner || localOwner === auth.user.name)) {
        bills = local.bills;
        updatedAt = Date.now();
        needUpload = true;
      }

      state.bills = bills;
      auth.accountLoaded = true;

      let cacheOwner = auth.user.name;
      if (needUpload) {
        const posted = await postAccountValue(billsPayload(bills, updatedAt));
        if (!posted.ok) {
          cacheOwner = '';
          auth.message = '已读取账号，但本机账单同步失败';
          auth.tone = 'error';
        } else {
          auth.message = '本机账单已同步到账号';
          auth.tone = 'ok';
        }
      }

      cacheBills(bills, updatedAt, cacheOwner);
      renderBills();
    } catch (err) {
      auth.accountLoaded = false;
      auth.message = '网络错误，账号数据未加载';
      auth.tone = 'error';
    } finally {
      auth.loading = false;
      updateAccountUI();
    }
  }

  async function checkAuth() {
    if (!ACCOUNT_MODE) {
      auth.ready = true;
      auth.accountLoaded = true;
      updateAccountUI();
      return;
    }

    auth.loading = true;
    auth.message = '';
    auth.tone = '';
    updateAccountUI();

    try {
      const response = await fetch('/api/auth/me', {
        credentials: 'same-origin',
        cache: 'no-store'
      });
      let data = null;
      try { data = await response.json(); } catch (err) {}
      if (response.ok && data && data.ok && data.user) {
        auth.user = data.user;
        auth.ready = true;
        await loadAccount();
      } else {
        auth.user = null;
        auth.accountLoaded = false;
      }
    } catch (err) {
      auth.user = null;
      auth.accountLoaded = false;
      auth.message = '网络错误，暂未连接账号';
      auth.tone = 'error';
    } finally {
      auth.loading = false;
      auth.ready = true;
      updateAccountUI();
    }
  }

  async function handleAccountLogin(event) {
    event.preventDefault();
    if (!ACCOUNT_MODE || auth.loading) return;

    const username = accountUsername.value.trim();
    const password = accountPassword.value;
    if (!username || !password) {
      auth.message = '请输入用户名和密码';
      auth.tone = 'error';
      updateAccountUI();
      return;
    }

    auth.loading = true;
    auth.message = '';
    auth.tone = '';
    updateAccountUI();

    try {
      const response = await fetch('/api/auth/login', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        credentials: 'same-origin',
        body: JSON.stringify({ username, password, remember: true })
      });
      let data = null;
      try { data = await response.json(); } catch (err) {}
      if (!response.ok || !data || !data.ok) {
        auth.message = (data && data.message) || '登录失败';
        auth.tone = 'error';
        return;
      }

      auth.user = data.user;
      auth.accountLoaded = false;
      auth.ready = true;
      accountPassword.value = '';
      try { localStorage.setItem('h2ning_username', username); } catch (err) {}
      await loadAccount();
    } catch (err) {
      auth.message = '网络错误，请重试';
      auth.tone = 'error';
    } finally {
      auth.loading = false;
      updateAccountUI();
    }
  }

  async function handleAccountLogout() {
    if (!ACCOUNT_MODE || auth.loading) return;

    auth.loading = true;
    auth.message = '';
    auth.tone = '';
    updateAccountUI();

    try {
      const response = await fetch('/api/auth/logout', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        credentials: 'same-origin',
        body: '{}'
      });
      let data = null;
      try { data = await response.json(); } catch (err) {}
      if (!response.ok || !data || !data.ok) {
        throw new Error('logout failed');
      }

      auth.user = null;
      auth.accountLoaded = false;
      state.bills = [];
      try {
        localStorage.removeItem(BILLS_KEY);
        localStorage.removeItem(BILLS_OWNER_KEY);
      } catch (err) {}
      sendToNative(billsPayload([], Date.now()));
      renderBills();
      auth.message = '';
      auth.tone = '';
      billsLive.textContent = '账号账单已隐藏';
    } catch (err) {
      auth.message = '退出失败，请重试';
      auth.tone = 'error';
    } finally {
      auth.loading = false;
      updateAccountUI();
    }
  }

  function ensureAccountForWrite(action) {
    if (!ACCOUNT_MODE) return true;
    if (auth.user && auth.accountLoaded) return true;

    const message = !auth.user ? '请先在设置登录账号' : '账号数据还没加载好';
    if (action === 'save') showHint(message);
    else billsLive.textContent = message;
    auth.message = message;
    auth.tone = 'error';
    updateAccountUI();
    openSettings();
    return false;
  }

  /* -------------------------------------------------------
     CSV 导入 / 导出
     ------------------------------------------------------- */
  function parseCsvRows(text) {
    const source = String(text || '').replace(/^\uFEFF/, '');
    const rows = [];
    let row = [];
    let field = '';
    let quoted = false;

    for (let i = 0; i < source.length; i += 1) {
      const ch = source[i];
      if (quoted) {
        if (ch === '"') {
          if (source[i + 1] === '"') {
            field += '"';
            i += 1;
          } else {
            quoted = false;
          }
        } else {
          field += ch;
        }
      } else if (ch === '"') {
        quoted = true;
      } else if (ch === ',') {
        row.push(field);
        field = '';
      } else if (ch === '\n') {
        row.push(field);
        rows.push(row);
        row = [];
        field = '';
      } else if (ch !== '\r') {
        field += ch;
      }
    }

    if (field || row.length) {
      row.push(field);
      rows.push(row);
    }

    return rows.filter((cells) => cells.some((cell) => String(cell).trim() !== ''));
  }

  function normalizeCsvDate(raw) {
    const value = String(raw || '').trim().replace(/[./]/g, '-');
    const match = /^(\d{4})-(\d{1,2})-(\d{1,2})$/.exec(value);
    if (!match) return '';
    const year = Number(match[1]);
    const month = Number(match[2]);
    const day = Number(match[3]);
    const date = new Date(year, month - 1, day);
    if (
      date.getFullYear() !== year ||
      date.getMonth() !== month - 1 ||
      date.getDate() !== day
    ) return '';
    return `${year}-${pad2(month)}-${pad2(day)}`;
  }

  function normalizeCsvTime(raw) {
    const match = /^(\d{1,2}):(\d{2})(?::\d{2})?$/.exec(String(raw || '').trim());
    if (!match) return '';
    const hour = Number(match[1]);
    const minute = Number(match[2]);
    if (hour > 23 || minute > 59) return '';
    return `${pad2(hour)}:${pad2(minute)}`;
  }

  function normalizeCsvType(raw) {
    const value = String(raw || '').trim().toLowerCase();
    if (value === '支出' || value === 'expense') return 'expense';
    if (value === '收入' || value === 'income') return 'income';
    return '';
  }

  function parseBillsCsv(text) {
    const rows = parseCsvRows(text);
    if (rows.length < 2) return { bills: [], errors: ['CSV 里没有账单'] };

    const headers = rows[0].map((cell) => String(cell || '').trim().toLowerCase());
    const aliases = {
      id: ['编号', 'id'],
      date: ['日期', 'date'],
      time: ['时间', 'time'],
      type: ['类型', 'type'],
      amount: ['金额', 'amount'],
      note: ['备注', 'note']
    };
    const findColumn = (names) => headers.findIndex((header) => names.includes(header));
    const idIndex = findColumn(aliases.id);
    const dateIndex = findColumn(aliases.date);
    const timeIndex = findColumn(aliases.time);
    const typeIndex = findColumn(aliases.type);
    const amountIndex = findColumn(aliases.amount);
    const noteIndex = findColumn(aliases.note);
    const missing = [];

    if (dateIndex < 0) missing.push('日期');
    if (timeIndex < 0) missing.push('时间');
    if (typeIndex < 0) missing.push('类型');
    if (amountIndex < 0) missing.push('金额');
    if (missing.length) return { bills: [], errors: [`CSV 缺少列：${missing.join('、')}`] };

    const bills = [];
    const errors = [];
    const usedIds = new Set();

    for (let i = 1; i < rows.length; i += 1) {
      const row = rows[i];
      const line = i + 1;
      if (!row.some((cell) => String(cell || '').trim())) continue;

      try {
        const iso = normalizeCsvDate(row[dateIndex]);
        if (!iso) throw new Error('日期格式应为 YYYY-MM-DD');
        const time = normalizeCsvTime(row[timeIndex]);
        if (!time) throw new Error('时间格式应为 HH:mm');
        const type = normalizeCsvType(row[typeIndex]);
        if (!type) throw new Error('类型应为支出或收入');

        const rawAmount = String(row[amountIndex] || '').replace(/[¥￥,\s]/g, '');
        const amount = Number(rawAmount);
        if (!Number.isFinite(amount) || amount <= 0) throw new Error('金额必须大于 0');
        const cents = Math.round(amount * 100);
        if (cents < 1) throw new Error('金额最小到 0.01 元');

        const split = breakdown(cents);
        if (split.remainder !== 0 || !split.groups.length) throw new Error('金额无法拆分现钞');
        const groups = split.groups.map((group) => ({ key: group.denom.key, count: group.count }));

        let id = idIndex >= 0 ? String(row[idIndex] || '').trim() : '';
        if (!id) id = `csv-${Date.now().toString(36)}-${i}`;
        if (usedIds.has(id)) throw new Error('编号重复');
        usedIds.add(id);

        const note = noteIndex >= 0 ? String(row[noteIndex] || '').trim().slice(0, 24) : '';
        const createdAt = dateFromParts(iso, time).getTime();
        if (!Number.isFinite(createdAt)) throw new Error('日期时间无效');

        bills.push({
          id,
          cents,
          type,
          note,
          iso,
          time,
          createdAt,
          count: totalNotes(groups),
          kinds: groups.length,
          groups
        });
      } catch (err) {
        errors.push(`第 ${line} 行：${err.message}`);
      }
    }

    if (!bills.length && !errors.length) errors.push('CSV 里没有账单');
    return { bills, errors };
  }

  function csvCell(value) {
    const text = String(value == null ? '' : value);
    return /[",\r\n]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text;
  }

  function billsCsvText(bills) {
    const rows = [['编号', '日期', '时间', '类型', '金额', '备注']];
    const sorted = bills.slice().sort((a, b) => {
      const left = `${a.iso || ''} ${a.time || '00:00'}`;
      const right = `${b.iso || ''} ${b.time || '00:00'}`;
      return left < right ? -1 : left > right ? 1 : 0;
    });

    sorted.forEach((bill) => {
      rows.push([
        bill.id || '',
        bill.iso || '',
        bill.time || '',
        bill.type === 'income' ? '收入' : '支出',
        (bill.cents / 100).toFixed(2),
        bill.note || ''
      ]);
    });

    return '\uFEFF' + rows.map((row) => row.map(csvCell).join(',')).join('\r\n') + '\r\n';
  }

  function exportBillsCsv() {
    if (!auth.user) return;
    if (!state.bills.length) {
      auth.message = '还没有可导出的账单';
      auth.tone = 'error';
      updateAccountUI();
      return;
    }

    const blob = new Blob([billsCsvText(state.bills)], { type: 'text/csv;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    const name = String(auth.user.name || 'nolabel').replace(/[\\/:*?"<>|]+/g, '_');
    link.href = url;
    link.download = `${name}-nolabel-${isoDate(new Date())}.csv`;
    link.rel = 'noopener';
    document.body.appendChild(link);
    link.click();
    link.remove();
    window.setTimeout(() => URL.revokeObjectURL(url), 1000);

    auth.message = `已导出 ${state.bills.length} 笔`;
    auth.tone = 'ok';
    updateAccountUI();
    billsLive.textContent = `已导出 ${state.bills.length} 笔账单`;
  }

  async function handleAccountImport(event) {
    const input = event.target;
    const file = input.files && input.files[0];
    input.value = '';
    if (!file) return;

    if (!auth.user || !auth.accountLoaded) {
      auth.message = '请先登录并等待账号数据加载';
      auth.tone = 'error';
      updateAccountUI();
      return;
    }
    if (file.size > 5 * 1024 * 1024) {
      auth.message = 'CSV 文件不能超过 5MB';
      auth.tone = 'error';
      updateAccountUI();
      return;
    }

    let text = '';
    try {
      text = await file.text();
    } catch (err) {
      auth.message = 'CSV 文件读取失败';
      auth.tone = 'error';
      updateAccountUI();
      return;
    }

    const parsed = parseBillsCsv(text);
    if (parsed.errors.length) {
      auth.message = `导入失败：${parsed.errors.slice(0, 3).join('；')}`;
      auth.tone = 'error';
      updateAccountUI();
      return;
    }
    if (!parsed.bills.length) {
      auth.message = 'CSV 里没有账单';
      auth.tone = 'error';
      updateAccountUI();
      return;
    }

    if (!window.confirm(`将 ${parsed.bills.length} 笔账单导入 ${auth.user.name} 账号？`)) return;

    const merged = new Map(state.bills.map((bill) => [bill.id, bill]));
    parsed.bills.forEach((bill) => merged.set(bill.id, bill));
    const nextBills = [...merged.values()];
    const result = await saveBills(nextBills, Date.now());

    if (!result.ok) {
      auth.message = result.code === 'auth'
        ? '登录已过期，请重新登录'
        : (result.code === 'not-ready' ? '账号数据还没加载好' : '导入失败，请检查网络后重试');
      auth.tone = 'error';
      updateAccountUI();
      return;
    }

    state.bills = nextBills;
    renderBills();
    auth.message = `已导入 ${parsed.bills.length} 笔，共 ${nextBills.length} 笔`;
    auth.tone = 'ok';
    updateAccountUI();
    billsLive.textContent = `已导入 ${parsed.bills.length} 笔账单`;
    vibrate(10);
  }

  function shiftBillsMonth(delta) {
    const base = state.billsMonth || new Date();
    state.billsMonth = new Date(base.getFullYear(), base.getMonth() + delta, 1);
    billsScroll.scrollTop = 0;
    renderBills();
    billsLive.textContent = `已切换到${monthLabelOf(state.billsMonth)}`;
    vibrate(5);
  }

  function openSettings() {
    showSettingsMain();
    updateAccountUI();
    if (!settingsDialog.open) {
      if (typeof settingsDialog.showModal === 'function') settingsDialog.showModal();
      else settingsDialog.setAttribute('open', '');
    }
    if (ACCOUNT_MODE && auth.ready && !auth.user && !accountForm.hidden) {
      window.requestAnimationFrame(() => {
        accountUsername.focus({ preventScroll: true });
      });
    } else {
      settingsCloseBtn.focus({ preventScroll: true });
    }
  }

  function formatMoney(cents) {
    return moneyFmt.format(cents / 100);
  }

  /* -------------------------------------------------------
     金额、表达式与运算
     ------------------------------------------------------- */
  function centsFromRaw(raw) {
    if (!raw || raw === '.') return 0;
    const n = Number(raw);
    if (!Number.isFinite(n) || n <= 0) return 0;
    return Math.round(n * 100);
  }

  function rawFromCents(cents) {
    const yuan = cents / 100;
    if (Number.isInteger(yuan)) return String(yuan);
    return yuan.toFixed(2).replace(/0+$/, '').replace(/\.$/, '');
  }

  function formatInput(raw) {
    if (!raw) return '0.00';
    const parts = raw.split('.');
    const intPart = (parts[0] || '0').replace(/^0+(?=\d)/, '') || '0';
    const grouped = intPart.replace(/\B(?=(\d{3})+(?!\d))/g, ',');
    return raw.includes('.') ? `${grouped}.${parts[1] || ''}` : grouped;
  }

  function formatCompact(cents) {
    return compactFmt.format(cents / 100);
  }

  function opSymbol(op) {
    return { '+': '+', '-': '−', '*': '×', '/': '÷' }[op] || op;
  }

  function opName(op) {
    return { '+': '加法', '-': '减法', '*': '乘法', '/': '除法' }[op] || '运算';
  }

  function operate(left, op, right) {
    if (left === null || !op) return null;
    let result;

    if (op === '+') result = left + right;
    else if (op === '-') result = left - right;
    else if (op === '*') result = Math.round(left * right / 100);
    else if (op === '/') {
      if (!right) {
        showHint('不能除以 0');
        return null;
      }
      result = Math.round(left / right * 100);
    } else return null;

    if (result < 0) {
      showHint('金额不能为负');
      return null;
    }

    return result;
  }

  function breakdown(cents) {
    let left = Math.max(0, Math.round(cents));
    const groups = [];

    DENOMS.forEach((denom) => {
      if (left >= denom.value) {
        const count = Math.floor(left / denom.value);
        groups.push({ denom, count });
        left -= count * denom.value;
      }
    });

    return { groups, remainder: left };
  }

  function totalNotes(groups) {
    return groups.reduce((sum, g) => sum + g.count, 0);
  }

  function packageBreakdown(cents) {
    const boxes = Math.floor(cents / 100000000);
    let rest = cents % 100000000;
    const bundles = Math.floor(rest / 10000000);
    rest %= 10000000;
    const stacks = Math.floor(rest / 1000000);
    const remainderCents = rest % 1000000;
    return { boxes, bundles, stacks, remainderCents };
  }

  /* -------------------------------------------------------
     金额显示与输入
     ------------------------------------------------------- */
  function setAmount(next) {
    state.amountStr = next;
    renderAmount();
    updateExpression();
    scheduleStageUpdate();
  }

  function expressionText() {
    const { left, op, fresh } = state.calc;
    if (left === null || !op) return '';
    const current = fresh || !state.amountStr ? '' : formatInput(state.amountStr);
    return `${formatCompact(left)}${opSymbol(op)}${current}`;
  }

  function previewCents() {
    const { left, op, fresh } = state.calc;
    if (left === null || !op || fresh) return centsFromRaw(state.amountStr);
    const right = centsFromRaw(state.amountStr);
    let result;
    if (op === '+') result = left + right;
    else if (op === '-') result = left - right;
    else if (op === '*') result = Math.round(left * right / 100);
    else if (op === '/') {
      if (!right) return 0;
      result = Math.round(left / right * 100);
    } else return right;
    if (result < 0) return 0;
    return result;
  }

  function renderAmount() {
    const expr = expressionText();
    const isEmpty = !expr && (state.amountStr === '' || state.amountStr === '.');
    const text = expr || formatInput(state.amountStr);

    amountDisplay.dataset.empty = isEmpty ? 'true' : 'false';
    amountNumber.textContent = text;
    amountNumber.classList.toggle('is-long', text.length > 9);
    amountNumber.classList.toggle('is-very-long', text.length > 14);
    amountNumber.classList.toggle('is-ultra-long', text.length > 19);
    saveBtn.disabled = previewCents() <= 0;
  }

  function updateExpression() {
    const { op } = state.calc;
    opBtn.querySelectorAll('.op-symbol').forEach((node) => {
      node.classList.toggle('is-active', Boolean(op) && node.dataset.op === op);
    });
    opBtn.setAttribute('aria-label', op ? `选择运算，当前${opName(op)}，快速连按切换，停顿后从加法重新开始` : '选择运算，快速连按切换，停顿后从加法重新开始');
    renderAmount();
  }

  function addDigits(digits) {
    if (state.calc.fresh) {
      state.calc.fresh = false;
      const start = digits === '00' ? '0' : digits;
      setAmount(start);
      return;
    }

    const raw = state.amountStr;

    if (raw.includes('.')) {
      const decPart = raw.split('.')[1] || '';
      if (decPart.length >= 2) return;
      const add = digits.slice(0, 2 - decPart.length);
      if (!add) return;
      setAmount(raw + add);
      return;
    }

    const base = raw === '0' ? '' : raw;
    let next = `${base}${digits}`.replace(/^0+(?=\d)/, '');
    if (next === '') next = '0';
    setAmount(next);
  }

  function addDecimal() {
    if (state.calc.fresh) {
      state.calc.fresh = false;
      setAmount('0.');
      return;
    }
    if (!state.amountStr) {
      setAmount('0.');
      return;
    }
    if (state.amountStr.includes('.')) return;
    setAmount(`${state.amountStr}.`);
  }

  function deleteLast() {
    if (state.calc.fresh) {
      state.calc.left = null;
      state.calc.op = null;
      state.calc.fresh = false;
      updateExpression();
      return;
    }
    if (!state.amountStr) {
      if (state.calc.left !== null) {
        const left = state.calc.left;
        state.calc.left = null;
        state.calc.op = null;
        state.calc.fresh = false;
        setAmount(rawFromCents(left));
      }
      return;
    }
    setAmount(state.amountStr.slice(0, -1));
  }

  function clearAmount() {
    resetOpCycle();
    state.amountStr = '';
    state.calc = { left: null, op: null, fresh: false };
    renderAmount();
    updateExpression();
    showHint('');
    scheduleStageUpdate();
  }

  function resetOpCycle() {
    state.opTapIndex = 0;
    state.opTapAt = 0;
  }

  function pressKey(key) {
    resetOpCycle();
    vibrate(6);
    if (key === 'backspace') {
      deleteLast();
      return;
    }
    if (key === '.') {
      addDecimal();
      return;
    }
    if (key === '00') {
      addDigits('00');
      return;
    }
    if (/^[0-9]$/.test(key)) addDigits(key);
  }

  function pressOperator() {
    const now = performance.now();
    const rapid = state.opTapAt !== 0 && now - state.opTapAt <= OP_TAP_WINDOW;
    state.opTapIndex = rapid ? (state.opTapIndex + 1) % OP_ORDER.length : 0;
    state.opTapAt = now;
    const selectedOp = OP_ORDER[state.opTapIndex];
    const current = centsFromRaw(state.amountStr);

    if (state.calc.left === null) {
      state.calc.left = current;
      state.calc.op = selectedOp;
      state.calc.fresh = true;
    } else if (state.calc.fresh) {
      state.calc.op = selectedOp;
    } else {
      const result = operate(state.calc.left, state.calc.op, current);
      if (result === null) return;
      state.calc.left = result;
      state.calc.op = selectedOp;
      state.calc.fresh = true;
      setAmount(rawFromCents(result));
    }

    updateExpression();
    vibrate(7);
  }

  function pressEquals() {
    resetOpCycle();
    if (state.calc.left === null || !state.calc.op) return;
    if (!state.calc.fresh) {
      const result = operate(state.calc.left, state.calc.op, centsFromRaw(state.amountStr));
      if (result === null) return;
      setAmount(rawFromCents(result));
    }
    state.calc = { left: null, op: null, fresh: false };
    updateExpression();
    vibrate(7);
  }

  function finalizeCents() {
    let cents = centsFromRaw(state.amountStr);
    if (state.calc.left !== null && state.calc.op) {
      if (!state.calc.fresh) {
        const result = operate(state.calc.left, state.calc.op, cents);
        if (result === null) return null;
        cents = result;
        setAmount(rawFromCents(cents));
      } else {
        cents = state.calc.left;
      }
      state.calc = { left: null, op: null, fresh: false };
      updateExpression();
    }
    return cents;
  }

  function showHint(text) {
    stateLive.textContent = text || '';
  }

  function vibrate(pattern) {
    if (typeof navigator.vibrate !== 'function') return;
    try {
      navigator.vibrate(pattern);
    } catch (err) {}
  }

  /* -------------------------------------------------------
     3D 场景
     ------------------------------------------------------- */
  function face(className) {
    return make('div', `face3d ${className}`);
  }

  function createLayer(denom, w, d, t, zBottom, step) {
    const layer = make('div', 'layer3d');
    layer.style.setProperty('--zc', `${zBottom + t / 2}px`);
    layer.style.setProperty('--w', `${w}px`);
    layer.style.setProperty('--d', `${d}px`);
    layer.style.setProperty('--t', `${t}px`);
    layer.style.setProperty('--img', `url("${denom.img}")`);
    layer.style.setProperty('--side', denom.side);
    layer.style.setProperty('--side-line', denom.sideLine);
    layer.style.setProperty('--side-dark', denom.sideDark);
    layer.style.setProperty('--line-step', `${step}px`);

    layer.appendChild(face('face3d--note'));
    layer.appendChild(face('face3d--back'));
    layer.appendChild(face('face3d--side face3d--left'));
    layer.appendChild(face('face3d--side face3d--right'));
    layer.appendChild(face('face3d--side face3d--topside'));
    layer.appendChild(face('face3d--side face3d--bottomside'));
    return layer;
  }

  function createStackBase(w, d) {
    const base = make('div', 'stack-base');
    base.style.setProperty('--bw', `${w * 1.12}px`);
    base.style.setProperty('--bd', `${d * 1.16}px`);
    return base;
  }

  function pitchForCount(count) {
    const progress = Math.min(1, Math.max(0, (count - 1) / 109));
    return 40 + 6 * progress;
  }

  function applyScenePitch() {
    scene3d.style.setProperty('--tilt', `${(state.basePitch + state.pitchOffset).toFixed(1)}deg`);
  }

  function sceneVisualHeight() {
    let top = Infinity;
    let bottom = -Infinity;
    scene3d.querySelectorAll('.face3d').forEach((face) => {
      const rect = face.getBoundingClientRect();
      if (!rect.width && !rect.height) return;
      top = Math.min(top, rect.top);
      bottom = Math.max(bottom, rect.bottom);
    });
    return bottom > top ? bottom - top : 0;
  }

  function updateScenePitch() {
    state.basePitch = pitchForCount(state.count);
    applyScenePitch();
  }

  function fitPileLayout(count, availableW, maxNoteW, maxThickness, phys) {
    const gap = 3;
    let best = null;

    for (let piles = 1; piles <= 10; piles += 1) {
      const perPile = Math.ceil(count / piles);
      if (!perPile) break;
      const widthByRow = (availableW - gap * (piles - 1)) / piles;
      const widthByHeight = maxThickness * phys / (perPile * NOTE_THICKNESS_MM);
      const width = Math.min(maxNoteW, widthByRow, widthByHeight);
      if (width < 6) continue;
      if (!best || width > best.width + 0.01) {
        best = { piles, width, gap };
      }
    }

    if (!best) {
      const piles = Math.max(1, Math.min(10, count));
      return {
        piles,
        width: Math.max(2, Math.min(maxNoteW, (availableW - gap * (piles - 1)) / piles)),
        gap
      };
    }
    return best;
  }

  function splitGroupsForPiles(groups, count) {
    const maps = Array.from({ length: count }, () => new Map());
    let cursor = 0;
    groups.forEach((group) => {
      for (let i = 0; i < group.count; i += 1) {
        const pile = cursor % count;
        const key = group.denom.key;
        const map = maps[pile];
        map.set(key, (map.get(key) || 0) + 1);
        cursor += 1;
      }
    });

    return maps.map((map) => DENOMS
      .filter((denom) => map.has(denom.key))
      .map((denom) => ({ denom, count: map.get(denom.key) })));
  }

  function createCuboid(w, d, h) {
    const body = make('div', 'package-body');
    body.style.transform = `translateZ(${h / 2}px)`;

    const addFace = (className, width, height, transform) => {
      const el = make('div', `face3d package-face ${className}`);
      el.style.width = `${width}px`;
      el.style.height = `${height}px`;
      el.style.transform = transform;
      body.appendChild(el);
      return el;
    };

    const top = addFace('package-face--top', w, d, `translate(-50%, -50%) translateZ(${h / 2}px)`);
    const front = addFace('package-face--front', w, h, `translate(-50%, -50%) rotateX(-90deg) translateZ(${d / 2}px)`);
    const back = addFace('package-face--back', w, h, `translate(-50%, -50%) rotateX(90deg) translateZ(${d / 2}px)`);
    const left = addFace('package-face--left', h, d, `translate(-50%, -50%) rotateY(-90deg) translateZ(${w / 2}px)`);
    const right = addFace('package-face--right', h, d, `translate(-50%, -50%) rotateY(90deg) translateZ(${w / 2}px)`);

    return { body, top, front, back, left, right };
  }

  function buildBoxItem(x, baseY, w) {
    const d = w * 0.62;
    const h = w * 0.55;
    const root = make('div', 'stack3d package-stack');
    root.style.left = `${x}px`;
    root.style.top = `${baseY}px`;
    root.style.setProperty('--tape-w', `${w * 0.18}px`);
    root.appendChild(createStackBase(w, d));

    const faces = createCuboid(w, d, h);
    faces.top.classList.add('box-face', 'box-face--top');
    faces.front.classList.add('box-face', 'box-face--front');
    faces.back.classList.add('box-face', 'box-face--back');
    faces.left.classList.add('box-face', 'box-face--left');
    faces.right.classList.add('box-face', 'box-face--right');

    const topTape = make('div', 'box-tape-top');
    faces.top.appendChild(topTape);

    const rightTape = make('div', 'box-tape-side box-tape-side--right');
    faces.right.appendChild(rightTape);
    const leftTape = make('div', 'box-tape-side box-tape-side--left');
    faces.left.appendChild(leftTape);

    const labelWrap = make('div', 'box-side-label');
    const sticker = make('div', 'box-note-sticker');
    sticker.style.width = `${w * 0.36}px`;
    sticker.style.height = `${w * 0.36 / (640 / 314)}px`;
    sticker.style.backgroundImage = `url("${DENOMS[0].img}")`;
    labelWrap.appendChild(sticker);
    faces.front.appendChild(labelWrap);

    root.appendChild(faces.body);
    scene3d.appendChild(root);
  }

  function buildBundleItem(x, baseY, w) {
    const denom = DENOMS[0];
    const d = w / denom.ratio;
    const h = 1000 * w * NOTE_THICKNESS_MM / denom.phys;
    const layerH = h / 10;
    const bandW = w * 0.10;
    const jitter = [0.50, 0.486, 0.512, 0.492, 0.505, 0.479, 0.518, 0.494, 0.501, 0.489];
    const root = make('div', 'stack3d package-stack');
    root.style.left = `${x}px`;
    root.style.top = `${baseY}px`;
    root.style.setProperty('--band-w', `${w * 0.10}px`);
    root.style.setProperty('--side', denom.side);
    root.style.setProperty('--side-line', denom.sideLine);
    root.style.setProperty('--side-dark', denom.sideDark);
    root.style.setProperty('--side-step', `${Math.max(1.2, w * NOTE_THICKNESS_MM / denom.phys)}px`);
    root.appendChild(createStackBase(w, d));

    const faces = createCuboid(w, d, h);
    faces.top.classList.add('package-note-top');
    faces.top.style.backgroundImage = `url("${denom.img}")`;
    [faces.front, faces.back, faces.left, faces.right].forEach((face) => {
      face.classList.add('package-side');
    });
    faces.front.classList.add('bundle-side');
    faces.back.classList.add('bundle-side');
    faces.left.classList.add('bundle-cut');
    faces.right.classList.add('bundle-cut', 'bundle-cut--right');
    [faces.front, faces.back].forEach((face) => {
      face.appendChild(make('div', 'bundle-margin bundle-margin--left'));
      face.appendChild(make('div', 'bundle-margin bundle-margin--right'));
    });

    jitter.forEach((ratio, i) => {
      const bandFront = make('div', 'bundle-band bundle-band--layer');
      bandFront.style.left = `calc(${ratio * 100}% - ${bandW / 2}px)`;
      bandFront.style.top = `${i * layerH}px`;
      bandFront.style.height = `${layerH}px`;
      bandFront.style.width = `${bandW}px`;
      faces.front.appendChild(bandFront);

      const bandBack = make('div', 'bundle-band bundle-band--layer');
      bandBack.style.left = `calc(${ratio * 100}% - ${bandW / 2}px)`;
      bandBack.style.top = `${i * layerH}px`;
      bandBack.style.height = `${layerH}px`;
      bandBack.style.width = `${bandW}px`;
      faces.back.appendChild(bandBack);
    });

    const bandTop = make('div', 'bundle-band bundle-band--top');
    bandTop.style.left = `${jitter[9] * 100}%`;
    faces.top.appendChild(bandTop);

    const seal = make('div', 'bundle-seal');
    seal.style.setProperty('--seal-circle', `${Math.max(14, w * 0.12)}px`);
    seal.style.setProperty('--seal-bank', `${Math.max(5, w * 0.045)}px`);
    seal.style.setProperty('--seal-check', `${Math.max(4, w * 0.036)}px`);
    seal.style.setProperty('--seal-main', `${Math.max(5, w * 0.048)}px`);
    seal.style.setProperty('--seal-amount', `${Math.max(9, w * 0.10)}px`);
    seal.style.setProperty('--seal-vertical', `${Math.max(3, w * 0.024)}px`);
    seal.style.setProperty('--seal-foot', `${Math.max(3, w * 0.026)}px`);
    seal.style.setProperty('--seal-blue', `${Math.max(6, w * 0.05)}px`);

    const sealTop = make('div', 'seal-top-row');
    sealTop.append(
      make('div', 'seal-circle', '100'),
      make('div', 'seal-bank-name', '中国银行'),
      make('div', 'seal-check', '封签')
    );

    const sealFoot = make('div', 'seal-foot');
    sealFoot.append(
      make('span', null, '年 月 日'),
      make('span', 'seal-role', '复核员'),
      make('span', 'seal-red-no', '07225'),
      make('span', 'seal-role', '封捆员'),
      make('span', 'seal-red-no', '04325')
    );

    const blueA = make('div', 'seal-blue-stamp', '已消毒');
    blueA.style.left = '5%';
    blueA.style.top = '34%';
    const blueB = make('div', 'seal-blue-stamp', '已消毒');
    blueB.style.left = '40%';
    blueB.style.top = '24%';

    seal.append(
      sealTop,
      make('div', 'seal-main', '人民币壹佰圆'),
      make('div', 'seal-amount', '壹拾万元整'),
      make('div', 'seal-vertical', '封签对外无效'),
      sealFoot,
      make('div', 'seal-red-stamp', '已消毒'),
      blueA,
      blueB
    );
    faces.top.appendChild(seal);

    faces.top.appendChild(make('div', 'bundle-gloss'));
    faces.front.appendChild(make('div', 'bundle-gloss bundle-gloss--front'));

    root.appendChild(faces.body);
    scene3d.appendChild(root);
  }

  function buildStackItem(x, baseY, w) {
    const denom = DENOMS[0];
    const d = w / denom.ratio;
    const h = 100 * w * NOTE_THICKNESS_MM / denom.phys;
    const root = make('div', 'stack3d package-stack');
    root.style.left = `${x}px`;
    root.style.top = `${baseY}px`;
    root.style.setProperty('--band-w', `${w * 0.10}px`);
    root.style.setProperty('--side', denom.side);
    root.style.setProperty('--side-line', denom.sideLine);
    root.style.setProperty('--side-dark', denom.sideDark);
    root.style.setProperty('--side-step', `${Math.max(1.2, w * NOTE_THICKNESS_MM / denom.phys)}px`);
    root.appendChild(createStackBase(w, d));

    const faces = createCuboid(w, d, h);
    faces.top.classList.add('package-note-top');
    faces.top.style.backgroundImage = `url("${denom.img}")`;
    faces.front.classList.add('package-side');
    faces.back.classList.add('package-side');
    faces.left.classList.add('package-side', 'bundle-cut');
    faces.right.classList.add('package-side', 'bundle-cut', 'bundle-cut--right');
    [faces.front, faces.back].forEach((face) => {
      face.appendChild(make('div', 'bundle-margin bundle-margin--left'));
      face.appendChild(make('div', 'bundle-margin bundle-margin--right'));
    });

    faces.top.appendChild(make('div', 'bundle-band bundle-band--top'));
    faces.front.appendChild(make('div', 'bundle-band bundle-band--front'));
    faces.back.appendChild(make('div', 'bundle-band bundle-band--back'));

    root.appendChild(faces.body);
    scene3d.appendChild(root);
  }

  function buildRemainderItem(x, baseY, w) {
    const groups = breakdown(state.packages.remainderCents).groups;
    if (!groups.length) return;
    const denom = groups[0].denom;
    const scale = w / denom.baseW;
    const perNote = w * NOTE_THICKNESS_MM / denom.phys;
    const root = make('div', 'stack3d package-stack');
    root.style.left = `${x}px`;
    root.style.top = `${baseY}px`;
    root.appendChild(createStackBase(w, denom.baseH * scale));

    let z = 0;
    groups.forEach((group) => {
      const gw = group.denom.baseW * scale;
      const gd = group.denom.baseH * scale;
      const t = Math.max(0.8, group.count * perNote);
      root.appendChild(createLayer(group.denom, gw, gd, t, z, perNote));
      z += t;
    });

    scene3d.appendChild(root);
  }

  function buildLevel1Packages(W, H) {
    const p = state.packages;
    if (!p) return;

    const rows = [];
    if (p.boxes) {
      rows.push({ type: 'box', actual: p.boxes, shown: Math.min(p.boxes, PACKAGE_VISIBLE_LIMIT) });
    }
    if (p.bundles) {
      rows.push({ type: 'bundle', actual: p.bundles, shown: Math.min(p.bundles, PACKAGE_VISIBLE_LIMIT) });
    }
    if (p.stacks) {
      rows.push({ type: 'stack', actual: p.stacks, shown: Math.min(p.stacks, PACKAGE_VISIBLE_LIMIT) });
    }
    if (p.remainderCents > 0) {
      rows.push({ type: 'remainder', actual: 1, shown: 1 });
    }
    if (!rows.length) return;

    state.level1Piles = 1;
    const avail = W * 0.82;
    const gap = 6;
    // Notes have no draw-scale clearance, so they need a wider slot gap than boxes.
    const noteGap = 14;

    const splits = rows.map(() => 1);
    let slotCount = rows.length;
    rows.forEach((row, index) => {
      if (row.type === 'box' && row.shown >= 3 && slotCount < 4) {
        splits[index] = 2;
        slotCount += 1;
      }
      if (row.type === 'stack' && row.shown >= 4 && slotCount < 4) {
        const parts = Math.min(3, Math.ceil(row.shown / 2), 4 - slotCount + 1);
        if (parts > 1) {
          splits[index] = parts;
          slotCount += parts - 1;
        }
      }
    });

    const slots = [];
    rows.forEach((row, index) => {
      const parts = splits[index];
      const base = Math.floor(row.shown / parts);
      const extra = row.shown % parts;
      for (let part = 0; part < parts; part += 1) {
        const count = base + (part < extra ? 1 : 0);
        if (count > 0) slots.push({ ...row, count, part });
      }
    });

    const factor = slotCount >= 4 ? 0.65 : slotCount === 3 ? 0.80 : 1;
    const boxBaseW = Math.min(W * 0.84, H * 0.88) * factor;
    const noteMaxW = Math.min(W * 0.60, 224);
    const hasNotes = slots.some((slot) => slot.type !== 'box');
    // Measured from the rendered 3D models: height and above-baseline share per type.
    const HEIGHT = { box: 1.03, bundle: 1.275, stack: 0.774, remainder: 0.615 };
    const ABOVE = { box: 0.72, bundle: 0.734, stack: 0.523, remainder: 0.511 };
    const rowGapY = 6;

    const slotCap = (slot) => {
      const rowGap = slot.type === 'box' ? gap : noteGap;
      return (avail - rowGap * (slot.count - 1)) / slot.count;
    };

    const layoutAt = (noteW) => {
      const noteSlots = slots.filter((slot) => slot.type !== 'box');
      const boxSlots = slots.filter((slot) => slot.type === 'box');
      const noteCap = noteSlots.reduce((min, slot) => Math.min(min, slotCap(slot)), noteMaxW);
      const noteBase = hasNotes ? Math.min(noteW, noteCap) : 0;
      const boxSlotW = boxSlots.length
        ? Math.min(
          ...boxSlots.map((slot) => slotCap(slot)),
          hasNotes ? noteBase * 1.25 / PACKAGE_BOX_DRAW_SCALE : boxBaseW
        )
        : 0;
      const boxDrawn = boxSlotW * PACKAGE_BOX_DRAW_SCALE;

      const entries = slots.map((slot) => {
        if (slot.type === 'box') {
          const slotW = boxSlotW;
          const drawn = boxDrawn;
          return { slot, slotW, drawn, rowGap: gap, height: drawn * HEIGHT.box, above: ABOVE.box };
        }
        return {
          slot,
          slotW: noteBase,
          drawn: noteBase,
          rowGap: noteGap,
          height: noteBase * HEIGHT[slot.type],
          above: ABOVE[slot.type]
        };
      });

      const total = entries.reduce((sum, entry) => sum + entry.height, 0)
        + rowGapY * Math.max(0, entries.length - 1);
      return { entries, total };
    };

    let noteW = noteMaxW;
    let layout = layoutAt(noteW);
    if (layout.total > H - 20) {
      let lo = 0;
      let hi = noteMaxW;
      for (let i = 0; i < 20; i += 1) {
        const mid = (lo + hi) / 2;
        if (layoutAt(mid).total > H - 20) hi = mid;
        else lo = mid;
      }
      noteW = lo;
      layout = layoutAt(noteW);
    }

    let cursor = (H - layout.total) / 2;
    if (layout.entries.length === 1) {
      cursor = Math.max(4, cursor - H * 0.05);
    }
    layout.entries.forEach((entry) => {
      const baseY = cursor + entry.height * entry.above;
      const total = entry.slotW * entry.slot.count + entry.rowGap * (entry.slot.count - 1);
      const firstX = W / 2 - total / 2 + entry.slotW / 2;

      for (let i = 0; i < entry.slot.count; i += 1) {
        const x = firstX + i * (entry.slotW + entry.rowGap);
        if (entry.slot.type === 'box') buildBoxItem(x, baseY, entry.drawn);
        else if (entry.slot.type === 'bundle') buildBundleItem(x, baseY, entry.drawn);
        else if (entry.slot.type === 'stack') buildStackItem(x, baseY, entry.drawn);
        else buildRemainderItem(x, baseY, entry.drawn);
      }
      cursor += entry.height + rowGapY;
    });
  }

  function buildLevel1() {
    scene3d.replaceChildren();
    if (!state.groups.length) return;

    const W = stage.clientWidth;
    const H = stage.clientHeight;
    if (!W || !H) return;

    if (state.packages) {
      state.basePitch = PACKAGE_TILT;
      applyScenePitch();
      buildLevel1Packages(W, H);
      return;
    }

    state.basePitch = PACKAGE_TILT;
    applyScenePitch();
    const maxThickness = Math.max(58, H * 0.40);
    const maxNoteW = Math.min(W * 0.60, 224);
    const layout = fitPileLayout(
      state.count,
      W * 0.92,
      maxNoteW,
      maxThickness,
      state.groups[0].denom.phys
    );
    const pileCount = layout.piles;
    const targetW = layout.width;
    const gap = layout.gap;
    state.level1Piles = pileCount;

    const scale = targetW / state.groups[0].denom.baseW;
    const perNote = targetW * NOTE_THICKNESS_MM / state.groups[0].denom.phys;
    const piles = splitGroupsForPiles(state.groups, pileCount);
    // Match the single-row package anchor so 9,999 and 10,000 do not jump.
    const anchorH = targetW * 0.774;
    const anchorCursor = Math.max(4, (H - anchorH) / 2 - H * 0.05);
    const stackTop = anchorCursor + anchorH * 0.523;

    piles.forEach((pileGroups, index) => {
      if (!pileGroups.length) return;
      const stack = make('div', 'stack3d');
      stack.style.left = `${W / 2 + (index - (pileCount - 1) / 2) * (targetW + gap)}px`;
      stack.style.top = `${stackTop}px`;

      const first = pileGroups[0].denom;
      stack.appendChild(createStackBase(first.baseW * scale, first.baseH * scale));

      let z = 0;
      pileGroups.forEach((group) => {
        const w = group.denom.baseW * scale;
        const d = group.denom.baseH * scale;
        const t = Math.max(0.8, group.count * perNote);
        stack.appendChild(createLayer(group.denom, w, d, t, z, perNote));
        z += t;
      });

      scene3d.appendChild(stack);
    });
  }

  function buildLevel2() {
    scene3d.replaceChildren();
    const groups = state.groups;
    if (!groups.length) return;

    state.basePitch = pitchForCount(state.count);
    applyScenePitch();
    const W = stage.clientWidth;
    const H = stage.clientHeight;
    if (!W || !H) return;

    const cols = groups.length <= 3 ? groups.length : (groups.length === 4 ? 2 : 3);
    const rows = Math.ceil(groups.length / cols);
    const padX = 10;
    const gapX = 6;
    const cellW = (W - padX * 2 - gapX * (cols - 1)) / cols;
    const rowBase = rows === 1 ? 0.56 : (rows === 2 ? 0.30 : 0.26);
    const rowGap = rows === 1 ? 0 : (rows === 2 ? 0.36 : 0.20);

    groups.forEach((group, index) => {
      const row = Math.floor(index / cols);
      const col = index % cols;
      const rowCount = Math.min(cols, groups.length - row * cols);
      const rowOffset = (cols - rowCount) * (cellW + gapX) / 2;
      const cellLeft = padX + rowOffset + col * (cellW + gapX);
      const cellCenter = cellLeft + cellW / 2;
      const baseY = H * (rowBase + row * rowGap);

      const noteW = Math.min(cellW * 0.72, 92) * (group.denom.phys / 155);
      const scale = noteW / group.denom.baseW;
      const d = group.denom.baseH * scale;
      const topPad = Math.max(32, H * 0.10);
      const maxThickness = Math.max(8, (baseY - topPad - d * 0.58) / 0.90);
      const layout = fitPileLayout(
        group.count,
        cellW * 0.94,
        noteW,
        maxThickness,
        group.denom.phys
      );
      const pileCount = layout.piles;
      const perPile = Math.ceil(group.count / pileCount);
      const perNote = layout.width * NOTE_THICKNESS_MM / group.denom.phys;
      const subStep = perPile * perNote > maxThickness
        ? Math.max(0.01, maxThickness / perPile)
        : perNote;
      const pileGap = layout.gap;
      const subW = layout.width;
      const subD = group.denom.baseH * (subW / group.denom.baseW);

      for (let pile = 0; pile < pileCount; pile += 1) {
        const count = Math.floor(group.count / pileCount) + (pile < group.count % pileCount ? 1 : 0);
        if (!count) continue;
        const t = Math.max(0.8, count * subStep);
        const stack = make('div', 'stack3d');
        stack.style.left = `${cellCenter + (pile - (pileCount - 1) / 2) * (subW + pileGap)}px`;
        stack.style.top = `${baseY}px`;
        stack.appendChild(createStackBase(subW, subD));
        stack.appendChild(createLayer(group.denom, subW, subD, t, 0, subStep));
        scene3d.appendChild(stack);
      }

    });
  }

  function setYaw(value) {
    state.yaw = value;
    scene3d.style.setProperty('--yaw', `${value}deg`);
  }

  function prefersReducedMotion() {
    return window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  }

  function stopMomentum() {
    if (state.momentumRaf) {
      cancelAnimationFrame(state.momentumRaf);
      state.momentumRaf = 0;
    }
  }

  function startMomentum(velocity) {
    stopMomentum();
    if (!state.entryOpen || state.mode === 3 || prefersReducedMotion()) return;

    let speed = Math.max(-760, Math.min(760, velocity));
    if (Math.abs(speed) < 24) return;

    let last = performance.now();
    const step = (now) => {
      if (!state.entryOpen || state.mode === 3) {
        state.momentumRaf = 0;
        return;
      }
      const dt = Math.min(0.05, Math.max(0.008, (now - last) / 1000));
      last = now;
      setYaw(state.yaw + speed * dt);
      speed *= Math.exp(-4.6 * dt);
      if (Math.abs(speed) > 5) {
        state.momentumRaf = requestAnimationFrame(step);
      } else {
        state.momentumRaf = 0;
      }
    };

    state.momentumRaf = requestAnimationFrame(step);
  }

  /* -------------------------------------------------------
     2D 全展开网格
     ------------------------------------------------------- */
  function buildGrid2D() {
    grid2d.replaceChildren();
    state.virtualGrid = null;
    const groups = state.groups;
    if (!groups.length) return;

    if (state.count > GRID_VIRTUAL_THRESHOLD) {
      buildVirtualGrid();
      return;
    }

    const W = stage.clientWidth;
    const H = stage.clientHeight;
    const padX = 12;
    const padTop = 8;
    const gapX = 5;
    const gapY = 5;
    const minW = 52;
    const cols = Math.max(4, Math.min(6, Math.floor((W - padX * 2 + gapX) / (minW + gapX))));
    const cellW = (W - padX * 2 - gapX * (cols - 1)) / cols;
    const rowH = cellW / 2;
    const rows = Math.ceil(state.count / cols);
    const total = padTop * 2 + rows * rowH + Math.max(0, rows - 1) * gapY;
    const offsetY = Math.max(0, (H - total) / 2);
    const gridTop = padTop + offsetY;
    const fragment = document.createDocumentFragment();
    let index = 0;

    groups.forEach((group) => {
      const scale = cellW / group.denom.baseW;
      const noteH = group.denom.baseH * scale;
      for (let n = 0; n < group.count; n += 1, index += 1) {
        const row = Math.floor(index / cols);
        const col = index % cols;
        const el = make('div', 'note');
        el.style.width = `${group.denom.baseW}px`;
        el.style.height = `${group.denom.baseH}px`;
        const inner = make('div', 'note-inner');
        const img = document.createElement('img');
        img.src = group.denom.img;
        img.alt = '';
        img.draggable = false;
        img.decoding = 'async';
        inner.appendChild(img);
        el.appendChild(inner);

        const x = padX + col * (cellW + gapX);
        const y = gridTop + row * (rowH + gapY) + (rowH - noteH) / 2;
        el.style.transform = `translate3d(${x}px, ${y}px, 0) scale(${scale})`;
        el.style.opacity = '1';
        el.style.zIndex = String(10 + index);
        fragment.appendChild(el);
      }
    });

    grid2d.appendChild(fragment);

    const contentH = Math.max(H, total);
    stageCanvas.style.height = `${contentH}px`;
    grid2d.style.height = `${contentH}px`;
    stage.scrollTop = 0;
  }

  function buildVirtualGrid() {
    const W = stage.clientWidth;
    const H = stage.clientHeight;
    if (!W || !H) return;

    const padX = 12;
    const padTop = 8;
    const gapX = 5;
    const gapY = 5;
    const minW = 52;
    const cols = Math.max(4, Math.min(6, Math.floor((W - padX * 2 + gapX) / (minW + gapX))));
    const cellW = (W - padX * 2 - gapX * (cols - 1)) / cols;
    const rowH = cellW / 2;
    const rows = Math.ceil(state.count / cols);
    const total = padTop * 2 + rows * rowH + Math.max(0, rows - 1) * gapY;
    const offsetY = Math.max(0, (H - total) / 2);
    const gridTop = padTop + offsetY;

    let start = 0;
    const segments = state.groups.map((group) => {
      const segment = { denom: group.denom, start, count: group.count };
      start += group.count;
      return segment;
    });

    const contentH = Math.max(H, total);
    stageCanvas.style.height = `${contentH}px`;
    grid2d.style.height = `${contentH}px`;
    state.virtualGrid = {
      segments,
      totalNotes: state.count,
      rows,
      gridTop,
      cols,
      cellW,
      rowH,
      gapX,
      gapY,
      padX,
      lastKey: ''
    };
    stage.scrollTop = 0;
    renderVirtualGrid();
  }

  function renderVirtualGrid() {
    const view = state.virtualGrid;
    if (!view || state.mode !== 3) return;

    const overscan = view.rowH * 3 + 60;
    const top = Math.max(0, stage.scrollTop - overscan);
    const bottom = stage.scrollTop + stage.clientHeight + overscan;
    const key = `${Math.floor(top / (view.rowH + view.gapY))}:${Math.floor(bottom / (view.rowH + view.gapY))}`;
    if (key === view.lastKey) return;
    view.lastKey = key;

    const firstRow = Math.max(0, Math.floor((top - view.gridTop) / (view.rowH + view.gapY)) - 1);
    const lastRow = Math.min(view.rows - 1, Math.floor((bottom - view.gridTop) / (view.rowH + view.gapY)) + 1);
    if (lastRow < firstRow) {
      grid2d.replaceChildren();
      return;
    }

    const startIndex = firstRow * view.cols;
    const endIndex = Math.min(view.totalNotes, (lastRow + 1) * view.cols);
    let segIndex = 0;
    while (segIndex < view.segments.length
      && startIndex >= view.segments[segIndex].start + view.segments[segIndex].count) {
      segIndex += 1;
    }

    const fragment = document.createDocumentFragment();
    for (let index = startIndex; index < endIndex; index += 1) {
      let segment = view.segments[segIndex];
      while (index >= segment.start + segment.count) {
        segIndex += 1;
        segment = view.segments[segIndex];
      }
      const row = Math.floor(index / view.cols);
      const col = index % view.cols;
      const scale = view.cellW / segment.denom.baseW;
      const noteH = segment.denom.baseH * scale;

      const el = make('div', 'note');
      el.style.width = `${segment.denom.baseW}px`;
      el.style.height = `${segment.denom.baseH}px`;
      const inner = make('div', 'note-inner');
      const img = document.createElement('img');
      img.src = segment.denom.img;
      img.alt = '';
      img.draggable = false;
      img.decoding = 'async';
      inner.appendChild(img);
      el.appendChild(inner);

      const x = view.padX + col * (view.cellW + view.gapX);
      const y = view.gridTop + row * (view.rowH + view.gapY) + (view.rowH - noteH) / 2;
      el.style.transform = `translate3d(${x}px, ${y}px, 0) scale(${scale})`;
      el.style.opacity = '1';
      el.style.zIndex = String(10 + index);
      fragment.appendChild(el);
    }

    grid2d.replaceChildren(fragment);
  }

  /* -------------------------------------------------------
     舞台状态与模式
     ------------------------------------------------------- */
  function scheduleStageUpdate() {
    cancelAnimationFrame(state.stageRaf);
    state.stageRaf = requestAnimationFrame(updateStageForAmount);
  }

  function updateStageForAmount() {
    const cents = previewCents();
    const mode = state.mode || 1;
    const { groups } = breakdown(cents);
    const count = totalNotes(groups);
    const kinds = groups.length;

    state.groups = groups;
    state.count = count;
    state.kinds = kinds;
    state.packages = cents >= 1000000 ? packageBreakdown(cents) : null;
    updateScenePitch();

    if (!groups.length) {
      clearStageVisuals();
      stageEmpty.classList.remove('is-hidden');
      stage.classList.add('is-empty');
      saveBtn.disabled = true;
      stage.setAttribute('aria-label', '金额为零，未生成现钞');
      breakdownText.textContent = '';
      stateLive.textContent = '';
      return;
    }

    stageEmpty.classList.add('is-hidden');
    stage.classList.remove('is-empty');
    saveBtn.disabled = false;
    breakdownText.textContent = `共 ${count} 张：${groups.map((g) => `${g.denom.name} ${g.count} 张`).join('；')}。`;

    setMode(mode, { force: true, fromAmount: true });
  }

  function cancelFocusPull() {
    state.focusPullId += 1;
    document.querySelectorAll('.focus-pull-layer').forEach((node) => node.remove());
    stageCanvas.classList.remove('is-focus-in');
    stageCanvas.style.transformOrigin = '';
  }

  function playFocusPull(nextMode) {
    cancelFocusPull();
    if (prefersReducedMotion()) return;
    const id = state.focusPullId;
    const rect = stage.getBoundingClientRect();
    const layer = document.createElement('div');
    layer.className = 'focus-pull-layer';
    layer.setAttribute('aria-hidden', 'true');
    layer.style.left = `${rect.left}px`;
    layer.style.top = `${rect.top}px`;
    layer.style.width = `${rect.width}px`;
    layer.style.height = `${rect.height}px`;
    layer.style.borderRadius = getComputedStyle(stage).borderRadius;

    const clone = stageCanvas.cloneNode(true);
    clone.removeAttribute('id');
    clone.querySelectorAll('[id]').forEach((node) => node.removeAttribute('id'));
    clone.classList.remove('is-focus-in');
    clone.classList.add('is-focus-out');
    clone.style.top = `${-stage.scrollTop}px`;
    clone.style.height = stageCanvas.style.height || '100%';
    clone.style.transformOrigin = `50% ${stage.scrollTop + stage.clientHeight * 0.48}px`;
    layer.appendChild(clone);
    document.body.appendChild(layer);

    stageCanvas.style.transformOrigin = nextMode === 3
      ? `50% ${stage.clientHeight * 0.48}px`
      : '50% 48%';
    stageCanvas.classList.add('is-focus-in');

    window.setTimeout(() => {
      if (id !== state.focusPullId) return;
      layer.remove();
      stageCanvas.classList.remove('is-focus-in');
      stageCanvas.style.transformOrigin = '';
    }, 320);
  }

  function setMode(mode, opts = {}) {
    if (!state.groups.length) return;
    stopMomentum();
    if (state.mode === mode && !opts.force) return;
    const prevMode = state.mode;
    if (prevMode !== mode) playFocusPull(mode);
    else cancelFocusPull();
    state.mode = mode;
    stage.dataset.mode = String(mode);

    stage.classList.toggle('is-empty', false);

    if (mode === 1 || mode === 2) {
      stage.classList.remove('is-scroll');
      stage.scrollTop = 0;
      stageCanvas.style.height = '100%';
      grid2d.style.height = '100%';
      grid2d.classList.add('is-hidden');
      scene3d.classList.remove('is-hidden');

      state.virtualGrid = null;
      if (mode === 1) buildLevel1();
      else buildLevel2();
    } else {
      scene3d.classList.add('is-hidden');
      grid2d.classList.remove('is-hidden');
      stage.classList.add('is-scroll');
      stageCanvas.style.height = '100%';
      buildGrid2D();
    }

    updateStageCopy(mode);

    if (!opts.silent) {
      vibrate(7);
    }
  }

  function updateStageCopy(mode) {
    const count = state.count;
    const kinds = state.kinds;
    const piles = mode === 1 ? state.level1Piles : 1;
    const packaged = mode === 1 && state.packages;

    let label;
    if (mode === 1 && packaged) {
      const p = state.packages;
      const pieces = [];
      if (p.boxes) pieces.push(`${p.boxes} 箱，共 ${p.boxes * 100} 万元`);
      if (p.bundles) pieces.push(`${p.bundles} 捆，共 ${p.bundles * 10} 万元`);
      if (p.stacks) pieces.push(`${p.stacks} 叠，共 ${p.stacks} 万元`);
      const loose = p.remainderCents > 0
        ? `，另有 ${formatCompact(p.remainderCents)} 元散钞叠在一起`
        : '';
      label = `现金共 ${count} 张，${pieces.join('，')}${loose}。按 100 万元装箱、10 万元成捆、1 万元成叠摆放。可拖动或按方向键旋转，轻点进入面额分组。`;
    } else if (mode === 1) {
      const splitText = piles > 1 ? `分成 ${piles} 叠，` : '';
      label = `现金共 ${count} 张，${kinds} 种面额，${splitText}按面额从大到小叠放。可拖动或按方向键旋转，轻点分开。`;
    } else if (mode === 2) {
      label = `现金已按面额分组，从大到小排列。可拖动或按方向键旋转，再轻点全部摊开。`;
    } else {
      const scrollable = stage.scrollHeight > stage.clientHeight + 4;
      label = scrollable
        ? `全部 ${count} 张钞票已按面额展开，可上下滑动查看。轻点收回。`
        : `全部 ${count} 张钞票已按面额展开。轻点收回。`;
    }

    stage.setAttribute('aria-label', label);
    stateLive.textContent = label;
  }

  function clearStageVisuals() {
    stopMomentum();
    cancelFocusPull();
    state.virtualGrid = null;
    if (state.gridRaf) {
      cancelAnimationFrame(state.gridRaf);
      state.gridRaf = 0;
    }
    scene3d.replaceChildren();
    grid2d.replaceChildren();
    grid2d.classList.add('is-hidden');
    scene3d.classList.add('is-hidden');
    stage.classList.remove('is-scroll');
    stage.scrollTop = 0;
    stageCanvas.style.height = '100%';
  }

  function cycleMode() {
    if (!state.groups.length || previewCents() <= 0) return;
    const next = state.mode === 1 ? 2 : (state.mode === 2 ? 3 : 1);
    setMode(next);
  }

  /* -------------------------------------------------------
     记账页导航
     ------------------------------------------------------- */
  function openDateDialog() {
    if (!state.entryOpen) return;
    dateInput.value = state.entryIso;
    timeInput.value = state.entryTime;
    if (!dateDialog.open) dateDialog.showModal();
    window.requestAnimationFrame(() => dateInput.focus({ preventScroll: true }));
  }

  function dismissDateDialog() {
    if (dateDialog.open) dateDialog.close();
    if (state.entryOpen) {
      entryDate.focus({ preventScroll: true });
    }
  }

  function applyDateDialog() {
    if (!dateInput.reportValidity()) return;
    if (!timeInput.reportValidity()) return;
    state.entryIso = dateInput.value;
    state.entryTime = timeInput.value;
    syncEntryDate();
    dismissDateDialog();
  }

  function resetEntry(bill = null) {
    if (dateDialog.open) dateDialog.close();
    const stamp = new Date();

    state.editingId = bill ? bill.id : null;
    state.amountStr = bill ? rawFromCents(bill.cents) : '';
    state.type = bill && bill.type === 'income' ? 'income' : 'expense';
    state.calc = { left: null, op: null, fresh: false };
    state.groups = [];
    state.count = 0;
    state.kinds = 0;
    state.packages = null;
    state.mode = 1;
    state.level1Piles = 1;
    stage.dataset.mode = '1';
    state.yaw = -30;
    setYaw(-30);
    state.pitchOffset = 0;
    state.basePitch = PACKAGE_TILT;
    applyScenePitch();
    resetOpCycle();

    state.entryIso = bill && bill.iso ? bill.iso : isoDate(stamp);
    state.entryTime = bill && bill.time ? bill.time : timeLabel(stamp);
    noteInput.value = bill ? (bill.note || '') : '';
    entryHeading.textContent = bill ? '编辑这笔现金账' : '记一笔现金账';
    saveBtn.setAttribute('aria-label', bill ? '保存修改' : '保存这笔账');
    syncEntryDate();

    renderAmount();
    updateExpression();
    updateTypeUI();
    showHint('');
    saveBtn.textContent = '保存';
    clearStageVisuals();
    breakdownText.textContent = '';
    stateLive.textContent = '';
    stage.classList.remove('is-scroll');
    stage.scrollTop = 0;

    if (bill) {
      stageEmpty.classList.add('is-hidden');
      stage.classList.remove('is-empty');
      saveBtn.disabled = false;
      updateStageForAmount();
    } else {
      stageEmpty.classList.remove('is-hidden');
      stage.classList.add('is-empty');
      stage.setAttribute('aria-label', '金额为零，未生成现钞');
      saveBtn.disabled = true;
    }
  }

  function openEntry(bill = null) {
    if (state.entryOpen) return;
    state.entryOpen = true;
    state.returnBillId = bill ? bill.id : null;

    app.classList.add('is-entry');
    billsView.setAttribute('aria-hidden', 'true');
    billsView.inert = true;
    entryView.removeAttribute('aria-hidden');
    entryView.inert = false;

    resetEntry(bill || null);

    window.requestAnimationFrame(() => {
      entryHeading.focus({ preventScroll: true });
    });
  }

  function closeEntry(options = {}) {
    if (!state.entryOpen || writing) return;
    const focusBillId = state.editingId || state.returnBillId;

    state.entryOpen = false;
    if (dateDialog.open) dateDialog.close();
    app.classList.remove('is-entry');
    entryView.setAttribute('aria-hidden', 'true');
    entryView.inert = true;
    billsView.removeAttribute('aria-hidden');
    billsView.inert = false;

    window.setTimeout(() => {
      const row = focusBillId
        ? billList.querySelector(`.bill-row[data-bill-id="${focusBillId}"]`)
        : null;
      (row || addBillBtn).focus({ preventScroll: true });
    }, 220);

    if (options.saved) {
      billsScroll.scrollTop = 0;
    }
    resetEntry();
    state.returnBillId = null;
  }

  function updateTypeUI() {
    typeSeg.classList.toggle('is-income', state.type === 'income');
    typeSeg.querySelectorAll('.seg-option').forEach((option) => {
      const active = option.dataset.type === state.type;
      option.classList.toggle('is-active', active);
      option.setAttribute('aria-pressed', String(active));
    });
  }

  async function saveEntry() {
    if (!state.entryOpen || writing) return;
    const cents = finalizeCents();
    if (cents === null) return;
    if (cents <= 0) {
      showHint('先输入金额');
      return;
    }

    const { groups, remainder } = breakdown(cents);
    if (!groups.length || remainder !== 0) {
      showHint('这个金额暂时无法组合');
      return;
    }

    const stampIso = state.entryIso || isoDate(new Date());
    const stampTime = state.entryTime || timeLabel(new Date());
    const stamp = dateFromParts(stampIso, stampTime);
    const fields = {
      cents,
      type: state.type,
      note: noteInput.value.trim(),
      iso: stampIso,
      time: stampTime,
      createdAt: stamp.getTime(),
      count: totalNotes(groups),
      kinds: groups.length,
      groups: groups.map((g) => ({ key: g.denom.key, count: g.count }))
    };

    let bill = null;
    let updated = false;
    let nextBills = [];
    if (state.editingId) {
      const index = state.bills.findIndex((item) => item.id === state.editingId);
      if (index !== -1) {
        const previous = state.bills[index];
        const createdAt = previous.iso === stampIso && previous.time === stampTime
          ? (previous.createdAt || stamp.getTime())
          : stamp.getTime();
        bill = { ...previous, ...fields, id: previous.id, createdAt };
        nextBills = state.bills.map((item, itemIndex) => itemIndex === index ? bill : item);
        updated = true;
      }
    }

    if (!bill) {
      bill = {
        id: `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 5)}`,
        ...fields
      };
      nextBills = [bill, ...state.bills];
    }

    if (!ensureAccountForWrite('save')) return;

    writing = true;
    saveBtn.disabled = true;
    saveBtn.textContent = '保存中';
    let result = { ok: false, code: 'network' };
    try {
      result = await saveBills(nextBills, Date.now());
    } catch (err) {}
    writing = false;
    saveBtn.textContent = '保存';

    if (!result.ok) {
      saveBtn.disabled = previewCents() <= 0;
      if (result.code === 'auth') {
        showHint('登录已过期，请重新登录');
        openSettings();
      } else if (result.code === 'not-ready') {
        showHint('账号数据还没加载好');
        openSettings();
      } else {
        showHint('保存失败，请检查网络后重试');
      }
      return;
    }

    state.bills = nextBills;
    state.lastBillId = bill.id;
    state.billsMonth = new Date(stamp.getFullYear(), stamp.getMonth(), 1);
    renderBills();

    billsLive.textContent = `${updated ? '已更新' : '已保存'}一笔${bill.type === 'expense' ? '支出' : '收入'}，${formatMoney(bill.cents)} 元，共 ${bill.count} 张现钞。`;
    closeEntry({ saved: true });

    window.setTimeout(() => {
      if (state.lastBillId === bill.id) {
        const row = billList.querySelector('.bill-row.is-new');
        if (row) row.classList.remove('is-new');
      }
    }, 1200);
  }

  /* -------------------------------------------------------
     事件
     ------------------------------------------------------- */
  addBillBtn.addEventListener('click', () => openEntry());

  let suppressBillClick = false;
  let billDrag = null;

  billList.addEventListener('click', (event) => {
    if (suppressBillClick) {
      suppressBillClick = false;
      return;
    }
    const btn = event.target.closest('[data-add-bill]');
    if (btn) {
      closeBillSwipes();
      openEntry();
      return;
    }
    const remove = event.target.closest('[data-delete-bill]');
    if (remove) {
      deleteBill(remove.dataset.deleteBill);
      return;
    }
    const row = event.target.closest('.bill-row[data-bill-id]');
    if (!row) return;
    const swipe = row.closest('.bill-swipe');
    if (swipe && swipe.classList.contains('is-open')) {
      closeBillSwipes();
      return;
    }
    closeBillSwipes();
    const bill = state.bills.find((item) => item.id === row.dataset.billId);
    if (bill) openEntry(bill);
  });

  billList.addEventListener('pointerdown', (event) => {
    if (!event.isPrimary || event.button !== 0) return;
    const swipe = event.target.closest('.bill-swipe');
    if (!swipe || event.target.closest('[data-delete-bill]')) return;
    const row = swipe.querySelector('.bill-row');
    if (!row) return;
    closeBillSwipes(swipe);
    billDrag = {
      pointerId: event.pointerId,
      swipe,
      row,
      startX: event.clientX,
      startY: event.clientY,
      startOffset: swipe.classList.contains('is-open') ? DELETE_REVEAL : 0,
      offset: swipe.classList.contains('is-open') ? DELETE_REVEAL : 0,
      active: false
    };
    swipe.style.setProperty('--delete-progress', String(deleteAppearProgress(billDrag.offset)));
  });

  billList.addEventListener('pointermove', (event) => {
    if (!billDrag || event.pointerId !== billDrag.pointerId) return;
    const dx = event.clientX - billDrag.startX;
    const dy = event.clientY - billDrag.startY;
    if (!billDrag.active) {
      if (Math.abs(dx) < 8 && Math.abs(dy) < 8) return;
      if (Math.abs(dy) >= Math.abs(dx)) {
        billDrag = null;
        return;
      }
      billDrag.active = true;
      billDrag.swipe.classList.add('is-dragging');
      try {
        billList.setPointerCapture(event.pointerId);
      } catch (err) {}
    }
    if (event.cancelable) event.preventDefault();
    const offset = Math.max(0, Math.min(DELETE_REVEAL, billDrag.startOffset - dx));
    billDrag.offset = offset;
    billDrag.swipe.style.setProperty('--reveal', `${offset}px`);
    billDrag.swipe.style.setProperty('--delete-progress', String(deleteAppearProgress(offset)));
  }, { passive: false });

  function finishBillDrag(event) {
    if (!billDrag || event.pointerId !== billDrag.pointerId) return;
    const drag = billDrag;
    billDrag = null;
    try {
      billList.releasePointerCapture(event.pointerId);
    } catch (err) {}
    if (!drag.active) return;
    suppressBillClick = true;
    window.setTimeout(() => {
      suppressBillClick = false;
    }, 320);
    const open = drag.offset >= DELETE_REVEAL * 0.55;
    drag.swipe.classList.remove('is-dragging');
    drag.swipe.classList.toggle('is-open', open);
    drag.swipe.style.removeProperty('--reveal');
    drag.swipe.style.removeProperty('--delete-progress');
  }

  billList.addEventListener('pointerup', finishBillDrag);
  billList.addEventListener('pointercancel', finishBillDrag);

  billList.addEventListener('focusin', (event) => {
    const swipe = event.target.closest('.bill-swipe');
    if (!swipe || !event.target.closest('[data-delete-bill]')) return;
    closeBillSwipes(swipe);
    swipe.classList.add('is-open');
  });

  billsScroll.addEventListener('pointerdown', (event) => {
    if (!event.target.closest('.bill-swipe')) closeBillSwipes();
  });

  closeEntryBtn.addEventListener('click', () => closeEntry());

  prevMonthBtn.addEventListener('click', () => shiftBillsMonth(-1));
  nextMonthBtn.addEventListener('click', () => shiftBillsMonth(1));
  if (sortToggle) {
    sortToggle.addEventListener('click', () => {
      state.sortDesc = !state.sortDesc;
      billsScroll.scrollTop = 0;
      renderBills();
      billsLive.textContent = state.sortDesc ? '已按时间倒序排列' : '已按时间正序排列';
      vibrate(5);
    });
  }
  settingsBtn.addEventListener('click', openSettings);
  settingsCloseBtn.addEventListener('click', () => settingsDialog.close());
  settingsBackBtn.addEventListener('click', () => {
    showSettingsMain();
    appearanceBtn.focus({ preventScroll: true });
  });
  appearanceBtn.addEventListener('click', showAppearanceView);
  settingsDialog.addEventListener('click', (event) => {
    if (event.target === settingsDialog) settingsDialog.close();
  });

  accountForm.addEventListener('submit', handleAccountLogin);
  accountLogoutBtn.addEventListener('click', handleAccountLogout);
  themeOptions.forEach((option) => {
    option.addEventListener('click', () => {
      const mode = option.dataset.themeMode;
      if (!Object.prototype.hasOwnProperty.call(THEME_NAMES, mode)) return;
      applyTheme(mode, true);
      billsLive.textContent = `外观已切换为${THEME_NAMES[mode]}`;
    });
  });
  if (themeMedia) {
    const onSystemThemeChange = () => {
      if (themeMode === 'system') applyTheme('system', false);
    };
    if (themeMedia.addEventListener) themeMedia.addEventListener('change', onSystemThemeChange);
    else if (themeMedia.addListener) themeMedia.addListener(onSystemThemeChange);
  }
  accountImportBtn.addEventListener('click', () => accountImportFile.click());
  accountExportBtn.addEventListener('click', exportBillsCsv);
  accountImportFile.addEventListener('change', handleAccountImport);

  entryDate.addEventListener('click', openDateDialog);
  dateApplyBtn.addEventListener('click', applyDateDialog);
  dateCancelBtn.addEventListener('click', dismissDateDialog);
  dateDialog.addEventListener('click', (event) => {
    if (event.target === dateDialog) dismissDateDialog();
  });
  dateDialog.addEventListener('keydown', (event) => {
    if (event.key === 'Enter' && event.target instanceof HTMLInputElement) {
      event.preventDefault();
      applyDateDialog();
    }
  });

  typeSeg.addEventListener('click', (event) => {
    const btn = event.target.closest('.seg-option');
    if (!btn) return;
    state.type = btn.dataset.type;
    updateTypeUI();
    vibrate(5);
  });

  opBtn.addEventListener('click', pressOperator);
  equalsBtn.addEventListener('click', pressEquals);
  saveBtn.addEventListener('click', saveEntry);
  $('keypad').addEventListener('click', (event) => {
    const btn = event.target.closest('button[data-key]');
    if (!btn) return;
    if (btn === backspaceBtn && state.suppressBackspaceClick) {
      state.suppressBackspaceClick = false;
      return;
    }
    pressKey(btn.dataset.key);
  });

  let backspaceTimer = 0;
  backspaceBtn.addEventListener('pointerdown', (event) => {
    if (!event.isPrimary) return;
    window.clearTimeout(backspaceTimer);
    backspaceTimer = window.setTimeout(() => {
      state.suppressBackspaceClick = true;
      clearAmount();
      vibrate(12);
      window.setTimeout(() => {
        state.suppressBackspaceClick = false;
      }, 1400);
    }, 620);
  });
  ['pointerup', 'pointercancel', 'pointerleave'].forEach((name) => {
    backspaceBtn.addEventListener(name, () => window.clearTimeout(backspaceTimer));
  });

  stage.addEventListener('scroll', () => {
    if (!state.virtualGrid || state.mode !== 3) return;
    cancelAnimationFrame(state.gridRaf);
    state.gridRaf = requestAnimationFrame(renderVirtualGrid);
  });

  /* Stage: drag to rotate + tap to expand */
  let stagePointer = null;
  let dragged = false;

  stage.addEventListener('pointerdown', (event) => {
    if (!event.isPrimary || !state.groups.length) return;
    stopMomentum();
    const visualHeight = state.mode === 3 ? 0 : sceneVisualHeight();
    stagePointer = {
      x: event.clientX,
      y: event.clientY,
      scroll: stage.scrollTop,
      yaw: state.yaw,
      pitch: state.pitchOffset,
      // Shorter models need more angle per pixel for the same visible travel.
      pitchScale: visualHeight ? Math.max(1, Math.min(2, PITCH_REF_HEIGHT / visualHeight)) : 1
    };
    dragged = false;
    state.dragVelocity = 0;
    state.lastMoveTime = performance.now();
    if (state.mode !== 3) {
      try {
        stage.setPointerCapture(event.pointerId);
      } catch (err) {}
    }
  });

  stage.addEventListener('pointermove', (event) => {
    if (!stagePointer || state.mode === 3) return;
    const dx = event.clientX - stagePointer.x;
    const dy = event.clientY - stagePointer.y;
    const horizontal = Math.abs(dx) >= 4;
    const vertical = Math.abs(dy) >= 4;
    if (!horizontal && !vertical && !dragged) return;

    const now = performance.now();
    if (horizontal) {
      const nextYaw = stagePointer.yaw - dx * 0.55;
      const deltaYaw = nextYaw - state.yaw;
      const dt = Math.max(8, now - state.lastMoveTime);
      const instant = (deltaYaw / dt) * 1000;

      state.dragVelocity = state.dragVelocity * 0.62 + instant * 0.38;
      state.lastMoveTime = now;
      setYaw(nextYaw);
    }

    if (vertical) {
      const nextPitch = Math.max(
        -PITCH_LIMIT,
        Math.min(PITCH_LIMIT, stagePointer.pitch - dy * PITCH_PER_PX * stagePointer.pitchScale)
      );
      if (nextPitch !== state.pitchOffset) {
        state.pitchOffset = nextPitch;
        applyScenePitch();
      }
    }

    dragged = true;
  });

  stage.addEventListener('pointerup', (event) => {
    if (!stagePointer) return;
    const mode = state.mode;
    const dx = Math.abs(event.clientX - stagePointer.x);
    const dy = Math.abs(event.clientY - stagePointer.y);
    const ds = Math.abs(stage.scrollTop - stagePointer.scroll);
    stagePointer = null;

    try {
      stage.releasePointerCapture(event.pointerId);
    } catch (err) {}

    if (mode === 3) {
      if (dx < 8 && dy < 8 && ds < 4) cycleMode();
      dragged = false;
      return;
    }

    if (dragged) {
      const idle = performance.now() - state.lastMoveTime;
      startMomentum(idle > 110 ? 0 : state.dragVelocity);
      dragged = false;
      return;
    }

    if (dx < 8 && dy < 8) cycleMode();
    dragged = false;
  });

  stage.addEventListener('pointercancel', (event) => {
    stagePointer = null;
    dragged = false;
    try {
      stage.releasePointerCapture(event.pointerId);
    } catch (err) {}
  });

  stage.addEventListener('keydown', (event) => {
    if (event.key === 'Enter' || event.key === ' ') {
      event.preventDefault();
      event.stopPropagation();
      cycleMode();
      return;
    }
    if (state.mode !== 3 && (event.key === 'ArrowLeft' || event.key === 'ArrowRight')) {
      event.preventDefault();
      setYaw(state.yaw + (event.key === 'ArrowRight' ? -8 : 8));
      return;
    }
    if (state.mode !== 3 && (event.key === 'ArrowUp' || event.key === 'ArrowDown')) {
      event.preventDefault();
      const delta = event.key === 'ArrowDown' ? -4 : 4;
      state.pitchOffset = Math.max(-PITCH_LIMIT, Math.min(PITCH_LIMIT, state.pitchOffset + delta));
      applyScenePitch();
    }
  });

  document.addEventListener('keydown', (event) => {
    if (!state.entryOpen) return;
    if (dateDialog.open || settingsDialog.open) return;
    if (event.key === 'Escape') {
      event.preventDefault();
      closeEntry();
      return;
    }
    if (event.target instanceof Element
      && event.target.closest('input, textarea, select, button, [contenteditable="true"]')) return;

    if (/^[0-9]$/.test(event.key)) {
      event.preventDefault();
      pressKey(event.key);
      return;
    }
    if (event.key === '.') {
      event.preventDefault();
      pressKey('.');
      return;
    }
    if (event.key === 'Backspace') {
      event.preventDefault();
      pressKey('backspace');
      return;
    }
    if (event.key === 'Delete') {
      event.preventDefault();
      clearAmount();
      return;
    }
    if (['+', '-', '*', '/'].includes(event.key)) {
      event.preventDefault();
      pressOperator();
      return;
    }
    if (event.key === '=') {
      event.preventDefault();
      pressEquals();
      return;
    }
    if (event.key === 'Enter') {
      event.preventDefault();
      saveEntry();
    }
  });

  /* -------------------------------------------------------
     Resize
     ------------------------------------------------------- */
  let resizeRaf = 0;
  const ro = new ResizeObserver(() => {
    if (!state.entryOpen || !state.groups.length) return;
    cancelAnimationFrame(resizeRaf);
    resizeRaf = requestAnimationFrame(() => {
      const scroll = stage.scrollTop;
      if (state.mode === 1) buildLevel1();
      else if (state.mode === 2) buildLevel2();
      else {
        buildGrid2D();
        stage.scrollTop = Math.min(scroll, Math.max(0, stage.scrollHeight - stage.clientHeight));
      }
    });
  });
  ro.observe(stage);

  /* -------------------------------------------------------
     初始化
     ------------------------------------------------------- */
  applyTheme(themeMode, false);
  state.bills = loadBills();
  renderBills();
  updateAccountUI();
  checkAuth();
  resetEntry();
  stage.dataset.mode = '1';
  stage.classList.add('is-empty');
  setYaw(-30);
})();
