// EMF.exe's page: draws the state the host sends (window.chrome.webview) and sends the player's commands back.
// Plain JavaScript, no framework and no build step. Every text from the game folder or Nexus goes in as text, never as
// HTML; the one exception is a Nexus description, which the host turned into safe HTML (src/nexus/bbcode.h) and which
// goes into its own container (.bb) only.
'use strict';

const host = window.chrome && window.chrome.webview;
const $ = (id) => document.getElementById(id);

const GROUPS = [
  { source: 'emf', title: 'EMF mods', one: 'EMF mod',
    note: () => 'On and off are saved in emf\\config' },
  { source: 'eml', title: 'EML and ShroudForge mods', one: 'EML mod',
    note: (s) => (s.shroudforge_active ? 'ShroudForge switches these (F9 in game)' : "Off renames the folder with a leading '.'") },
  { source: 'chain', title: 'DLL mods started by EMF', one: 'DLL mod started by EMF',
    note: () => 'Listed in dinput8-chain.ini' },
  { source: 'other', title: 'Other loaders and their mods', one: 'Another loader',
    note: () => 'Read-only: their own loader manages them' },
];

let state = null;
const TABS = ['mods', 'server', 'browse', 'saves', 'warnings', 'emf'];
let tab = TABS.includes(new URLSearchParams(location.search).get('tab')) ? new URLSearchParams(location.search).get('tab') : 'mods';
let selected = new URLSearchParams(location.search).get('select');  // a row's key, or "source:id" from --select
let filterText = '';
let logWhich = 'core';
let logs = { core: '', loader: '', content: '' };
let reportedRender = false;
let detailsShown = '';
let forceDetails = false;  // a save was refused: draw the details again even if a control has focus
const settingErrors = {};  // "source:id:key" (the save's ref) -> why the last value was refused
let pending = false;       // a switch is waiting for the host
let pendingKey = '';       // the row of that switch (the note counts the mods switched)
let account = null;        // the host's account message: whether a key is set, the account's name and Premium (never the key)
// The host's Nexus mode (bridge.h nexus_mode; state.nexus, account.mode): "off" in the release build (no Browse,
// no Check for updates, no account, no nxm:// setting: nothing asks Nexus, and the host refuses those commands too),
// "personal_key" with the tester switch, "sso" with the slug. Off until the host says otherwise.
let nexusMode = 'off';
const nexusOn = () => nexusMode !== 'off';
let download = null;       // the last download message
let downloadHide = 0;      // the timer that hides a finished download's bar
let waitingPlan = null;    // a plan from a download that arrived while another sheet was open: "Show plan" opens it
let readyDownload = null;  // the host's download_ready: a finished download whose plan waits (a plan was open)
const INSTALL_GUARD_MS = 1000;  // a plan's Install ignores clicks and Enter this long after the sheet appears
const KEYS_URL = 'https://www.nexusmods.com/settings/api-keys';
// The key field is made once and kept, so drawing the account card again never loses what the player is typing. The
// key goes to the host once (Save key) and the field is emptied at once.
const keyInput = el('input', {
  id: 'acct-key', type: 'password', autocomplete: 'off', spellcheck: 'false', maxlength: '1024',
  placeholder: 'Paste your personal API key', 'aria-label': 'Nexus API key',
});

function send(msg) {
  if (host) host.postMessage(msg);
}

// el('div', {class: 'x', onclick: fn}, child, 'text', [more]): attributes that are false/null/undefined are left out.
function el(tag, attrs, ...children) {
  const e = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs || {})) {
    if (v === undefined || v === null || v === false) continue;
    if (k.startsWith('on')) e.addEventListener(k.slice(2), v);
    else if (k === 'class') e.className = v;
    else e.setAttribute(k, v === true ? '' : String(v));
  }
  for (const c of children.flat(Infinity)) {
    if (c === null || c === undefined || c === false) continue;
    e.append(c instanceof Node ? c : document.createTextNode(String(c)));
  }
  return e;
}

// Replaces a node's children, leaving out null/undefined/false (replaceChildren would show them as text).
function fill(node, ...kids) {
  node.replaceChildren(...kids.flat(Infinity).filter((k) => k !== null && k !== undefined && k !== false));
}

const keyOf = (m) => m.key;  // unique per entry (source and path), from the host
const groupOf = (m) => GROUPS.find((g) => g.source === m.source) || GROUPS[3];
// A version shown as "v1.2.0", without a second v when the text already starts with one ("v1.2.0" seen on Nexus).
const vtext = (v) => (/^v/i.test(String(v)) ? '' : 'v') + v;

// ---- messages from the host ----
if (host) host.addEventListener('message', (e) => onMessage(e.data));

function onMessage(m) {
  if (!m || typeof m !== 'object') return;
  if (onServerMessage(m)) return;  // folders and dedicated servers (the servers block below)
  if (m.type === 'state') {
    state = m;
    if (m.nexus) nexusMode = m.nexus;
    if (refreshAfterState) {  // a saved setting decides whether others can be changed: draw them again
      refreshAfterState = false;
      forceDetails = true;
    }
    render();
    updatesOnState();
  } else if (m.type === 'result') {
    onResult(m);
  } else if (m.type === 'logs') {
    logs = { core: m.core || '', loader: m.loader || '', content: m.content || '' };
    renderLog();
  } else if (m.type === 'nexus_search') {
    onSearch(m);
  } else if (m.type === 'nexus_mod') {
    onModPage(m);
  } else if (m.type === 'nexus_file') {
    onFile(m);
  } else if (m.type === 'install_busy') {
    // a download's plan never covers what is on screen: it waits behind "Show plan" while another sheet is open
    if (!(m.from_download && sheetInTheWay())) {
      showModal({ mode: 'busy', fromDownload: !!m.from_download, title: 'Unpacking ' + m.archive, text: 'EMF unpacks the file into a temporary folder and checks what is inside. Nothing is copied yet.' });
    }
  } else if (m.type === 'install_plan') {
    if (m.from_download && sheetInTheWay()) {
      if (m.ok) waitingPlan = m.plan;
      else toast(m.error, true);
      renderDownload();
    } else {
      onPlan(m);
    }
  } else if (m.type === 'download_ready') {
    readyDownload = m.count > 0 ? m : null;
    renderDownload();
  } else if (m.type === 'install_done' || m.type === 'uninstall_done') {
    updatesOnDone(m);
    onDone(m);
  } else if (m.type === 'account') {
    account = m;
    if (m.mode) nexusMode = m.mode;
    renderAccount();
    renderNexusChip();
    updatesRedraw();
    if (tab === 'browse') renderBrowseDetails(true);
  } else if (m.type === 'download') {
    onDownload(m);
  } else if (m.type === 'updates') {
    onUpdates(m);
  } else if (m.type === 'nexus_links') {
    onNexusLinks(m);
  }
}

function onResult(m) {
  if (m.cmd === 'set_enabled') {
    pending = false;
    if (m.ok) {  // one note for switches made one after another, not one each
      switchNote(pendingKey);
      if (state) render();
      return;
    }
  }
  if (m.cmd === 'updates_check' || m.cmd === 'nexus_link') updatesOnResult(m);
  if (m.cmd === 'set_setting' && m.ref) {  // the host echoes the ref the save was sent with
    if (m.ok) delete settingErrors[m.ref];
    else {
      settingErrors[m.ref] = m.error;
      forceDetails = true;  // the control shows the stored value again, with the reason under it
    }
  }
  if (!m.ok && m.error) toast(m.error, true);
  else if (m.text) toast(m.text, false);
  if (state) render();
}

function toast(text, bad) {
  const t = el('div', { class: 'toast' + (bad ? ' bad' : ''), role: bad ? 'alert' : 'status' }, text);
  $('toasts').append(t);
  setTimeout(() => t.remove(), bad ? 9000 : 4500);
}

// Switches made one after another share one note that counts the mods: "3 changes take effect at the next game
// start." It stays while the player keeps switching and goes a few seconds after the last switch.
const switched = { note: null, keys: new Set(), timer: 0 };
function switchNote(key) {
  switched.keys.add(key || '');
  const n = switched.keys.size;
  const text = n === 1 ? 'Takes effect at the next game start.' : n + ' changes take effect at the next game start.';
  if (switched.note && switched.note.isConnected) switched.note.textContent = text;
  else {
    switched.note = el('div', { class: 'toast', role: 'status', id: 'switch-note' }, text);
    $('toasts').append(switched.note);
  }
  clearTimeout(switched.timer);
  switched.timer = setTimeout(() => {
    if (switched.note) switched.note.remove();
    switched.note = null;
    switched.keys.clear();
  }, 6000);
}

// ---- drawing ----
// Without the Nexus features: no Browse tab and no Check for updates (a --page browse start shows the Mods tab).
function nexusGate() {
  const on = nexusOn();
  $('tab-browse').hidden = !on;
  $('updates-check').hidden = !on;
  if (!on && tab === 'browse') {
    tab = 'mods';
    for (const o of document.querySelectorAll('.tab[data-tab]')) o.setAttribute('aria-selected', String(o.dataset.tab === tab));
  }
}

function render() {
  nexusGate();
  renderHeader();
  const nogame = !state.game_found;
  $('page-nogame').hidden = !(nogame && tab === 'mods');
  $('page-mods').hidden = nogame || tab !== 'mods';
  $('page-browse').hidden = tab !== 'browse';
  $('page-warnings').hidden = tab !== 'warnings';
  $('page-emf').hidden = tab !== 'emf';
  $('page-saves').hidden = tab !== 'saves';  // the Saves tab (saves.js)
  if (tab === 'saves' && typeof renderSaves === 'function') renderSaves(false);
  if (tab === 'browse') renderBrowse();
  if (modal) renderModal();
  if (nogame) {
    const why = state.warnings.find((w) => w.level === 'error');
    $('nogame-text').textContent = state.game
      ? (why ? why.text : 'This folder has no enshrouded.exe.')
      : 'EMF could not find the game through Steam. Choose the folder that holds enshrouded.exe, or enshrouded_server.exe for a dedicated server.';
  }
  // the list is drawn anew: keep the keyboard on the row (or its switch) it was on
  const active = document.activeElement;
  const row = active && active.closest ? active.closest('.mod-row') : null;
  const focusKey = row ? row.dataset.key : null;
  const onSwitch = !!row && active.classList.contains('switch');
  if (!nogame) renderList();
  if (focusKey) {
    const again = [...document.querySelectorAll('.mod-row')].find((r) => r.dataset.key === focusKey);
    const sw = again && again.querySelector('.switch');
    if (again) (onSwitch && sw && !sw.disabled ? sw : again).focus();
  }
  if (!nogame) renderDetails(false);
  renderWarnings();
  renderEmf();
  if (typeof renderContent === 'function') renderContent();  // the EML content card (content.js)
  renderAccount();
  renderNexusChip();
  renderServers();
  if (!reportedRender) {  // the smoke test waits for this: what the rows show, read back from the page
    reportedRender = true;
    const titles = nogame ? [] : [...document.querySelectorAll('#groups .mod-name')].map((n) => n.textContent);
    send({ cmd: 'rendered', count: titles.length, titles });
  }
}

function renderHeader() {
  const s = state;
  const path = $('folder-path');
  path.replaceChildren(el('bdi', {}, s.game || 'No folder chosen'));
  path.title = s.game ? 'Show ' + s.game + ' in Explorer' : '';
  path.disabled = !s.game_found;

  const chip = $('emf-chip');
  chip.hidden = !s.game_found;
  chip.className = 'emf-chip ' + (s.emf_installed ? 'ok' : 'missing');
  chip.textContent = s.emf_installed ? 'EMF ' + (s.emf_version || '') + ' installed' : 'EMF not installed';

  const play = $('play');
  play.disabled = s.game_running && !s.server;
  $('play-label').textContent = s.server ? 'Server' : s.game_running ? 'Running' : 'Play';
  $('play-sub').textContent = s.server ? (s.game_running ? 'running: stop it there' : 'start it in the Server tab')
    : s.game_running ? 'close it to switch mods' : 'through Steam';
  play.title = s.server ? 'A dedicated server folder: the Server tab starts and stops it'
    : s.wine ? 'Under Wine or Proton the link may not reach Steam: if nothing starts, start Enshrouded from Steam. EMF still loads with it.' : '';
  // the Play menu (a game folder only): the two starts without mods need EMF's loader here to know the one-shot flag
  const more = $('play-more');
  more.hidden = !!s.server || !s.game_found;
  more.disabled = !!s.game_running;
  const why = !s.emf_installed ? 'EMF is not installed in this folder: Play starts the game without EMF anyway.'
    : !s.play_once ? 'The EMF in this folder is older and cannot do this. Install EMF again from its package.' : '';
  // aria-disabled, not disabled: the entries stay focusable, so keyboard and screen-reader users hear why
  for (const id of ['play-no-emf', 'play-no-mods']) $(id).setAttribute('aria-disabled', why ? 'true' : 'false');
  $('play-no-emf-sub').textContent = why || 'This start only. The DLL mods started by EMF still run.';
  $('play-no-mods-sub').textContent = why || 'This start only. Neither EMF mods nor the DLL mods started by EMF.';
  if (more.hidden || more.disabled) playMenu(false);

  const running = $('running');
  running.hidden = !s.game_running;
  // the reason says which process, or that Windows hides its folder (the game runs as administrator)
  const reason = (s.running_reason || 'Enshrouded is running from this folder').replace(/\.?\s*$/, '.');
  running.textContent = reason + ' Switches stay locked until it is closed; settings still save and apply at its next start.';

  $('count-mods').textContent = s.game_found ? String(s.mods.length) : '';
  const alerts = s.warnings.filter((w) => w.level !== 'info').length;
  $('count-warnings').textContent = alerts ? String(alerts) : '';
}

function loaderBadge(m) {
  const cls = m.loaded_by === 'EMF' ? 'emf' : m.loaded_by === 'EML' ? 'eml' : m.loaded_by === 'ShroudForge' ? 'sf' : '';
  return el('span', { class: 'badge ' + cls, title: 'Loaded by ' + m.loaded_by }, m.loaded_by);
}

function statusBadges(m) {
  const b = (cls, text, title) => el('span', { class: 'badge ' + cls, title }, text);
  const out = [];
  const chainTrouble = m.source === 'chain' && /^(missing|failed)/.test(m.status);  // its own badge says it
  if (m.error && !chainTrouble) out.push(b('bad', 'Error', m.error));
  if (m.is_loader) out.push(b('quiet', 'Loader'));
  if (m.source === 'chain' && m.status === 'kept aside') out.push(b('quiet', 'Kept aside'));
  else if (m.source === 'chain' && m.status === 'not listed') out.push(b('quiet', 'Not listed'));
  else if (m.source === 'chain' && m.enabled) {  // the last game start; an off DLL will not start next time
    if (m.status === 'started') out.push(b('ok', 'Started', 'Started at the last game start'));
    else if (m.status === 'missing') out.push(b('bad', 'Missing', 'Not in the game folder at the last game start'));
    else if (m.status.startsWith('failed')) out.push(b('bad', 'Failed', 'Did not load at the last game start'));
    else if (m.status === 'skipped') out.push(b('quiet', 'Skipped', 'Not started at the last game start: the game was started without any mods'));
    else if (!m.error) out.push(b('quiet', 'Not started yet', 'Listed after the last game start'));
  }
  const update = updateBadge(m);  // from the last "Check for updates"
  if (update) out.push(update);
  return out;
}

function toggle(m) {
  const locked = m.can_toggle && state.game_running;
  const title = !m.can_toggle ? m.toggle_note
    : locked ? 'Close the game first to switch mods'
    : m.enabled ? 'On. Switch it off (takes effect at the next game start)' : 'Off. Switch it on (takes effect at the next game start)';
  return el('button', {
    class: 'switch', type: 'button', role: 'switch', 'aria-checked': String(m.enabled),
    'aria-label': m.name, title, disabled: !m.can_toggle || locked || pending,
    onclick: (e) => {
      e.stopPropagation();
      pending = true;
      pendingKey = keyOf(m);
      send({ cmd: 'set_enabled', source: m.source, id: m.id, on: !m.enabled });
      render();
    },
  });
}

function modRow(m) {
  const key = keyOf(m);
  return el('div', {
    class: 'mod-row' + (m.enabled ? '' : ' off') + (key === selected ? ' selected' : ''),
    role: 'button', tabindex: '0', 'aria-pressed': String(key === selected), 'data-key': key,
    onclick: () => select(key),
    onkeydown: (e) => {
      if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); select(key); }
    },
  },
  el('div', { class: 'mod-main' },
    el('div', { class: 'mod-title' },
      el('span', { class: 'mod-name' }, m.name),
      m.version ? el('span', { class: 'mod-version' }, m.version) : null),
    el('div', { class: 'mod-sub' }, loaderBadge(m), statusBadges(m),
      serverBadge(m),
      m.description ? el('span', { class: 'mod-desc' }, m.description) : null)),
  m.is_loader ? null : toggle(m));  // a loader has no switch here
}

function renderList() {
  const groups = $('groups');
  const f = filterText.trim().toLowerCase();
  const match = (m) => !f || [m.name, m.id, m.description, m.loaded_by].join(' ').toLowerCase().includes(f);
  if (selected && !state.mods.some((m) => keyOf(m) === selected)) {  // --select gives "source:id"
    const named = state.mods.find((m) => m.source + ':' + m.id === selected);
    if (named) selected = keyOf(named);
  }
  if (!selected || !state.mods.some((m) => keyOf(m) === selected)) {
    const first = GROUPS.map((g) => state.mods.find((m) => m.source === g.source)).find(Boolean);
    selected = first ? keyOf(first) : null;
  }
  const cards = [];
  for (const g of GROUPS) {
    const all = state.mods.filter((m) => m.source === g.source);
    if (!all.length && g.source !== 'emf') continue;
    const shown = all.filter(match);
    cards.push(el('section', { class: 'group', 'aria-label': g.title },
      el('div', { class: 'group-head' },
        el('span', { class: 'group-title' }, g.title),
        el('span', { class: 'group-count' }, String(all.length)),
        el('span', { class: 'group-note' }, g.note(state))),
      shown.length ? shown.map(modRow)
        : el('div', { class: 'group-empty' }, all.length ? 'Nothing matches the filter.' : 'No EMF mods in emf\\mods yet.')));
  }
  groups.replaceChildren(...cards);
}

function select(key) {
  const rowFocused = document.activeElement && document.activeElement.classList.contains('mod-row');
  selected = key;
  renderList();
  renderDetails(true);
  if (rowFocused) {  // the list was drawn again: keep the keyboard on the chosen row
    const row = [...document.querySelectorAll('.mod-row')].find((r) => r.dataset.key === key);
    if (row) row.focus();
  }
}

// EMF's names for a key press, the ones its key settings read (emf/keys.hpp); '' for a key that cannot be bound.
const KEY_NAMES = {
  Space: 'Space', Tab: 'Tab', Enter: 'Enter', NumpadEnter: 'Enter', Backspace: 'Backspace', Insert: 'Insert',
  Delete: 'Delete', Home: 'Home', End: 'End', PageUp: 'PageUp', PageDown: 'PageDown', ArrowUp: 'Up', ArrowDown: 'Down',
  ArrowLeft: 'Left', ArrowRight: 'Right', ShiftLeft: 'Shift', ShiftRight: 'Shift', ControlLeft: 'Ctrl',
  ControlRight: 'Ctrl', AltLeft: 'Alt', AltRight: 'Alt', CapsLock: 'CapsLock', Pause: 'Pause', NumpadAdd: 'NumpadAdd',
  NumpadSubtract: 'NumpadSubtract', NumpadMultiply: 'NumpadMultiply', NumpadDivide: 'NumpadDivide',
  NumpadDecimal: 'NumpadDecimal',
};
// Windows virtual-key codes with a name in EMF's key settings (the others bind as their number, "0xba").
const VK_NAMES = {
  8: 'Backspace', 9: 'Tab', 13: 'Enter', 16: 'Shift', 17: 'Ctrl', 18: 'Alt', 19: 'Pause', 20: 'CapsLock', 32: 'Space',
  33: 'PageUp', 34: 'PageDown', 35: 'End', 36: 'Home', 37: 'Left', 38: 'Up', 39: 'Right', 40: 'Down', 45: 'Insert',
  46: 'Delete', 106: 'NumpadMultiply', 107: 'NumpadAdd', 109: 'NumpadSubtract', 110: 'NumpadDecimal', 111: 'NumpadDivide',
};
// The key the game will see for a key press: by its Windows virtual-key code, which follows the keyboard layout (on a
// German keyboard the key printed Z binds Z) and NumLock (Numpad 8 with NumLock off is Up). '' for the IME's key.
function keyName(e) {
  const k = e.keyCode || 0;
  if (k === 229 || e.key === 'Process') return '';  // the IME is composing: no key the game sees
  if (k) {
    if ((k >= 65 && k <= 90) || (k >= 48 && k <= 57)) return String.fromCharCode(k);
    if (k >= 96 && k <= 105) return 'Numpad' + (k - 96);
    if (k >= 112 && k <= 135) return 'F' + (k - 111);
    if (VK_NAMES[k]) return VK_NAMES[k];
    return k > 6 && k < 255 && k !== 27 ? '0x' + k.toString(16).padStart(2, '0') : '';
  }
  const c = e.code || '';  // no key code (a made-up event): the physical key
  if (/^Key[A-Z]$/.test(c)) return c.slice(3);
  if (/^Digit[0-9]$/.test(c)) return c.slice(5);
  if (/^F([1-9]|1[0-9]|2[0-4])$/.test(c) || /^Numpad[0-9]$/.test(c)) return c;
  if (KEY_NAMES[c]) return KEY_NAMES[c];
  return e.keyCode > 6 && e.keyCode < 255 ? '0x' + e.keyCode.toString(16).padStart(2, '0') : '';
}

// A key bind waiting for a key: {ref, save}. The next key anywhere on the page binds; Esc or a click elsewhere cancels.
let capture = null;
let refreshAfterState = false;
const MODIFIERS = ['Shift', 'Ctrl', 'Alt'];
function bindCaptured(name) {
  const c = capture;
  capture = null;
  c.save(name);
  renderDetails(true);
}
window.addEventListener('keydown', (e) => {
  if (!capture) return;
  e.preventDefault();
  e.stopPropagation();
  if (e.key === 'Escape') {
    capture = null;
    renderDetails(true);
    return;
  }
  const name = keyName(e);
  if (!name) return;
  if (MODIFIERS.includes(name)) {  // wait: Shift+G binds G, Shift released alone binds Shift
    capture.modifier = name;
    return;
  }
  if (/^Numpad[0-9]$/.test(e.code || '') && !/^Numpad/.test(name))
    toast('NumLock is off, so the game sees this key as ' + name + '. Switch NumLock on to bind ' + e.code + '.', false);
  bindCaptured(name);
}, true);
window.addEventListener('keyup', (e) => {
  if (!capture || !capture.modifier) return;
  if (keyName(e) === capture.modifier) {
    e.preventDefault();
    bindCaptured(capture.modifier);
  }
}, true);
document.addEventListener('mousedown', (e) => {
  // a click on a key bind button (this one or another) is handled by its own click: no redraw that would eat it
  if (capture && !(e.target.closest && e.target.closest('.keybind'))) {
    capture = null;
    renderDetails(true);
  }
}, true);

const sentence = (t) => t.charAt(0).toUpperCase() + t.slice(1) + '.';
// A setting's default for its tooltip, as the in-game Mods tab shows it on hover (the host sends it shown: "on", an
// option's label, a key's name); undefined from an older host.
const defaultTip = (s) =>
  typeof s.default_shown === 'string' ? 'Default: ' + (s.default_shown === '' ? '(empty)' : s.default_shown) : undefined;

function settingControl(m, s) {
  const errKey = keyOf(m) + ':' + s.key;
  const save = (value) => {
    if (s.controls) refreshAfterState = true;
    send({ cmd: 'set_setting', id: m.id, key: s.key, value: String(value), ref: errKey });
  };
  const off = s.active === false;  // its enabledWhen does not hold: greyed out, as in the in-game Mods tab
  const focus = 'set:' + s.key;
  const parts = [];
  if (s.type === 'bool') {
    parts.push(el('button', {
      class: 'switch', type: 'button', role: 'switch', 'aria-checked': String(s.value === '1'), 'aria-label': s.label,
      'data-focus': focus, disabled: off,
      onclick: () => save(s.value === '1' ? '0' : '1'),
    }));
    parts.push(el('span', { class: 'setting-range' }, s.value === '1' ? 'On' : 'Off'));
  } else if (s.type === 'int' || s.type === 'float') {
    const step = s.step ? String(s.step) : s.type === 'int' ? '1' : 'any';
    const num = el('input', { type: 'number', value: s.value, step, min: s.min, max: s.max, 'aria-label': s.label, 'data-focus': focus, disabled: off });
    num.addEventListener('change', () => save(num.value));
    num.addEventListener('keydown', (e) => { if (e.key === 'Enter') num.blur(); });
    parts.push(num);
    if (s.min !== undefined && s.max !== undefined) {
      const range = el('input', { type: 'range', value: s.value, step, min: s.min, max: s.max, 'aria-label': s.label + ' (slider)', 'data-focus': focus + ':range', disabled: off });
      range.addEventListener('input', () => { num.value = range.value; });
      range.addEventListener('change', () => save(range.value));
      parts.push(range);
    } else if (s.min !== undefined || s.max !== undefined) {
      parts.push(el('span', { class: 'setting-range' }, s.min !== undefined ? 'at least ' + s.min : 'at most ' + s.max));
    }
  } else if (s.type === 'choice') {
    const sel = el('select', { 'aria-label': s.label, 'data-focus': focus, disabled: off },
      s.choices.map((c, i) => el('option', { value: String(i), selected: String(i) === s.value }, c)));
    sel.addEventListener('change', () => save(sel.value));
    parts.push(sel);
  } else if (s.type === 'select') {
    const sel = el('select', { 'aria-label': s.label, 'data-focus': focus, disabled: off },
      (s.options || []).map((o) => el('option', { value: o.value, selected: o.value === s.value }, o.label)));
    sel.addEventListener('change', () => save(sel.value));
    parts.push(sel);
  } else if (s.type === 'color') {
    const pick = el('input', { type: 'color', value: s.value, 'aria-label': s.label, 'data-focus': focus, disabled: off });
    pick.addEventListener('change', () => save(pick.value));
    parts.push(pick, el('span', { class: 'setting-range' }, s.value));
  } else if (s.type === 'key') {
    const waiting = !!capture && capture.ref === errKey;
    parts.push(el('button', {
      class: 'keybind' + (waiting ? ' waiting' : ''), type: 'button', 'data-focus': focus, disabled: off,
      'aria-label': s.label + ': ' + (s.value || 'no key') + (waiting ? '. Press a key, Esc cancels' : '. Click, then press a key'),
      onclick: () => {
        capture = waiting ? null : { ref: errKey, save };
        renderDetails(true);
      },
    }, waiting ? 'Press a key\u2026' : (s.value || 'No key')));
    if (waiting) parts.push(el('span', { class: 'setting-range' }, 'Esc cancels'));
    else if (s.value) parts.push(el('button', { class: 'ghost small', type: 'button', disabled: off, onclick: () => save('') }, 'Clear'));
  } else {
    const input = el('input', {
      type: 'text', value: s.value, spellcheck: 'false', 'aria-label': s.label, 'data-focus': focus, disabled: off,
      maxlength: s.max_length || undefined,
    });
    input.addEventListener('change', () => save(input.value));
    input.addEventListener('keydown', (e) => { if (e.key === 'Enter') input.blur(); });
    parts.push(input);
    if (s.max_length) parts.push(el('span', { class: 'setting-range' }, 'max ' + s.max_length));
  }
  return el('div', { class: 'setting' + (off ? ' inactive' : ''), title: defaultTip(s) },
    el('div', { class: 'setting-head' },
      el('span', { class: 'setting-label' }, s.label || s.key),
      state.game_running
        ? el('span', { class: 'setting-when', title: 'The game is running: what you save here applies at its next start' }, 'From next start')
        : el('span', { class: 'setting-when' + (s.live ? ' live' : ''), title: s.live ? 'The in-game Mods tab applies it at once' : 'Applies when the game starts' },
          s.live ? 'Live in the in-game Mods tab' : 'At game start')),
    s.help ? el('p', { class: 'setting-help' }, s.help) : null,
    el('div', { class: 'setting-control' }, parts),
    off && s.when ? el('p', { class: 'setting-cond' }, sentence(s.when)) : null,
    settingErrors[errKey] ? el('div', { class: 'setting-error', role: 'alert' }, settingErrors[errKey]) : null);
}

// The settings with a heading where a group starts (the host sends them in the in-game Mods tab's order).
function settingList(m) {
  const out = [];
  let group = '';
  for (const s of m.settings) {
    if ((s.group || '') !== group) {
      group = s.group || '';
      if (group) out.push(el('h4', { class: 'setting-group' }, group));
    }
    out.push(settingControl(m, s));
  }
  return out;
}

function renderDetails(force) {
  const d = $('details');
  const m = state.mods.find((x) => keyOf(x) === selected);
  if (!m) {
    fill(d, el('p', { class: 'details-empty' }, state.mods.length ? 'Choose a mod to see its details.' : 'No mods are installed in this folder yet.'));
    detailsShown = '';
    return;
  }
  const shownNow = JSON.stringify([m, state.game_running, pending, settingErrors, capture && capture.ref, updatesSignature(m)]);
  if (forceDetails) force = true;
  forceDetails = false;
  if (!force && shownNow === detailsShown) return;
  const active = document.activeElement;
  if (!force && d.contains(active) && (active.tagName === 'INPUT' || active.tagName === 'SELECT')) return;  // the player is typing
  detailsShown = shownNow;
  const scroll = d.scrollTop;
  const focusWas = d.contains(active) && active.dataset ? active.dataset.focus : '';  // to put the keyboard back after

  const g = groupOf(m);
  const meta = [];
  if (m.version) meta.push('Version ' + m.version);
  if (m.authors.length) meta.push('by ' + m.authors.join(', '));
  const switchText = !m.can_toggle ? m.toggle_note
    : state.game_running ? 'Close the game first to switch it.'
    : 'Takes effect the next time the game starts.';
  const nexus = /^\d+$/.test(m.nexus_id) ? 'https://www.nexusmods.com/enshrouded/mods/' + m.nexus_id : '';

  fill(d,
    el('div', { class: 'd-eyebrow' }, m.is_loader ? 'Loader' : g.one),
    el('h2', { class: 'd-name' + (/\.(dll|zip)$/i.test(m.name) ? ' file' : '') }, m.name),
    el('div', { class: 'd-meta' }, meta.join(' · '), meta.length && m.id !== m.name ? ' · ' : '',
      m.id !== m.name ? el('span', { class: 'mono' }, m.id) : null),
    el('div', { class: 'd-badges' }, loaderBadge(m), statusBadges(m)),
    m.is_loader ? null : el('div', { class: 'd-switch' }, withFocus(toggle(m), 'toggle'),
      el('div', { class: 'd-switch-text' },
        el('strong', {}, m.enabled ? 'On' : 'Off'),
        el('span', {}, switchText),
        m.can_toggle && m.toggle_note ? el('span', {}, m.toggle_note) : null)),
    m.error ? el('div', { class: 'd-error', role: 'alert' }, el('span', {}, m.error),
      copyButton(() => m.name + ': ' + m.error)) : null,
    m.description ? el('p', { class: 'd-desc' }, m.description) : null,
    m.note ? el('p', { class: 'd-note' }, m.note) : null,
    serverNote(m),
    el('div', { class: 'd-actions' },
      nexus ? el('button', { class: 'ghost', type: 'button', title: nexus, onclick: () => send({ cmd: 'open_url', url: nexus }) }, 'Open on Nexus Mods') : null,
      m.path ? el('button', { class: 'ghost', type: 'button', title: m.path, onclick: () => send({ cmd: 'open_folder', path: m.path }) }, 'Show in Explorer') : null,
      m.install_key ? withFocus(el('button', {
        class: 'ghost danger', type: 'button', disabled: state.game_running,
        title: state.game_running ? 'Close the game first' : 'Remove the files EMF installed for it',
        onclick: () => confirmUninstall(m.install_key, keyOf(m), m.install_root, m.name),
      }, 'Uninstall'), 'uninstall') : null),
    m.install_key ? el('p', { class: 'd-note' }, installedText(m.install_key, keyOf(m), m.install_root)) : null,
    updateSection(m),
    m.depends.length ? el('div', { class: 'd-section' }, el('h3', {}, 'Needs'), el('ul', { class: 'd-list' }, m.depends.map((x) => el('li', {}, x)))) : null,
    m.game_build ? el('p', { class: 'd-note' }, 'Made for game build ' + m.game_build + '.') : null,
    m.settings.length ? el('div', { class: 'd-section' },
      el('h3', {}, 'Settings'),
      state.game_running ? el('p', { class: 'd-note' }, 'The game is running: what you save here applies at its next start. The in-game Mods tab changes settings at once.') : null,
      settingList(m)) : null,
    m.readme ? el('div', { class: 'd-section' }, el('h3', {}, 'Readme'), el('pre', { class: 'readme' }, m.readme)) : null);
  d.scrollTop = scroll;
  if (focusWas) {
    const again = d.querySelector('[data-focus="' + CSS.escape(focusWas) + '"]');
    if (again && !again.disabled) again.focus();
  }
}

// A small button that puts a text on the clipboard (through the host), for a bug report.
function copyButton(text) {
  return el('button', { class: 'ghost small copy', type: 'button', title: 'Copy to the clipboard', onclick: (e) => {
    e.stopPropagation();
    send({ cmd: 'copy', text: text() });
  } }, 'Copy');
}

// Marks a control so the keyboard can be put back on it after the details are drawn again.
function withFocus(node, name) {
  node.dataset.focus = name;
  return node;
}

function renderWarnings() {
  const list = $('warnings');
  const label = { error: 'Error', warn: 'Warning', info: 'Note' };
  list.replaceChildren(...(state.warnings.length
    ? state.warnings.map((w) => el('li', { class: 'warning ' + w.level }, el('span', { class: 'lvl' }, label[w.level] || w.level), el('span', { class: 'text' }, w.text)))
    : [el('li', { class: 'none' }, 'No warnings: nothing clashes that EMF can see.')]));
  $('report').textContent = state.report.length ? state.report.join('\n') : 'Nothing to report: no proxy DLLs next to the game and nothing started by EMF.';
}

function renderEmf() {
  const box = $('install');
  const s = state;
  let title, text, cls;
  if (!s.game_found) {
    cls = 'card install';
    title = 'No game folder';
    text = 'Choose the game folder first (Change, at the top).';
  } else if (s.emf_installed) {
    cls = 'card install ok';
    title = 'EMF ' + (s.emf_version || '') + ' is installed';
    text = 'In ' + s.game + '. Its loader (dinput8.dll) starts EMF and the DLL mods in dinput8-chain.ini when the game starts.';
  } else {
    cls = 'card install missing';
    title = 'EMF is not installed here';
    text = 'Unpack the EMF package and run install.cmd. It finds the game through Steam, keeps other mods and lists their DLLs so EMF starts them.';
  }
  box.className = cls;
  fill(box,
    el('h3', {}, title),
    el('p', {}, text),
    el('p', {}, 'This app: EMF.exe ' + (s.app_version || '') + '.'),
    s.game_found ? el('div', { class: 'row' },
      el('button', { class: 'ghost', type: 'button', onclick: () => send({ cmd: 'open_folder', path: s.game }) }, 'Show the game folder'),
      s.emf_installed ? el('button', { class: 'ghost', type: 'button', onclick: () => send({ cmd: 'open_folder', path: s.game + '\\emf' }) }, 'Show the emf folder') : null) : null);
}

function renderLog() {
  const text = logs[logWhich];
  const log = $('log');
  const none = {
    core: 'No emf_core.log yet: EMF writes it when the game starts.',
    loader: 'No emf_loader.log yet: EMF writes it when the game starts.',
    content: 'No content.log yet: EMF writes it when it builds the EML content at a game start.',
  };
  log.textContent = text || none[logWhich] || '';
  log.scrollTop = log.scrollHeight;
}

// ---- the Nexus account, the nxm:// setting and downloads ----
// The key is checked and kept by the host (DPAPI); the page only hears "set" or "not set", the name and Premium.
// Without the Nexus features (nexusOn) there is no account card, no nxm:// setting and no Download with EMF.
const isPremium = () => nexusOn() && !!(account && account.user && account.user.premium);
const nxmOurs = () => nexusOn() && !!(account && account.nxm && account.nxm.ours);
const downloading = () => !!(download && download.state === 'running');
const fmtCount = (n) => (n >= 0 ? new Intl.NumberFormat('en').format(n) : '?');

function filePage(modId, fileId) {
  return 'https://www.nexusmods.com/enshrouded/mods/' + modId + '?tab=files&file_id=' + fileId;
}

function renderNexusChip() {
  const chip = $('nexus-chip');
  chip.hidden = !account || !nexusOn();
  if (chip.hidden) return;
  chip.className = 'nexus-chip' + (account.user ? ' ok' : '');
  chip.textContent = account.user ? account.user.name + (account.user.premium ? ' · Premium' : '') : account.key_set ? 'Nexus: key set' : 'Nexus: not logged in';
  chip.title = account.key_set ? 'Your Nexus account in EMF' : 'Set your Nexus API key to download with EMF';
}

function showAccount() {
  selectTab('emf');
  const t = $('account-title');
  if (t && t.scrollIntoView) t.scrollIntoView({ block: 'start' });
}

function renderAccount() {
  const box = $('account');
  box.hidden = $('account-title').hidden = !nexusOn();  // Nexus off: no account card
  if (box.hidden) {
    fill(box);
    renderNxm();
    return;
  }
  if (!account) {
    fill(box, el('p', { class: 'muted' }, 'Loading…'));
    return;
  }
  const a = account;
  const busy = (text, extra) => el('p', { class: 'acct-busy' }, el('span', { class: 'spinner', 'aria-hidden': 'true' }), text, extra || null);
  const parts = [el('div', { class: 'acct-line' },
    el('span', { class: 'acct-label' }, 'API key'),
    el('strong', { id: 'acct-key-state', class: a.key_set ? 'good' : '' }, a.key_set ? 'set' : 'not set'),
    a.user ? el('span', { class: 'acct-user' }, 'Logged in as ', el('bdi', {}, a.user.name)) : null,
    a.user ? el('span', { class: 'badge ' + (a.user.premium ? 'premium' : 'quiet'), id: 'acct-premium' }, a.user.premium ? 'Premium' : 'Free account') : null,
    a.user && a.user.supporter && !a.user.premium ? el('span', { class: 'badge quiet' }, 'Supporter') : null)];
  if (a.checking) parts.push(busy('Checking the key with Nexus…'));
  if (a.sso && a.sso.running) {
    parts.push(busy('Waiting for you to authorise EMF on nexusmods.com, in your browser… ',
      el('button', { class: 'ghost small', type: 'button', onclick: () => send({ cmd: 'sso_cancel' }) }, 'Cancel')));
  }
  if (a.error) parts.push(el('div', { class: 'd-error', role: 'alert', id: 'acct-error' }, el('span', {}, a.error)));
  if (a.note) parts.push(el('p', { class: 'd-note' }, a.note));
  if (a.waiting) parts.push(el('div', { class: 'sheet-warn', role: 'status', id: 'acct-waiting' }, 'A Mod Manager Download link is waiting: set your key, and EMF downloads the file.'));
  if (a.key_set) {
    parts.push(el('div', { class: 'row' },
      el('button', { class: 'ghost', type: 'button', disabled: a.checking, onclick: () => send({ cmd: 'account_check' }) }, 'Check again'),
      el('button', { class: 'ghost danger', type: 'button', id: 'acct-logout', onclick: () => send({ cmd: 'account_logout' }) }, 'Log out')));
    if (a.user) {
      parts.push(el('p', { class: 'muted small' }, (a.user.premium
        ? 'Premium: “Download with EMF” on a file in Browse downloads it here. '
        : 'Free account: click Mod Manager Download on a file’s page on Nexus, and EMF downloads it. ') + 'Checked ' + a.user.checked_at + '.'));
    }
  } else if (a.personal_key === false) {  // a build with the application slug: players log in on nexusmods.com
    parts.push(el('div', { class: 'row' }, a.sso && a.sso.available && !a.sso.running
      ? el('button', { class: 'primary', id: 'sso-start', type: 'button', onclick: () => send({ cmd: 'sso_start' }) }, 'Log in with Nexus') : null));
    parts.push(el('p', { class: 'muted small' }, 'Log in with Nexus opens nexusmods.com in your browser; after you allow EMF there, Nexus gives EMF a key. EMF keeps it encrypted for your Windows user and sends it only to api.nexusmods.com.'));
  } else {
    const save = () => {
      const k = keyInput.value.trim();
      if (!k) { keyInput.focus(); return; }
      send({ cmd: 'account_key', key: k });
      keyInput.value = '';
    };
    keyInput.onkeydown = (e) => { if (e.key === 'Enter') { e.preventDefault(); save(); } };
    parts.push(el('div', { class: 'acct-form' }, keyInput,
      el('button', { class: 'primary', type: 'button', id: 'acct-save', disabled: a.checking, onclick: save }, 'Save key')));
    parts.push(el('div', { class: 'row' },
      el('button', { class: 'ghost small', type: 'button', title: KEYS_URL, onclick: () => send({ cmd: 'open_url', url: KEYS_URL }) }, 'Get your personal API key on nexusmods.com'),
      a.sso && a.sso.available && !a.sso.running
        ? el('button', { class: 'primary small', id: 'sso-start', type: 'button', onclick: () => send({ cmd: 'sso_start' }) }, 'Log in with Nexus') : null));
    parts.push(el('p', { class: 'muted small' }, 'On that page, under “Personal API Key”, copy the key and paste it here. EMF keeps it encrypted for your Windows user and sends it only to api.nexusmods.com.'));
  }
  if (a.rate && a.rate.known) {
    parts.push(a.rate.exhausted
      ? el('div', { class: 'd-error', role: 'alert', id: 'acct-rate' }, el('span', {}, a.rate.message))
      : el('p', { class: 'muted small', id: 'acct-rate' }, 'Requests Nexus allows your account: ' + fmtCount(a.rate.daily) + ' left today, ' + fmtCount(a.rate.hourly) + ' this hour.'));
  }
  parts.push(el('div', { class: 'row acct-downloads' },
    el('span', { class: 'muted small', title: a.downloads }, 'Downloads go to ', el('bdi', { class: 'mono' }, a.downloads || '(none)')),
    a.downloads ? el('button', { class: 'ghost small', type: 'button', onclick: () => send({ cmd: 'open_downloads' }) }, 'Show downloads') : null));
  const typing = document.activeElement === keyInput;  // keep the keyboard in the key field
  fill(box, parts);
  if (typing && document.contains(keyInput)) keyInput.focus();
  renderNxm();
}

function renderNxm() {
  const box = $('nxm-setting');
  const n = account && account.nxm;
  const show = !!(n && n.available);
  box.hidden = !show;
  $('nxm-title').hidden = !show;
  if (!show) return;
  const owner = n.ours ? 'EMF (this copy)' : n.owner === 'nothing' ? 'nothing yet' : n.owner;
  const parts = [el('p', {}, 'Nexus’s “Mod Manager Download” button opens nxm:// links. On this PC they open in: ',
    el('strong', { id: 'nxm-owner', title: n.program || '' }, owner), n.machine ? ' (set for all users)' : '')];
  if (n.ours) {
    const back = n.previous && n.previous !== 'nothing' ? n.previous : '';
    parts.push(el('p', { class: 'muted small' }, !nexusOn()
      ? 'A testing version of EMF took them. This version doesn’t download from Nexus, so it has no use for them: ' +
        (back ? 'give them back to ' + back + '.' : 'stop opening them.')
      : back
        ? 'EMF saved ' + back + '’s setting and puts it back when you give the links back. EMF opens only Enshrouded links; it refuses the others.'
        : 'Nothing opened them before EMF. EMF opens only Enshrouded links; it refuses the others.'));
    parts.push(el('div', { class: 'row' }, el('button', { class: 'ghost', id: 'nxm-toggle', type: 'button', onclick: () => send({ cmd: 'nxm_give_back' }) },
      back ? 'Give them back to ' + back : 'Stop opening them')));
  } else {
    parts.push(el('p', { class: 'muted small' }, 'Vortex and Mod Organizer 2 use these links too, for every game. EMF opens only Enshrouded links and refuses the others, and it keeps the current setting so you can give the links back with one click.'));
    parts.push(el('div', { class: 'row' }, el('button', { class: 'primary', id: 'nxm-toggle', type: 'button', onclick: () => send({ cmd: 'nxm_take' }) },
      n.owner === 'nothing' ? 'Let EMF open them' : 'Let EMF open them instead of ' + n.owner)));
  }
  fill(box, parts);
}

function onDownload(m) {
  // a refusal before a download starts (a second link while one runs): a message; the running download keeps its bar
  if (download && download.state === 'running' && m.id !== download.id && m.state === 'failed') {
    toast(m.error, true);
    return;
  }
  clearTimeout(downloadHide);
  download = m;
  if (m.state === 'need_key') {
    toast(m.error, false);
    showAccount();
    setTimeout(() => { if (document.contains(keyInput)) keyInput.focus(); }, 0);
  } else if (m.state === 'done' || m.state === 'cancelled') {
    downloadHide = setTimeout(() => { download = null; renderDownload(); if (tab === 'browse') renderBrowseDetails(true); }, m.state === 'done' ? 6000 : 3000);
  }
  renderDownload();
  if (tab === 'browse') renderBrowseDetails(true);
  if (m.state !== updates.downloadState) {  // started or ended, not every progress step
    updates.downloadState = m.state;
    updatesRedraw();
  }
}

// A sheet the player is looking at (not the "Unpacking" sheet of a download's own plan).
function sheetInTheWay() {
  return !!modal && !(modal.mode === 'busy' && modal.fromDownload);
}

// "Show plan": the waiting plan, after closing the sheet that was in the way (the player asked for it).
function showWaitingPlan() {
  if (modal && modal.mode !== 'busy') closeModal();
  if (waitingPlan) {
    const p = waitingPlan;
    waitingPlan = null;
    showModal({ mode: 'plan', plan: p, fromDownload: true, shownAt: Date.now() });
  } else if (readyDownload) {
    send({ cmd: 'download_plan', id: readyDownload.id });
    readyDownload = null;
  }
  renderDownload();
}

function renderDownload() {
  const bar = $('download');
  const d = download && download.state !== 'need_key' ? download : null;
  const waiting = waitingPlan || readyDownload;
  if (!d && !waiting) {
    bar.hidden = true;
    return;
  }
  if (!d) {  // only a plan that waits
    const name = waitingPlan ? waitingPlan.name : (readyDownload.file || readyDownload.name);
    bar.className = 'download-bar done';
    fill(bar, el('div', { class: 'dl-title good' }, 'A download is ready: ', el('bdi', {}, name)),
      el('div', { class: 'dl-foot' }, el('span', { class: 'dl-meta' }, 'Nothing is copied until you click Install.'),
        el('button', { class: 'primary small', id: 'download-show-plan', type: 'button', onclick: showWaitingPlan }, 'Show plan')));
    bar.hidden = false;
    return;
  }
  const what = d.file || d.name || (d.file_id ? 'file ' + d.file_id : 'the file');
  const dismiss = el('button', { class: 'ghost small', type: 'button', onclick: () => { download = null; renderDownload(); } }, 'Dismiss');
  let body;
  if (d.state === 'running') {
    body = [
      el('div', { class: 'dl-title' }, el('span', { class: 'spinner', 'aria-hidden': 'true' }), 'Downloading ', el('bdi', {}, what)),
      el('progress', { max: d.total > 0 ? String(d.total) : null, value: d.total > 0 ? String(d.bytes) : null, 'aria-label': 'Download progress' }),
      el('div', { class: 'dl-foot' },
        el('span', { class: 'dl-meta' }, d.total > 0 ? sizeText(d.bytes) + ' of ' + sizeText(d.total) : d.bytes ? sizeText(d.bytes) : 'Asking Nexus for the file…'),
        el('button', { class: 'ghost small', id: 'download-cancel', type: 'button', onclick: () => send({ cmd: 'download_cancel' }) }, 'Cancel')),
    ];
  } else if (d.state === 'done') {
    body = [el('div', { class: 'dl-title good' }, 'Downloaded ', el('bdi', {}, what)),
      el('div', { class: 'dl-foot' }, el('span', { class: 'dl-meta' }, sizeText(d.bytes) + '. EMF checks it now; nothing is copied until you click Install.'),
        waiting ? el('button', { class: 'primary small', id: 'download-show-plan', type: 'button', onclick: showWaitingPlan }, 'Show plan') : dismiss)];
  } else if (d.state === 'cancelled') {
    body = [el('div', { class: 'dl-foot' }, el('span', { class: 'dl-title' }, 'Download cancelled'), dismiss)];
  } else {
    body = [el('div', { class: 'dl-title bad' }, 'Not downloaded'), el('p', { class: 'dl-error', id: 'download-error' }, d.error),
      el('div', { class: 'dl-foot' },
        d.page ? el('button', { class: 'primary small', type: 'button', onclick: () => send({ cmd: 'open_url', url: d.page }) }, 'Open the file on Nexus') : el('span', {}),
        dismiss)];
  }
  bar.className = 'download-bar ' + d.state;
  fill(bar, body);
  bar.hidden = false;
}

// ---- Browse: mods on Nexus Mods ----
// The host asks Nexus on a worker thread; each request carries a seq, and an answer to an older one is ignored.
const PAGE = 20;
const browse = {
  started: false, text: '', sort: 'downloads', offset: 0, seq: 0, loading: false, error: '', total: 0, mods: [],
  selected: null, page: null, pageSeq: 0, pageLoading: false, pageError: '', fileSeq: 0, checking: new Set(), drawn: '',
  olderOpen: false,
};
const numbers = new Intl.NumberFormat('en');
const ICON = {
  down: 'M7 1.5h2v7.3l2.6-2.6 1.4 1.4L8 12.6 3 7.6l1.4-1.4L7 8.8zM2.5 13h11v1.5h-11z',
  heart: 'M8 14.4l-1.1-1C3 9.9.6 7.7.6 4.9.6 2.7 2.3 1 4.5 1 5.8 1 7 1.6 8 2.6 9 1.6 10.2 1 11.5 1c2.2 0 3.9 1.7 3.9 3.9 0 2.8-2.4 5-6.3 8.5z',
  arrow: 'M2 7.2h9.1L7.6 3.7 8.7 2.6 14.1 8l-5.4 5.4-1.1-1.1 3.5-3.5H2z',
};

function icon(name) {
  const ns = 'http://www.w3.org/2000/svg';
  const svg = document.createElementNS(ns, 'svg');
  svg.setAttribute('viewBox', '0 0 16 16');
  svg.setAttribute('aria-hidden', 'true');
  svg.setAttribute('class', 'icon');
  const path = document.createElementNS(ns, 'path');
  path.setAttribute('d', ICON[name]);
  svg.append(path);
  return svg;
}

function ago(iso) {
  const t = Date.parse(iso);
  if (!t) return '';
  const s = Math.max(0, (Date.now() - t) / 1000);
  if (s < 3600) return Math.max(1, Math.round(s / 60)) + ' min ago';
  if (s < 86400) return Math.round(s / 3600) + ' h ago';
  const days = Math.round(s / 86400);
  if (days < 45) return days + (days === 1 ? ' day ago' : ' days ago');
  const months = Math.round(days / 30.4);
  return months < 18 ? months + ' months ago' : Math.round(days / 365) + ' years ago';
}

function sizeText(bytes) {
  if (!bytes) return '';
  if (bytes < 1024 * 1024) return Math.max(1, Math.round(bytes / 1024)) + ' KB';
  return (bytes / (1024 * 1024)).toFixed(bytes < 10 * 1024 * 1024 ? 1 : 0) + ' MB';
}

function dayText(unix) {
  return unix ? new Date(unix * 1000).toISOString().slice(0, 10) : '';
}

function initials(name) {
  return (String(name).match(/[A-Za-z0-9]+/g) || ['?']).slice(0, 3).map((w) => w[0].toUpperCase()).join('');
}

// A picture from Nexus (the host allows only image_hosts); a broken one becomes the mod's initials.
function picture(url, name) {
  const img = el('img', { src: url, alt: '', loading: 'lazy', decoding: 'async', referrerpolicy: 'no-referrer' });
  img.addEventListener('error', () => img.replaceWith(el('span', { class: 'thumb-empty' }, initials(name))));
  return img;
}

// Nexus mod ids the folder has: nexus_id in a mod.json, or an install EMF.exe recorded.
function installedIds() {
  const ids = new Set();
  if (!state) return ids;
  for (const m of state.mods) if (/^\d+$/.test(m.nexus_id)) ids.add(m.nexus_id);
  for (const i of state.installed || []) if (i.nexus_id) ids.add(i.nexus_id);
  return ids;
}

function search(offset) {
  if (!nexusOn()) return;  // no Nexus request in this build
  browse.started = true;
  browse.offset = Math.max(0, offset);
  browse.loading = true;
  browse.error = '';
  browse.seq += 1;
  send({ cmd: 'nexus_search', text: browse.text, sort: browse.sort, offset: browse.offset, seq: browse.seq });
  renderBrowse();
}

function onSearch(m) {
  if (m.seq !== browse.seq) return;  // an older search
  browse.loading = false;
  browse.error = m.ok ? '' : (m.error || 'Nexus did not answer.');
  if (m.ok) {
    browse.mods = m.mods;
    browse.total = m.total;
  }
  renderBrowse();
  const list = document.querySelector('.browse-list');
  if (list) list.scrollTop = 0;
}

function openMod(id) {
  browse.selected = id;
  browse.page = null;
  browse.pageLoading = true;
  browse.pageError = '';
  browse.pageSeq += 1;
  browse.checking.clear();
  browse.olderOpen = false;
  send({ cmd: 'nexus_mod', id, seq: browse.pageSeq });
  renderBrowse();
}

function onModPage(m) {
  if (m.seq !== browse.pageSeq) return;  // the player opened another mod since
  browse.pageLoading = false;
  browse.pageError = m.ok ? '' : (m.error || 'Nexus did not answer.');
  browse.page = m.ok ? m : null;
  renderBrowseDetails(true);
  $('browse-details').scrollTop = 0;
}

function checkFile(f) {
  browse.fileSeq += 1;
  browse.checking.add(f.file_id);
  send({ cmd: 'nexus_file', mod_id: browse.selected, file_id: f.file_id, seq: browse.fileSeq });
  renderBrowseDetails(true);
}

function onFile(m) {
  if (!browse.page || !browse.page.mod || m.mod_id !== browse.page.mod.id) return;
  browse.checking.delete(m.file.file_id);
  const f = browse.page.files.find((x) => x.file_id === m.file.file_id);
  if (f) {
    for (const k of ['checked', 'listed', 'error', 'entries', 'kind', 'kind_label', 'also', 'notes']) f[k] = m.file[k];
  }
  renderBrowseDetails(true);
}

function renderBrowse() {
  if (!browse.started) return search(0);  // opening the page is the first search
  $('browse-fineprint').textContent = 'Mods, pictures and descriptions come from Nexus Mods. ' + (isPremium()
    ? 'Download a file with EMF, or install one you downloaded: '
    : 'Download a file on Nexus (its Mod Manager Download button sends it to EMF when EMF opens nxm:// links), or install one you downloaded: ') +
    'EMF checks it before anything is copied.';
  const status = $('browse-status');
  const cards = $('browse-cards');
  const pager = $('browse-pager');
  if (browse.loading) {
    fill(status, el('span', { class: 'spinner', 'aria-hidden': 'true' }), 'Searching Nexus Mods…');
  } else if (browse.error) {
    fill(status, el('div', { class: 'd-error', role: 'alert' }, el('span', {}, 'Could not search Nexus Mods: ' + browse.error),
      el('button', { class: 'ghost small', type: 'button', onclick: () => search(browse.offset) }, 'Try again')));
  } else {
    const sortName = { downloads: 'most downloaded', endorsements: 'most endorsed', updated: 'recently updated' }[browse.sort];
    fill(status, browse.total
      ? el('span', {}, numbers.format(browse.total) + (browse.total === 1 ? ' mod' : ' mods') +
        (browse.text ? ' matching “' + browse.text + '”' : ' for Enshrouded') + ', ' + sortName + ' first')
      : el('span', {}, browse.text ? 'No mods match “' + browse.text + '”. Nexus matches whole words of the name.' : 'No mods found.'));
  }

  // the cards are drawn anew: keep the keyboard on the card it was on
  const active = document.activeElement;
  const focusId = active && active.classList && active.classList.contains('mod-card') ? active.dataset.id : null;
  const have = installedIds();
  if (browse.loading && !browse.mods.length) {
    fill(cards, Array.from({ length: 6 }, () => el('div', { class: 'mod-card ghostly', 'aria-hidden': 'true' },
      el('div', { class: 'thumb' }), el('div', { class: 'card-body' }, el('div', { class: 'bar-l' }), el('div', { class: 'bar-s' })))));
  } else {
    fill(cards, browse.mods.map((m) => modCard(m, have.has(String(m.id)))));
    cards.classList.toggle('stale', browse.loading);
  }
  if (focusId) {
    const again = cards.querySelector('.mod-card[data-id="' + CSS.escape(focusId) + '"]');
    if (again) again.focus();
  }
  const from = browse.offset + 1, to = browse.offset + browse.mods.length;
  fill(pager, browse.total > PAGE || browse.offset > 0 ? [
    el('button', { class: 'ghost small', type: 'button', disabled: browse.offset === 0 || browse.loading, onclick: () => search(browse.offset - PAGE) }, '‹ Previous'),
    el('span', { class: 'pager-text' }, browse.mods.length ? from + '–' + to + ' of ' + numbers.format(browse.total) : ''),
    el('button', { class: 'ghost small', type: 'button', disabled: to >= browse.total || browse.loading, onclick: () => search(browse.offset + PAGE) }, 'Next ›'),
  ] : []);
  renderBrowseDetails(false);
}

function modCard(m, installed) {
  const selectedNow = m.id === browse.selected;
  return el('article', {
    class: 'mod-card' + (selectedNow ? ' selected' : ''), role: 'button', tabindex: '0', 'aria-pressed': String(selectedNow),
    'data-id': String(m.id), 'aria-label': m.name,
    onclick: () => openMod(m.id),
    onkeydown: (e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); openMod(m.id); } },
  },
  el('div', { class: 'thumb' + (m.adult ? ' adult' : '') }, m.thumbnail ? picture(m.thumbnail, m.name) : el('span', { class: 'thumb-empty' }, initials(m.name))),
  el('div', { class: 'card-body' },
    el('div', { class: 'card-title' }, el('span', { class: 'card-name' }, m.name),
      installed ? el('span', { class: 'badge ok', title: 'This folder has it (a mod.json with its Nexus id, or an install EMF recorded)' }, 'Installed') : null,
      m.adult ? el('span', { class: 'badge warn' }, '18+') : null),
    el('div', { class: 'card-by' }, 'by ' + (m.author || 'unknown') + (m.version ? ' · ' + vtext(m.version) : '')),
    m.summary ? el('p', { class: 'card-summary' }, m.summary) : null,
    el('div', { class: 'card-stats' },
      el('span', { title: 'Downloads' }, icon('down'), numbers.format(m.downloads)),
      el('span', { title: 'Endorsements' }, icon('heart'), numbers.format(m.endorsements)),
      m.updated ? el('span', { class: 'card-when', title: 'Updated ' + m.updated }, ago(m.updated)) : null)));
}

const CATEGORY = { MAIN: 'Main', OPTIONAL: 'Optional', UPDATE: 'Update', MISCELLANEOUS: 'Misc', OLD_VERSION: 'Old version', ARCHIVED: 'Archived', REMOVED: 'Removed' };

function fileCard(f) {
  const old = ['OLD_VERSION', 'ARCHIVED', 'REMOVED'].includes(f.category);
  const looking = browse.checking.has(f.file_id);
  let inside;
  if (!f.checked) {
    inside = el('button', { class: 'ghost small', type: 'button', disabled: looking, onclick: () => checkFile(f) },
      looking ? 'Looking inside…' : 'Check what’s inside');
  } else if (f.error) {
    inside = el('p', { class: 'file-error' }, 'Could not look inside: ' + f.error);
  } else if (!f.listed) {
    inside = el('p', { class: 'file-unlisted' }, 'Nexus doesn’t list this file’s contents; EMF checks the archive when you install it.');
  } else {
    inside = [
      el('div', { class: 'file-kind' }, el('span', { class: 'badge kind' }, f.kind_label),
        (f.also || []).map((a) => el('span', { class: 'badge quiet' }, 'also ' + a))),
      f.notes && f.notes.length ? el('ul', { class: 'notes' }, f.notes.map((n) => el('li', {}, n))) : null,
    ];
  }
  // Premium members download with EMF; free accounts go to the file's page (Nexus's rule: its Mod Manager Download
  // button sends the file to EMF when EMF opens nxm:// links)
  const mod = browse.page && browse.page.mod;
  const modId = mod ? mod.id : browse.selected;
  let get = null;
  if (f.category !== 'REMOVED') {
    get = isPremium()
      ? el('button', {
        class: 'primary small', type: 'button', 'data-download': String(f.file_id), disabled: downloading(),
        title: downloading() ? 'EMF is downloading another file' : 'Download this file with EMF, then see what it installs before anything is copied',
        onclick: () => send({ cmd: 'nexus_download', mod_id: modId, file_id: f.file_id, name: mod ? mod.name : '' }),
      }, 'Download with EMF')
      : el('button', {
        class: 'ghost small', type: 'button', 'data-download': String(f.file_id),
        title: 'Nexus gives free accounts downloads on its website: click Mod Manager Download on the file’s page' + (nxmOurs() ? ', and EMF downloads it' : ''),
        onclick: () => send({ cmd: 'open_url', url: filePage(modId, f.file_id) }),
      }, 'Download on Nexus');
  }
  return el('div', { class: 'file' + (old ? ' old' : ''), 'data-file': String(f.file_id) },
    el('div', { class: 'file-head' },
      el('span', { class: 'file-name' }, f.name || 'File ' + f.file_id),
      f.version ? el('span', { class: 'mod-version' }, f.version) : null,
      el('span', { class: 'badge cat ' + String(f.category).toLowerCase() }, CATEGORY[f.category] || f.category)),
    el('div', { class: 'file-meta' }, [sizeText(f.size), dayText(f.date)].filter(Boolean).join(' · ')),
    inside,
    get ? el('div', { class: 'file-actions' }, get) : null);
}

// The current files, then the older ones (old versions, archived, removed) folded away: a mod can have dozens.
function fileList(files) {
  const OLD = ['OLD_VERSION', 'ARCHIVED', 'REMOVED'];
  const current = files.filter((f) => !OLD.includes(f.category));
  const older = files.filter((f) => OLD.includes(f.category));
  let box = null;
  if (older.length) {
    box = el('details', { class: 'older', open: browse.olderOpen },
      el('summary', {}, older.length + (older.length === 1 ? ' older file' : ' older files')), older.map(fileCard));
    box.addEventListener('toggle', () => { browse.olderOpen = box.open; });
  }
  return [current.map(fileCard), box];
}

// The description: safe HTML from the host (bbcode.h), inside its own container. Links open in the browser through the
// host; a picture that does not load is left out.
function description(html) {
  const box = el('div', { class: 'bb' });
  box.innerHTML = html;
  for (const a of box.querySelectorAll('a[href]')) {
    a.addEventListener('click', (e) => {
      e.preventDefault();
      send({ cmd: 'open_url', url: a.getAttribute('href'), external: true });
    });
  }
  for (const img of box.querySelectorAll('img')) img.addEventListener('error', () => img.remove());
  return box;
}

function renderBrowseDetails(force) {
  const d = $('browse-details');
  const have = installedIds();
  const key = JSON.stringify([browse.selected, browse.pageSeq, browse.pageLoading, browse.pageError, browse.page && browse.page.files,
    [...browse.checking], browse.selected !== null && have.has(String(browse.selected)), isPremium(), nxmOurs(), downloading()]);
  if (!force && key === browse.drawn) return;
  browse.drawn = key;
  if (browse.selected === null) {
    fill(d, el('div', { class: 'details-empty' },
      el('p', {}, 'Choose a mod to see its page, its files and what each file would do in this folder.'),
      el('p', { class: 'muted' }, 'Then download the file on Nexus and install it here with “Install a downloaded file”.')));
    return;
  }
  if (browse.pageLoading) {
    fill(d, el('div', { class: 'loading' }, el('span', { class: 'spinner', 'aria-hidden': 'true' }), 'Loading the mod’s page from Nexus Mods…'));
    return;
  }
  if (!browse.page) {
    fill(d, el('div', { class: 'd-error', role: 'alert' }, el('span', {}, 'Could not load the mod’s page: ' + browse.pageError),
      el('button', { class: 'ghost small', type: 'button', onclick: () => openMod(browse.selected) }, 'Try again')));
    return;
  }
  const p = browse.page.mod;
  const files = browse.page.files || [];
  const meta = ['by ' + (p.author || 'unknown')];
  if (p.version) meta.push('version ' + p.version.replace(/^v/i, ''));
  if (p.updated) meta.push('updated ' + ago(p.updated));
  fill(d,
    p.picture ? el('div', { class: 'd-picture' + (p.adult ? ' adult' : '') }, picture(p.picture, p.name)) : null,
    el('div', { class: 'd-eyebrow' }, 'Nexus Mods' + (p.category ? ' · ' + p.category : '')),
    el('h2', { class: 'd-name' }, p.name),
    el('div', { class: 'd-meta' }, meta.join(' · ')),
    el('div', { class: 'd-badges' },
      have.has(String(p.id)) ? el('span', { class: 'badge ok' }, 'Installed') : null,
      p.adult ? el('span', { class: 'badge warn' }, 'Adult content') : null,
      el('span', { class: 'badge quiet stat', title: 'Downloads' }, icon('down'), numbers.format(p.downloads)),
      el('span', { class: 'badge quiet stat', title: 'Endorsements' }, icon('heart'), numbers.format(p.endorsements))),
    el('div', { class: 'd-actions' },
      el('button', { class: 'primary', type: 'button', title: p.url + '?tab=files', onclick: () => send({ cmd: 'open_url', url: p.url + '?tab=files' }) }, 'Open on Nexus'),
      el('button', { class: 'ghost', type: 'button', onclick: () => pickArchive({ id: p.id, name: p.name }) }, 'Install a downloaded file…')),
    el('p', { class: 'd-note' }, isPremium()
      ? 'Download with EMF on a file below: EMF downloads it and shows what it would install before anything is copied.'
      : nxmOurs()
        ? 'Download on Nexus opens the file’s page: click Mod Manager Download there, and EMF downloads it and shows what it would install.'
        : 'Download the file you want on the mod’s Files tab, then install it here. EMF checks the archive before it copies anything.'),
    p.summary ? el('p', { class: 'd-desc' }, p.summary) : null,
    el('div', { class: 'd-section files' }, el('h3', {}, 'Files'),
      files.length ? fileList(files) : el('p', { class: 'd-note' }, browse.page.files_error ? 'Could not list the files: ' + browse.page.files_error : 'Nexus lists no files for this mod.')),
    p.description_html ? el('div', { class: 'd-section' }, el('h3', {}, 'Description'), description(p.description_html)) : null);
}

// ---- installing a downloaded file, uninstalling ----
let modal = null;        // {mode: 'busy' | 'plan' | 'done' | 'confirm', ...}
let modalDrawn = '';
let modalReturn = null;  // where the keyboard goes back to

function pickArchive(nexus) {
  send({ cmd: 'install_pick', nexus_id: nexus ? nexus.id : 0, nexus_name: nexus ? nexus.name : '' });
}

function showModal(m) {
  if (!modal) modalReturn = document.activeElement;
  modal = m;
  renderModal();
}

function closeModal() {
  if (modal && modal.mode === 'plan' && modal.plan) send({ cmd: 'install_cancel', plan_id: modal.plan.id });
  modal = null;
  modalDrawn = '';
  $('modal').hidden = true;
  if (modalReturn && modalReturn.focus && document.contains(modalReturn)) modalReturn.focus();
}

function onPlan(m) {
  if (!m.ok) showModal({ mode: 'done', ok: false, title: 'Not installed', error: m.error, lines: [] });
  else showModal({ mode: 'plan', plan: m.plan, fromDownload: !!m.from_download, shownAt: Date.now() });
  waitingPlan = null;  // the host keeps one plan: a held one is gone now
  renderDownload();
}

function onDone(m) {
  const install = m.type === 'install_done';
  showModal({
    mode: 'done', ok: m.ok, error: m.error, lines: m.lines || [],
    title: install ? (m.ok ? 'Installed' : 'Not installed') : (m.ok ? 'Uninstalled' : 'Not uninstalled'),
  });
}

function recordOf(key) {
  return state && (state.installed || []).find((i) => i.key === key);
}

// The other rows of one install (an EML folder and its DLL): Uninstall removes them too, so the details and the
// question name them. A record of several separate mods (EMF.exe 0.3.2 recorded the creature packs as one) uninstalls
// one mod folder at a time instead: none go with it.
function sameInstall(key, rowKey) {
  const r = recordOf(key);
  if (!state || (r && r.separable)) return [];
  return state.mods.filter((x) => x.install_key === key && keyOf(x) !== rowKey).map((x) => x.name);
}

// How many files of a record are in one of its mod folders (a record of several separate mods), else all of them.
function filesOf(r, root) {
  const i = root && r.separable && r.roots ? r.roots.indexOf(root) : -1;
  return i >= 0 && r.root_files ? r.root_files[i] : r.files;
}

function namesText(names) {
  return names.length < 2 ? names.join('') : names.slice(0, -1).join(', ') + ' and ' + names[names.length - 1];
}

function installedText(key, rowKey, root) {
  const r = recordOf(key);
  if (!r) return '';
  const others = sameInstall(key, rowKey);
  const n = filesOf(r, root);
  return 'Installed by EMF on ' + r.installed_at + ' from ' + r.archive + ' (' + n + (n === 1 ? ' file' : ' files') + ').' +
    (others.length ? ' Together with ' + namesText(others) + ', as one install: Uninstall removes them together.' : '');
}

// rowRoot: the row's mod folder, sent along when the record holds several separate mods (only that folder goes)
function confirmUninstall(key, rowKey, rowRoot, rowName) {
  const r = recordOf(key);
  const root = r && r.separable && rowRoot ? rowRoot : '';
  showModal({ mode: 'confirm', key, rowKey, root, rowName: root ? rowName : '' });
}

const ACTION = { install: 'Install', update: 'Update', skip: 'Not installed', refused: 'Not installed' };

function planPart(p) {
  return el('li', { class: 'part act-' + p.action },
    el('div', { class: 'part-head' },
      el('span', { class: 'badge act-' + p.action }, ACTION[p.action] || p.action),
      el('span', { class: 'part-label' }, p.label),
      p.title && p.title !== p.label ? el('span', { class: 'part-title' }, p.title + (p.version ? ' ' + p.version : '')) : null),
    p.target && (p.action === 'install' || p.action === 'update')
      ? el('div', { class: 'part-target' }, icon('arrow'), el('span', { class: 'mono' }, p.target)) : null,
    p.why ? el('p', { class: 'part-why' }, p.why) : null,
    p.lines.length ? el('ul', { class: 'part-lines' }, p.lines.map((l) => el('li', {}, l))) : null,
    p.copies.length ? el('details', { class: 'part-files' }, el('summary', {}, p.files === 1 ? '1 file' : p.files + ' files' + (p.bytes ? ', ' + sizeText(p.bytes) : '')),
      el('ul', {}, p.copies.map((c) => el('li', { class: 'mono' }, c)), p.files > p.copies.length ? el('li', {}, '…') : null)) : null);
}

function renderModal() {
  const box = $('modal');
  if (!modal) {
    box.hidden = true;
    return;
  }
  if (modal.mode === 'add_server') { renderAddServer(); return; }  // the servers block
  const running = !!(state && state.game_running);
  const key = JSON.stringify([modal, running]);
  if (key === modalDrawn && !box.hidden) return;
  modalDrawn = key;
  const sheet = $('sheet');
  const close = (text) => el('button', { class: 'ghost', type: 'button', 'data-focus': 'close', onclick: closeModal }, text);
  let focus = null;
  if (modal.mode === 'busy') {
    fill(sheet, el('div', { class: 'sheet-busy' }, el('span', { class: 'spinner big', 'aria-hidden': 'true' }),
      el('h2', { id: 'sheet-title', class: 'sheet-title' }, modal.title), modal.text ? el('p', { class: 'muted' }, modal.text) : null));
  } else if (modal.mode === 'plan') {
    const p = modal.plan;
    const install = el('button', {
      class: 'primary', type: 'button', disabled: !p.installable || running,
      onclick: () => {
        if (Date.now() - (modal.shownAt || 0) < INSTALL_GUARD_MS) return;  // a click or Enter meant for what was there before
        const id = p.id;
        modal = null;  // the plan is in the host's hands now: no cancel when this closes
        send({ cmd: 'install_apply', plan_id: id });
        showModal({ mode: 'busy', title: 'Installing ' + p.name, text: 'Copying the files. Nothing is overwritten.' });
      },
    }, p.update ? 'Update' : 'Install');
    // a plan the player did not just ask for (a download's) keeps the keyboard off Install: the sheet's Cancel gets it
    focus = p.installable && !running && !modal.fromDownload ? install : null;
    fill(sheet,
      el('div', { class: 'sheet-head' },
        el('div', { class: 'd-eyebrow' }, 'Install a downloaded file'),
        el('h2', { id: 'sheet-title', class: 'sheet-title' }, p.name + (p.version ? ' ' + p.version : '')),
        el('div', { class: 'sheet-sub' }, el('span', { class: 'mono' }, p.archive),
          p.game ? el('span', { class: 'plan-into', title: p.game }, 'into ', el('bdi', { class: 'mono' }, p.game)) : null,
          p.kind_label ? el('span', { class: 'badge kind' }, p.kind_label) : null,
          p.update ? el('span', { class: 'badge warn', title: 'EMF installed an earlier version: it moves to emf\\backup first' }, 'Update') : null)),
      el('div', { class: 'sheet-body' },
        p.error ? el('div', { class: 'd-error', role: 'alert' }, el('span', {}, p.error)) : null,
        running ? el('div', { class: 'sheet-warn', role: 'status' }, 'Close the game first: mods are installed while the game is closed.') : null,
        p.parts.length ? [el('h3', { class: 'sheet-h' }, 'What goes where'), el('ul', { class: 'parts' }, p.parts.map(planPart))] : null,
        p.notes.length ? [el('h3', { class: 'sheet-h' }, 'Good to know'), el('ul', { class: 'notes' }, p.notes.map((n) => el('li', {}, n)))] : null,
        el('p', { class: 'fineprint' }, 'EMF never overwrites a file. It records every file it installs (emf\\installed_mods), so Uninstall removes exactly those.')),
      el('div', { class: 'sheet-foot' }, close('Cancel'), install));
  } else if (modal.mode === 'done') {
    fill(sheet,
      el('div', { class: 'sheet-head' },
        el('h2', { id: 'sheet-title', class: 'sheet-title ' + (modal.ok ? 'good' : 'bad') }, modal.title)),
      el('div', { class: 'sheet-body' },
        modal.error ? el('div', { class: 'd-error', role: 'alert' }, el('span', {}, modal.error), copyButton(() => modal.error)) : null,
        modal.lines.length ? el('ul', { class: 'part-lines done' }, modal.lines.map((l) => el('li', {}, l))) : null),
      el('div', { class: 'sheet-foot' }, close('OK')));
  } else if (modal.mode === 'confirm') {
    const r = recordOf(modal.key) || { name: modal.key, files: 0, chain: [] };
    const one = !!modal.root;  // one mod folder of a record of several separate mods
    const title = one ? modal.rowName || modal.root : r.name;
    const n = filesOf(r, modal.root);
    const go = el('button', {
      class: 'primary danger', type: 'button', disabled: running,
      onclick: () => {
        const k = modal.key;
        send(one ? { cmd: 'uninstall_mod', key: k, root: modal.root } : { cmd: 'uninstall_mod', key: k });
        showModal({ mode: 'busy', title: 'Uninstalling ' + title, text: 'Removing the files EMF installed.' });
      },
    }, 'Uninstall');
    focus = running ? null : go;
    fill(sheet,
      el('div', { class: 'sheet-head' },
        el('div', { class: 'd-eyebrow' }, 'Uninstall'),
        el('h2', { id: 'sheet-title', class: 'sheet-title' }, one ? title : r.name + (r.version ? ' ' + r.version : ''))),
      el('div', { class: 'sheet-body' },
        running ? el('div', { class: 'sheet-warn', role: 'status' }, 'Close the game first: mods are uninstalled while the game is closed.') : null,
        el('ul', { class: 'part-lines' },
          el('li', {}, 'Removes the ' + n + (n === 1 ? ' file' : ' files') + ' EMF installed' + (one ? ' in ' + modal.root : '') + ', where they are unchanged. A file that changed since is left in place and named.'),
          one ? el('li', {}, 'The other mods EMF installed from the same file (' + r.archive + ') stay.') : null,
          sameInstall(modal.key, modal.rowKey).length ? el('li', { class: 'also' }, 'Also uninstalls ' + namesText(sameInstall(modal.key, modal.rowKey)) +
            ': EMF installed them from the same file as one install.') : null,
          !one && r.outside && r.outside.length ? el('li', {}, 'Including files outside the mod’s own folder: ' + r.outside.join(', ') + '.') : null,
          !one && r.chain && r.chain.length ? el('li', {}, 'Takes ' + r.chain.join(', ') + ' out of dinput8-chain.ini.') : null,
          el('li', {}, 'Removes the folders it made once they are empty; a file another mod still uses is kept. Earlier versions in emf\\backup stay.'))),
      el('div', { class: 'sheet-foot' }, close('Cancel'), go));
  }
  box.hidden = false;
  (focus || sheet.querySelector('[data-focus="close"]') || sheet).focus();
}

// ---- dedicated servers: the folder switcher in the header and the Server tab ----
// The host reads the server's enshrouded_server.json (passwords only as "set" or not), EMF's [chat] settings in
// emf\emf_core.ini and the process; the page draws them and sends folder_* and server_* commands
// (app/server_bridge.h). The logs come every two seconds while the Server tab is open, passwords already stripped.
const srv = {
  logs: { server: '', core: '', server_path: '', core_path: '' },
  logWhich: 'server',
  logTimer: 0,
  stop: null,      // the last server_stop progress message
  found: null,     // the server folders Steam has (the add sheet)
  everyone: null,  // the switch while it differs from what is saved (null: as saved)
  gameAdmins: null, // the game's admins switch while it differs from what is saved (null: as saved)
  dirty: false,    // the admins box has changes that are not saved
  refuse: null,    // the players' mods choice while it differs from what is saved (null: as saved)
  modsDirty: false, // the mods boxes have changes that are not saved
  drawn: '',
  switchKey: '',
  game: null,      // the folder the tab was drawn for
};
// The admins box and the log are made once and kept, so drawing the tab again never loses what the player types or
// where the log is scrolled.
const adminsBox = el('textarea', {
  id: 'srv-admins', rows: '4', spellcheck: 'false', autocomplete: 'off', placeholder: '0x00ab00cd00ef0011',
  'aria-label': 'Admins: account hashes, one per line',
});
adminsBox.addEventListener('input', () => {
  srv.dirty = true;
  const note = $('srv-chat-note');
  if (note) note.textContent = 'Not saved yet.';
});
// The players' mods card keeps its two boxes the same way.
const modsBox = el('textarea', {
  id: 'srv-mods-required', rows: '3', spellcheck: 'false', autocomplete: 'off', placeholder: 'beastmaster',
  'aria-label': 'Mods every player must have, one id per line',
});
const modsInfoBox = el('input', {
  id: 'srv-mods-info', type: 'text', maxlength: '200', autocomplete: 'off', spellcheck: 'false',
  'aria-label': 'Where to get the mods, said to refused players',
});
const modsTyped = () => {
  srv.modsDirty = true;
  const note = $('srv-mods-note');
  if (note) note.textContent = 'Not saved yet.';
};
modsBox.addEventListener('input', modsTyped);
modsInfoBox.addEventListener('input', modsTyped);
const serverLogBox = el('pre', { class: 'log', id: 'srv-log', tabindex: '0' });

function onServerMessage(m) {
  if (m.type === 'server_detect') {
    srv.found = m.found || [];
    showModal({ mode: 'add_server' });
    return true;
  }
  if (m.type === 'server_stop') {
    srv.stop = m.state === 'progress' ? m : null;
    if (m.state === 'ask') {  // other programs share the server's console: Ctrl+C would reach them too
      if (window.confirm(m.text)) send({ cmd: 'server_stop', shared_ok: true });
    } else if (m.state === 'done') toast(m.text, false);
    else if (m.state === 'failed') toast(m.text, true);
    srv.drawn = '';
    if (state) renderServers();
    return true;
  }
  if (m.type === 'server_install') {
    showModal({
      mode: 'done', ok: m.ok, error: m.error, lines: m.lines || [],
      title: m.ok ? 'EMF installed into the server' : 'EMF not installed',
    });
    return true;
  }
  if (m.type === 'server_logs') {
    srv.logs = m;
    renderServerLog();
    return true;
  }
  if (m.type === 'closing') {
    showModal({ mode: 'busy', title: 'Closing EMF', text: m.text });
    return true;
  }
  if (m.type === 'closing_failed') {
    if (modal && modal.mode === 'busy') closeModal();
    toast(m.text, true);
    srv.drawn = '';
    if (state) renderServers();
    return true;
  }
  if (m.type === 'result') {
    if (m.cmd === 'server_chat_save' && m.ok) {
      srv.dirty = false;
      srv.everyone = null;
      srv.gameAdmins = null;
    }
    if (m.cmd === 'server_mods_save' && m.ok) {
      srv.modsDirty = false;
      srv.refuse = null;
    }
    if (m.cmd === 'server_install_emf' && !m.ok && modal && modal.mode === 'busy') closeModal();
    if (m.cmd === 'folder_switch' && !m.ok) {  // the list shows the folder shown again
      srv.switchKey = '';
      if (state) renderServers();
    }
  }
  return false;  // results go on to onResult (the toast)
}

// A mod row's badge in a server folder: where it has to run.
function serverBadge(m) {
  if (!state || !state.server || !m.server_note) return null;
  if (m.side === 'client') return el('span', { class: 'badge warn', title: m.server_note }, 'Not for servers');
  if (m.side === 'server' && m.side_declared) return el('span', { class: 'badge ok', title: m.server_note }, 'Server-side');
  if (m.side_declared) return el('span', { class: 'badge quiet', title: m.server_note }, 'Players need it too');
  return null;
}

function serverNote(m) {
  if (!state || !state.server || !m.server_note) return null;
  return el('p', { class: 'd-note srv-note ' + (m.server_level || 'info') }, 'Where it runs: ' + m.server_note);
}

function renderServers() {
  if (!state) return;
  const s = state;
  if (srv.game !== s.game) {  // another folder: what was typed or switched for the last one does not carry over
    srv.game = s.game;
    srv.dirty = false;
    srv.everyone = null;
    srv.gameAdmins = null;
    srv.modsDirty = false;
    srv.refuse = null;
    srv.stop = null;
    srv.logs = { server: '', core: '', server_path: '', core_path: '' };
    srv.drawn = '';
    if (document.activeElement === adminsBox) adminsBox.blur();
    if (document.activeElement === modsBox) modsBox.blur();
    if (document.activeElement === modsInfoBox) modsInfoBox.blur();
  }
  // the folder switcher: Game, Server: <name>, ..., Add a server folder...
  const sel = $('folder-switch');
  const folders = s.folders || [];
  const key = JSON.stringify(folders);
  if (key !== srv.switchKey || sel.value === 'add') {
    srv.switchKey = key;
    const current = folders.find((f) => f.current);
    fill(sel,
      folders.map((f) => el('option', { value: 'f:' + f.path, selected: !!f.current, title: f.path }, f.label + (f.missing ? ' (missing)' : ''))),
      current ? null : el('option', { value: '', selected: true }, 'This folder'),
      el('option', { value: 'add' }, 'Add a server folder…'));
  }
  sel.hidden = !s.game_found && !folders.length;
  $('folder-eyebrow').textContent = s.server ? 'Server folder' : 'Game folder';
  $('change-folder').hidden = !!s.server;  // Change picks the game's folder; servers come from the list

  // the Server tab
  $('tab-server').hidden = !s.server;
  if (!s.server && tab === 'server') {
    selectTab('mods');
    return;
  }
  const show = tab === 'server' && !!s.server;
  $('page-server').hidden = !show;
  if (show) {
    renderServerPage();
    startServerLogs();
  } else {
    stopServerLogs();
  }
}

function startServerLogs() {
  if (srv.logTimer) return;
  send({ cmd: 'server_logs' });
  srv.logTimer = setInterval(() => {
    if (tab === 'server' && state && state.server && !document.hidden) send({ cmd: 'server_logs' });
  }, 2000);
}

function stopServerLogs() {
  if (!srv.logTimer) return;
  clearInterval(srv.logTimer);
  srv.logTimer = 0;
}

function renderServerLog() {
  const text = srv.logs[srv.logWhich] || '';
  const atEnd = serverLogBox.scrollTop + serverLogBox.clientHeight >= serverLogBox.scrollHeight - 8;
  const empty = srv.logWhich === 'server'
    ? 'No server log yet: the server writes logs\\enshrouded_server.log when it starts.'
    : 'No emf_core.log yet: EMF writes it when the server starts with EMF installed.';
  if (serverLogBox.textContent !== (text || empty)) {
    serverLogBox.textContent = text || empty;
    if (atEnd) serverLogBox.scrollTop = serverLogBox.scrollHeight;  // follow the end, unless the player scrolled up
  }
}

// "0.3.0" against "0.2.0": >0 newer, 0 the same, <0 older (numbers only; missing parts are 0).
function compareVersions(a, b) {
  const pa = String(a || '').split('.').map((x) => parseInt(x, 10) || 0);
  const pb = String(b || '').split('.').map((x) => parseInt(x, 10) || 0);
  for (let i = 0; i < Math.max(pa.length, pb.length); ++i) {
    const d = (pa[i] || 0) - (pb[i] || 0);
    if (d) return d;
  }
  return 0;
}

function fact(label, value) {
  return [el('dt', {}, label), el('dd', {}, value)];
}

function rights(g) {
  const may = [];
  if (g.can_kick_ban) may.push('kick and ban');
  if (g.can_access_inventories) may.push('open chests');
  if (g.can_edit_world) may.push('change the world');
  if (g.can_edit_base) may.push('build in bases');
  if (g.can_extend_base) may.push('extend bases');
  if (g.reserved_slots) may.push(g.reserved_slots + ' reserved slot' + (g.reserved_slots === 1 ? '' : 's'));
  return may.length ? may.join(', ') : 'visit only';
}

function radio(name, value, checked, label, onpick) {
  const input = el('input', { type: 'radio', name, value, checked });
  input.addEventListener('change', () => { if (input.checked) onpick(); });
  return el('label', { class: 'srv-radio' }, input, label);
}

function confirmKill() {
  if (window.confirm('Stop the server now? It ends at once without saving: what changed since its last autosave (up to 30 seconds) is lost.')) {
    send({ cmd: 'server_kill' });
  }
}

function renderServerPage() {
  const page = $('server-page');
  const s = state;
  const t = s.server_tab;
  if (!t) {
    fill(page);
    srv.drawn = '';
    return;
  }
  const chat = t.chat || { admins: [] };
  if (!srv.dirty && document.activeElement !== adminsBox) adminsBox.value = (chat.admins || []).join('\n');
  const mods = t.mods || { required: [] };
  if (!srv.modsDirty && document.activeElement !== modsBox) modsBox.value = (mods.required || []).join('\n');
  if (!srv.modsDirty && document.activeElement !== modsInfoBox) modsInfoBox.value = mods.info || '';
  const drawnNow = JSON.stringify([t, s.emf_installed, s.emf_version, s.game, srv.everyone, srv.gameAdmins, srv.logWhich, srv.stop, srv.dirty, srv.refuse, srv.modsDirty]);
  if (drawnNow === srv.drawn && page.childElementCount) {
    renderServerLog();
    return;
  }
  srv.drawn = drawnNow;
  const active = document.activeElement;
  const focusId = active && page.contains(active) && active.id ? active.id : '';
  const c = t.config || {};
  const p = t.process || {};
  const running = !!p.running;
  const stopping = !!t.stopping;

  // ---- start and stop ----
  const runCard = el('div', { class: 'card account', id: 'srv-run' },
    el('div', { class: 'acct-line' },
      el('span', { class: 'acct-label' }, 'Server'),
      el('strong', { class: running ? 'srv-good' : '', id: 'srv-running' }, running ? 'Running' : 'Stopped'),
      running ? el('span', { class: 'muted small', id: 'srv-pid' }, 'process ' + p.pid + (p.started_here ? ', started by this EMF.exe' : ', started outside this EMF.exe')) : null),
    el('div', { class: 'row' },
      el('button', { class: 'primary', type: 'button', id: 'srv-start', disabled: !t.can_start || s.game_running, onclick: () => send({ cmd: 'server_start' }) }, 'Start'),
      el('button', { class: 'ghost danger', type: 'button', id: 'srv-stop', disabled: !running || stopping, onclick: () => send({ cmd: 'server_stop' }) }, stopping ? 'Stopping…' : 'Stop'),
      t.stop_failed ? el('button', { class: 'ghost danger', type: 'button', id: 'srv-kill', onclick: confirmKill }, 'Stop now') : null),
    stopping ? el('p', { class: 'acct-busy', id: 'srv-stopping' }, el('span', { class: 'spinner', 'aria-hidden': 'true' }),
      srv.stop ? srv.stop.text : 'Asking the server to stop…') : null,
    !stopping && t.stop_text ? el('p', { class: t.stop_failed ? 'sheet-warn' : 'd-note', id: 'srv-stop-text' }, t.stop_text) : null,
    el('p', { class: 'muted small' }, 'Stop asks the server to shut down the way Ctrl+C in its window does: it saves the world first. ' +
      'Start runs enshrouded_server.exe from this folder with its window minimized. While it runs, the mods’ switches are locked.'),
    el('fieldset', { class: 'srv-close' }, el('legend', {}, 'When EMF.exe closes'),
      radio('srv-close', 'leave', !t.stop_on_close, 'Leave the server running', () => send({ cmd: 'server_on_close', stop: false })),
      radio('srv-close', 'stop', !!t.stop_on_close, 'Stop it first (it saves, then EMF closes)', () => send({ cmd: 'server_on_close', stop: true })),
      running && !p.started_here ? el('p', { class: 'muted small', id: 'srv-close-note' }, 'This run was not started by this EMF.exe, so closing EMF.exe leaves it running either way; the choice applies once you start it here.') : null));

  // ---- enshrouded_server.json ----
  const groups = c.groups || [];
  const configCard = el('div', { class: 'card account', id: 'srv-config' },
    c.found === false ? el('p', { class: 'd-note' }, 'There is no enshrouded_server.json yet: the server writes one with its defaults when it first starts.') : null,
    c.error ? el('div', { class: 'd-error', role: 'alert' }, el('span', {}, c.error)) : null,
    c.found !== false && !c.error ? el('dl', { class: 'srv-facts' },
      fact('Name', c.name || '—'),
      fact('Slots', c.slots ? String(c.slots) : '—'),
      fact('Port', c.query_port ? String(c.query_port) + (c.game_port ? ' (game port ' + c.game_port + ')' : '') : '—'),
      fact('Text chat', c.text_chat_known ? (c.text_chat ? 'on' : 'off') : '—')) : null,
    c.text_chat_known && !c.text_chat ? el('p', { class: 'sheet-warn' }, 'Text chat is off ("enableTextChat": false), so players cannot type EMF commands.') : null,
    groups.length ? el('table', { class: 'srv-groups', id: 'srv-groups' },
      el('thead', {}, el('tr', {}, el('th', {}, 'Group'), el('th', {}, 'Password'), el('th', {}, 'May'))),
      el('tbody', {}, groups.map((g) => el('tr', {},
        el('td', {}, g.name || '(no name)'),
        el('td', { class: g.password_set ? 'srv-good' : 'srv-warn' }, g.password_set ? 'set' : 'none: anyone can join with it'),
        el('td', { class: 'small' }, rights(g)))))) : null,
    c.legacy_password_set ? el('p', { class: 'd-note' }, 'An old single "password" (from before update 2) is set.') : null,
    el('div', { class: 'row' },
      c.found !== false ? el('button', { class: 'ghost small', type: 'button', onclick: () => send({ cmd: 'open_folder', path: s.game + '\\enshrouded_server.json' }) }, 'Show enshrouded_server.json') : null,
      el('span', { class: 'muted small' }, 'Read-only here, and EMF never shows a password. Change the file while the server is stopped.')));

  // ---- EMF chat commands ----
  const everyone = srv.everyone === null ? !!chat.everyone : srv.everyone;
  const gameAdmins = srv.gameAdmins === null ? !!chat.game_admins : srv.gameAdmins;
  const openAdminGroup = groups.some((g) => g.can_kick_ban && !g.password_set);  // anyone can join as the game's admin
  const refused = t.refused || [];
  const chatCard = el('div', { class: 'card account', id: 'srv-chat' },
    !s.emf_installed ? el('p', { class: 'sheet-warn' }, 'EMF is not installed in this server folder yet (below): these settings wait for it.') : null,
    el('p', {}, 'Players type EMF commands into the game’s chat (/help, /give Material_T1_Wood_Logs 20, /<mod>.<command>); only they see the replies. On a dedicated server they are always on: here you set who may.'),
    el('div', { class: 'acct-line' },
      el('button', {
        class: 'switch', type: 'button', role: 'switch', id: 'srv-everyone', 'aria-checked': String(everyone),
        'aria-label': 'Every player may use EMF commands', onclick: () => { srv.everyone = !everyone; renderServerPage(); },
      }),
      el('span', {}, 'Every player may use EMF commands'),
      everyone ? el('span', { class: 'badge warn' }, 'only on a server for friends') : null),
    el('div', { class: 'acct-line' },
      el('button', {
        class: 'switch', type: 'button', role: 'switch', id: 'srv-game-admins', 'aria-checked': String(gameAdmins),
        'aria-label': 'The game’s admins may use EMF commands', onclick: () => { srv.gameAdmins = !gameAdmins; renderServerPage(); },
      }),
      el('span', {}, 'The game’s admins may use EMF commands'),
      el('span', { class: 'muted small' }, 'players who joined with the password of a group that may kick and ban'),
      gameAdmins && openAdminGroup ? el('span', { class: 'badge warn', id: 'srv-game-admins-open' },
        'a group that may kick and ban has no password: everyone who joins could use every EMF command') : null),
    el('label', { class: 'srv-label', for: 'srv-admins' }, 'Admins: account hashes, one per line'),
    adminsBox,
    el('p', { class: 'muted small' }, 'To find your account hash, type any EMF command (/help) into the chat: EMF answers that you may not, and the server log says “chat command refused from account 0x...”. Put that value here, or click Add as admin below, then restart the server. A Steam64 id (17 digits) is not an account hash.'),
    refused.length ? el('div', { class: 'srv-refused', id: 'srv-refused' }, el('span', { class: 'acct-label' }, 'Refused lately'),
      el('p', { class: 'muted small' }, 'Add only an account you recognise: check the time and what was typed.'),
      refused.map((a) => el('div', { class: 'srv-account' }, el('code', {}, a.account),
        el('span', { class: 'muted small srv-typed' }, a.time + ' typed /', el('bdi', {}, a.command)),
        el('button', { class: 'ghost small', type: 'button', 'data-account': a.account, onclick: () => send({ cmd: 'server_admin_add', account: a.account }) }, 'Add as admin')))) : null,
    el('div', { class: 'row' },
      el('button', { class: 'primary', type: 'button', id: 'srv-chat-save', onclick: () => send({ cmd: 'server_chat_save', everyone, game_admins: gameAdmins, admins: adminsBox.value }) }, 'Save'),
      el('span', { class: 'muted small', id: 'srv-chat-note' }, srv.dirty || srv.everyone !== null || srv.gameAdmins !== null ? 'Not saved yet.'
        : 'In emf\\emf_core.ini ([chat]); the server reads it when it starts.')));

  // ---- the mod check on join ----
  const refuse = srv.refuse === null ? !!mods.refuse : srv.refuse;
  const pickRefuse = (v) => { srv.refuse = v; srv.modsDirty = true; renderServerPage(); };
  const modsCard = el('div', { class: 'card account', id: 'srv-mods' },
    el('p', {}, 'EMF compares each joining player’s mods with this server’s. By default it only warns.'),
    el('fieldset', { class: 'srv-close' }, el('legend', {}, 'When a player’s mods differ'),
      radio('srv-mods-mode', 'warn', !refuse, 'Warn players whose mods differ (default)', () => pickRefuse(false)),
      radio('srv-mods-mode', 'refuse', refuse, 'Refuse them: they are told why in the chat, then kicked after 5 seconds (admins never)', () => pickRefuse(true))),
    el('label', { class: 'srv-label', for: 'srv-mods-required' }, 'Mods every player must have, one id per line (content packs and mods marked for both sides are always checked)'),
    modsBox,
    el('label', { class: 'srv-label', for: 'srv-mods-info' }, 'Where to get them (said to refused players)'),
    modsInfoBox,
    el('div', { class: 'row' },
      el('button', { class: 'primary', type: 'button', id: 'srv-mods-save', onclick: () => send({ cmd: 'server_mods_save', refuse, required: modsBox.value, info: modsInfoBox.value }) }, 'Save'),
      el('span', { class: 'muted small', id: 'srv-mods-note' }, srv.modsDirty ? 'Not saved yet.'
        : 'In emf\\emf_core.ini ([net]); the server reads it when it starts.')));

  // ---- EMF in this server ----
  const pkg = t.package || {};
  const order = compareVersions(pkg.version, s.emf_version);
  const label = !s.emf_installed || !s.emf_version ? 'Install EMF ' + (pkg.version || '')
    : order === 0 ? 'Install EMF ' + pkg.version + ' again'
    : order > 0 ? 'Update EMF to ' + pkg.version : 'Install the older EMF ' + pkg.version;
  const pkgMods = pkg.mods || [];
  const modText = (m) => m.name + (m.on ? (m.side === 'client' ? ' (switched off on a fresh server: its mod.json says it does nothing there)' : '') : ' (off)');
  const emfCard = el('div', { class: 'card install ' + (s.emf_installed ? 'ok' : 'missing'), id: 'srv-emf' },
    el('h3', {}, s.emf_installed ? 'EMF ' + (s.emf_version || '') + ' is installed' : 'EMF is not installed here'),
    el('p', {}, pkg.ok ? 'This EMF.exe installs EMF ' + (pkg.version || '') + ' with the installer’s own rules: another mod’s dinput8.dll is renamed and started by EMF, the server’s settings stay.' : (pkg.error || '')),
    pkg.ok && !t.emf_here ? el('div', { class: 'row' },
      el('button', {
        class: 'primary', type: 'button', id: 'srv-install', disabled: running || !!t.installing,
        onclick: () => {
          showModal({ mode: 'busy', title: 'Installing EMF into the server', text: 'The installer copies EMF and records what it changed. The world is not touched.' });
          send({ cmd: 'server_install_emf' });
        },
      }, label),
      running ? el('span', { class: 'muted small' }, 'Stop the server first.') : null) : null,
    pkg.ok && pkgMods.length ? el('p', { class: 'muted small', id: 'srv-pkg-mods' }, 'It also brings these mods, switched on unless marked: ' +
      pkgMods.map(modText).join(', ') + '. Switch them in the Mods tab.') : null,
    pkg.ok && order < 0 && s.emf_installed ? el('p', { class: 'sheet-warn' }, 'This server has a newer EMF (' + s.emf_version + ') than this EMF.exe brings.') : null,
    t.emf_here ? el('p', { class: 'd-note' }, 'This EMF.exe runs from the server folder itself: use install.cmd from the EMF zip, or EMF.exe from the game’s folder.') : null,
    el('p', {}, 'Mods: the Mods tab lists this server’s mods with where each has to run; its “Install a downloaded file” installs into this server.'));

  // ---- logs ----
  const seg = (which, text) => el('button', {
    type: 'button', class: 'seg', 'aria-selected': String(srv.logWhich === which), 'data-srvlog': which,
    onclick: () => { srv.logWhich = which; renderServerPage(); },
  }, text);
  const logHead = el('div', { class: 'logs-head' },
    el('h3', { class: 'section-title' }, 'Logs'),
    el('div', { class: 'segmented', role: 'tablist', 'aria-label': 'Log file' }, seg('server', 'enshrouded_server.log'), seg('core', 'emf_core.log')),
    el('span', { class: 'muted small' }, 'follows the file'),
    el('button', { class: 'ghost small', type: 'button', id: 'srv-log-copy', onclick: () => send({ cmd: 'copy', text: srv.logs[srv.logWhich] || '' }) }, 'Copy'));

  fill(page,
    el('div', { class: 'title-row' },
      el('h2', { class: 'page-title' }, c.name || 'Dedicated server'),
      el('span', { class: 'srv-state ' + (running ? 'on' : 'off'), id: 'srv-state' }, running ? 'Running · process ' + p.pid : 'Stopped')),
    runCard,
    el('h3', { class: 'section-title' }, 'Server (enshrouded_server.json)'), configCard,
    el('h3', { class: 'section-title' }, 'EMF chat commands'), chatCard,
    el('h3', { class: 'section-title' }, 'Players’ mods'), modsCard,
    el('h3', { class: 'section-title' }, 'EMF in this server'), emfCard,
    logHead, serverLogBox);
  renderServerLog();
  if (focusId) {
    const again = document.getElementById(focusId);
    if (again && !again.disabled) again.focus();
  }
}

// "Add a server folder...": the servers Steam has, and the folder dialog.
function renderAddServer() {
  const box = $('modal');
  const sheet = $('sheet');
  const key = JSON.stringify(['add_server', srv.found]);
  if (key === modalDrawn && !box.hidden) return;
  modalDrawn = key;
  const found = srv.found || [];
  fill(sheet,
    el('div', { class: 'sheet-head' },
      el('div', { class: 'd-eyebrow' }, 'Dedicated server'),
      el('h2', { id: 'sheet-title', class: 'sheet-title' }, 'Add a server folder')),
    el('div', { class: 'sheet-body' },
      el('p', { class: 'muted' }, 'EMF manages a dedicated server like the game: its mods and their settings, who may use chat commands, starting and stopping it, and its log.'),
      found.length ? [el('h3', { class: 'sheet-h' }, 'Found through Steam'),
        el('ul', { class: 'srv-found' }, found.map((f) => el('li', {},
          el('div', { class: 'srv-found-text' }, el('strong', {}, f.name), el('span', { class: 'mono small' }, f.path)),
          f.added ? el('span', { class: 'badge ok' }, 'In the list')
            : el('button', { class: 'primary small', type: 'button', 'data-path': f.path, onclick: () => { closeModal(); send({ cmd: 'folder_add', path: f.path }); } }, 'Add'))))]
        : el('p', { class: 'd-note' }, 'Steam has no Enshrouded Dedicated Server (app 2278520) here. For a server installed with SteamCMD or copied elsewhere, choose its folder.'),
      el('p', { class: 'fineprint' }, 'A server’s folder has enshrouded_server.exe. EMF changes nothing there until you switch a mod, save a setting, install, or start the server.')),
    el('div', { class: 'sheet-foot' },
      el('button', { class: 'ghost', type: 'button', 'data-focus': 'close', onclick: closeModal }, 'Cancel'),
      el('button', { class: 'ghost', type: 'button', id: 'srv-pick', onclick: () => { closeModal(); send({ cmd: 'folder_pick_server' }); } }, 'Choose a folder…')));
  box.hidden = false;
  const first = sheet.querySelector('button.primary') || $('srv-pick');
  if (first) first.focus();
}

$('folder-switch').addEventListener('change', (e) => {
  const v = e.target.value;
  if (v === 'add') {
    send({ cmd: 'server_detect' });
    srv.switchKey = '';  // back to the folder shown
    renderServers();
    return;
  }
  if (v.startsWith('f:')) send({ cmd: 'folder_switch', path: v.slice(2) });
});

// ---- Check for updates: only when the player clicks; the host asks Nexus (docs/app.md) ----
// The host's answer names, for each Nexus mod it checked, the mod rows it belongs to ("source:id"), what EMF decided
// ("update", "maybe", "current", "unavailable", "gone", "failed") and why, and the file to take (or files to choose from).
const updates = { seq: 0, checking: false, reply: null, links: {}, linksGame: null, linking: null, linkText: '', downloadState: '', retryAt: 0, timer: 0 };
const UPDATE_WORDS = { update: 'Update available', maybe: 'EMF can’t tell', current: 'Up to date', unavailable: 'Not on Nexus now', gone: 'Gone from Nexus', failed: 'Not checked' };
const rowId = (m) => m.source + ':' + m.id;

function checkUpdates() {
  if (!nexusOn()) return;  // no Nexus request in this build
  updates.seq += 1;
  updates.checking = true;
  send({ cmd: 'updates_check', seq: updates.seq });
  renderUpdates();
}

function onUpdates(m) {
  if (m.seq !== updates.seq) return;  // an older check
  updates.checking = false;
  updates.reply = m;
  // Nexus failed: the host asks it again only after a while, and the buttons say so
  updates.retryAt = m.retry_after > 0 ? Date.now() + m.retry_after * 1000 : 0;
  renderUpdates();
  if (state) render();  // the rows' badges, keeping the keyboard where it was
  updatesDetails();
}

// What the details show of the check for a mod: when it changes, renderDetails draws them again (and a redraw skipped
// while the player typed is done at the next one).
function updatesSignature(m) {
  return [updateItemFor(m), updates.links[rowId(m)], updates.linking, isPremium(), downloading()];
}

// The details drawn again for what changed here, unless the player is typing in them (a setting, a link).
function updatesDetails() {
  if (state && state.game_found) renderDetails(false);
}

// Update with EMF follows the account and a running download.
function updatesRedraw() {
  if (updates.reply) updatesDetails();
}

function updatesOnResult(m) {
  if (m.cmd === 'updates_check') {  // refused at once (no game folder)
    updates.checking = false;
    renderUpdates();
  } else if (m.cmd === 'nexus_link' && m.ok) {
    updates.linking = null;
    updates.linkText = '';
  }
}

// Another game folder: the last check was about the other one, and its links are read again.
function updatesOnState() {
  if (!state || state.game === updates.linksGame) return;
  const changed = updates.linksGame !== null;
  updates.linksGame = state.game;
  updates.links = {};
  updates.linking = null;
  if (changed) {  // a check still running was about the other folder: its answer is dropped
    updates.seq += 1;
    updates.checking = false;
    updates.reply = null;
    renderUpdates();
  }
  send({ cmd: 'nexus_links' });
}

function onNexusLinks(m) {
  if (!state || m.game !== state.game) return;
  updates.links = m.links || {};
  updatesDetails();
}

// An install or uninstall changed a mod: what the last check said about it is out of date.
function updatesOnDone(m) {
  const r = updates.reply;
  if (!r || !m.ok || !m.key) return;
  const nexusId = /^nexus-(\d+)$/.test(m.key) ? Number(m.key.slice(6)) : 0;
  const keys = m.keys && m.keys.length ? m.keys : [m.key];  // an archive of several mods writes a record for each
  r.items = r.items.filter((it) => !keys.includes(it.install_key) && it.nexus_id !== nexusId);
  r.summary = { update: 0, maybe: 0, current: 0, unavailable: 0, gone: 0, failed: 0 };
  for (const it of r.items) r.summary[it.state] = (r.summary[it.state] || 0) + 1;
  renderUpdates();
}

function updateItemFor(m) {
  const r = updates.reply;
  if (!r || !nexusOn()) return null;
  const id = rowId(m);
  return r.items.find((it) => it.rows.includes(id)) || null;
}

function updateBadge(m) {
  const it = updateItemFor(m);
  if (!it) return null;
  if (it.state === 'update') return el('span', { class: 'badge upd', title: it.reason }, 'Update');
  if (it.state === 'maybe') return el('span', { class: 'badge quiet', title: it.reason }, 'Update?');
  if (it.state === 'unavailable') return el('span', { class: 'badge warn', title: it.reason }, 'Not on Nexus now');
  if (it.state === 'gone') return el('span', { class: 'badge bad', title: it.reason }, 'Gone from Nexus');
  return null;
}

function updatesSummary(s) {
  const parts = [];
  if (s.update) parts.push(s.update + (s.update === 1 ? ' update' : ' updates'));
  if (s.maybe) parts.push(s.maybe + ' EMF can’t tell');
  if (s.unavailable) parts.push(s.unavailable + ' not on Nexus now');
  if (s.gone) parts.push(s.gone + ' gone from Nexus');
  if (s.failed) parts.push(s.failed + ' not checked');
  if (s.current) parts.push(s.current + ' up to date');
  return parts.length ? parts.join(', ') : 'Nothing to check';
}

function updateFileText(f) {
  return [f.name || 'File ' + f.file_id, f.version && !String(f.name).includes(f.version) ? vtext(f.version) : '', dayText(f.date), sizeText(f.size)]
    .filter(Boolean).join(' · ');
}

// Premium: "Update with EMF" downloads the file and opens the plan (nothing installs before Install); when EMF can't
// tell, only a quieter "Download anyway…"; when the update would be an install of its own, the button says so. Free: the
// file's page on Nexus, whose Mod Manager Download button sends it back to EMF when EMF opens nxm:// links.
function updateFileButton(it, f, small) {
  const cls = small ? ' small' : '';
  if (isPremium()) {
    const sure = it.state === 'update';
    const text = !sure ? 'Download anyway…' : it.separate ? 'Install separately with EMF' : 'Update with EMF';
    return el('button', {
      class: (sure ? 'primary' : 'ghost') + cls, type: 'button', 'data-update': String(f.file_id), disabled: downloading(),
      title: downloading() ? 'EMF is downloading another file'
        : (sure ? '' : 'EMF can’t tell whether this is an update. ') + 'Download ' + (f.name || 'the file') + ' with EMF, then see the plan before anything is copied',
      onclick: () => send({ cmd: 'nexus_download', mod_id: it.nexus_id, file_id: f.file_id, name: it.name }),
    }, text);
  }
  return el('button', {
    class: 'ghost' + cls, type: 'button', 'data-update': String(f.file_id), title: f.page,
    onclick: () => send({ cmd: 'open_url', url: f.page }),
  }, 'Open on Nexus');
}

function updateButtons(it) {
  const files = it.nexus.files_url || it.nexus.url;
  const open = (text) => el('button', { class: 'ghost small', type: 'button', title: files, onclick: () => send({ cmd: 'open_url', url: files }) }, text);
  if (it.file) return [updateFileButton(it, it.file, true), isPremium() ? open('Open on Nexus') : null];
  return [open('Open on Nexus')];
}

function renderUpdates() {
  if (!nexusOn()) {
    $('updates-bar').hidden = true;
    return;
  }
  const btn = $('updates-check');
  const wait = Math.max(0, Math.ceil((updates.retryAt - Date.now()) / 1000));
  if (wait > 0 && !updates.timer) updates.timer = setTimeout(() => { updates.timer = 0; renderUpdates(); }, 1000);
  btn.disabled = updates.checking || wait > 0;
  btn.textContent = updates.checking ? 'Checking…' : wait > 0 ? 'Check again in ' + wait + ' s' : 'Check for updates';
  const bar = $('updates-bar');
  const r = updates.reply;
  if (!updates.checking && !r) {
    bar.hidden = true;
    return;
  }
  const kids = [];
  if (updates.checking) {
    kids.push(el('div', { class: 'upd-line' }, el('span', { class: 'spinner', 'aria-hidden': 'true' }), 'Asking Nexus Mods about your mods…'));
  } else {
    kids.push(el('div', { class: 'upd-line' }, el('strong', { id: 'updates-summary' }, updatesSummary(r.summary)),
      r.asked ? el('span', { class: 'muted small' }, r.asked + (r.asked === 1 ? ' Nexus mod, ' : ' Nexus mods, ') + r.requests + (r.requests === 1 ? ' request' : ' requests')) : null,
      el('button', { class: 'ghost small upd-close', type: 'button', title: 'Hide this', onclick: () => { updates.reply = null; renderUpdates(); if (state) render(); updatesDetails(); } }, 'Hide')));
    if (!r.ok && r.error) kids.push(el('div', { class: 'd-error', role: 'alert' }, el('span', {}, 'Could not check with Nexus: ' + r.error),
      el('button', { class: 'ghost small', type: 'button', id: 'updates-retry', disabled: wait > 0, onclick: checkUpdates }, wait > 0 ? 'Try again in ' + wait + ' s' : 'Try again')));
    if (r.note) kids.push(el('p', { class: 'muted small' }, r.note));
    if (r.emf && r.emf.newer) {
      kids.push(el('div', { class: 'upd-emf', id: 'updates-emf' }, el('strong', {}, 'EMF ' + r.emf.nexus + ' is out'), ' (you have ' + r.emf.installed + '). EMF does not update itself: install it from its package.',
        el('button', { class: 'ghost small', type: 'button', onclick: () => send({ cmd: 'open_url', url: r.emf.url }) }, 'Open EMF on Nexus')));
    }
    // installs with no row in the list (a loader's files, a mod folder removed by hand) are named here
    for (const it of r.items.filter((x) => !x.rows.length && x.state !== 'current')) {
      kids.push(el('div', { class: 'upd-other' }, el('span', {}, el('strong', {}, it.name || 'Nexus mod ' + it.nexus_id), ': ' + (UPDATE_WORDS[it.state] || it.state) + '. ' + it.reason), updateButtons(it)));
    }
  }
  fill(bar, kids);
  bar.hidden = false;
}

function linkForm(m) {
  const input = el('input', {
    type: 'text', id: 'link-input', 'data-focus': 'link-input', spellcheck: 'false', autocomplete: 'off', maxlength: '300',
    placeholder: 'https://www.nexusmods.com/enshrouded/mods/…', 'aria-label': 'The mod’s page on Nexus Mods, or its number',
  });
  input.value = updates.linkText;  // the details can be drawn again while the player types
  input.addEventListener('input', () => { updates.linkText = input.value; });
  input.addEventListener('blur', () => setTimeout(() => renderDetails(false), 0));  // a redraw skipped while typing
  const cancel = () => { updates.linking = null; updates.linkText = ''; renderDetails(true); };
  const go = () => {
    const v = input.value.trim();
    if (!v) { input.focus(); return; }
    input.blur();  // the answer draws the details again
    send({ cmd: 'nexus_link', source: m.source, id: m.id, link: v });
  };
  input.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') { e.preventDefault(); go(); } else if (e.key === 'Escape') { e.stopPropagation(); cancel(); }
  });
  return el('div', { class: 'link-form' }, input,
    el('button', { class: 'primary small', type: 'button', id: 'link-save', onclick: go }, 'Link'),
    el('button', { class: 'ghost small', type: 'button', onclick: cancel }, 'Cancel'));
}

// The details' "Updates on Nexus": what the last check said, and the hand link for a mod EMF has no Nexus id for.
function updateSection(m) {
  if (!nexusOn()) return null;  // no Check for updates, so no hand link to Nexus either (it only feeds the check)
  const it = updateItemFor(m);
  const link = updates.links[rowId(m)];
  const recordId = m.install_key ? (recordOf(m.install_key) || {}).nexus_id : '';
  const parts = [];
  if (it) {
    parts.push(el('p', { class: 'upd-state ' + it.state, id: 'update-state' }, el('strong', {}, UPDATE_WORDS[it.state] || it.state), ' ' + it.reason));
    if (it.note) parts.push(el('p', { class: 'd-note' }, it.note));
    const facts = [['Installed', [it.installed.version ? vtext(it.installed.version) : '', it.installed.file_name].filter(Boolean).join(' · ') || 'unknown']];
    if (it.nexus.version) facts.push(['On Nexus', vtext(it.nexus.version) + (it.nexus.updated ? ' · updated ' + ago(it.nexus.updated) : '')]);
    if (it.file) facts.push([it.state === 'update' ? 'File to take' : 'Nexus’s main file', updateFileText(it.file)]);
    parts.push(el('dl', { class: 'upd-facts' }, facts.map(([k, v]) => [el('dt', {}, k), el('dd', {}, v)])));
    if (it.file && it.file.changelog.length) {
      parts.push(el('details', { class: 'upd-log' }, el('summary', {}, 'Changelog'), el('ul', {}, it.file.changelog.map((l) => el('li', {}, l)))));
    }
    if (it.choices.length) {
      parts.push(el('div', { class: 'upd-choices' }, el('p', { class: 'd-note' }, 'Choose the file you use:'),
        it.choices.map((f) => el('div', { class: 'upd-choice' }, el('span', {}, updateFileText(f)), updateFileButton(it, f, true)))));
    }
    if (it.separate && (it.file || it.choices.length)) {
      parts.push(el('p', { class: 'd-note', id: 'update-separate' }, 'EMF installs it as an install of its own (' + it.installs_as + '), not into ' +
        (it.name || it.install_key) + ': ' + it.separate + '.'));
    }
    parts.push(el('div', { class: 'd-actions' }, updateButtons(it)));
  }
  if (updates.linking === rowId(m)) {
    parts.push(el('p', { class: 'd-note' }, 'Paste the mod’s page on nexusmods.com (or its number). Check for updates then asks Nexus about it.'), linkForm(m));
  } else if (link) {
    parts.push(el('p', { class: 'd-note', id: 'link-note' }, 'You linked this to Nexus mod ' + link + '. ',
      el('button', { class: 'ghost small', type: 'button', onclick: () => { updates.linking = rowId(m); updates.linkText = ''; renderDetails(true); } }, 'Change…'), ' ',
      el('button', { class: 'ghost small', type: 'button', onclick: () => send({ cmd: 'nexus_link', source: m.source, id: m.id, link: '' }) }, 'Remove link')));
  } else if (!/^\d+$/.test(m.nexus_id) && !recordId) {  // EMF knows no Nexus id for it: the player may say which mod it is
    parts.push(el('button', {
      class: 'ghost small', type: 'button', id: 'link-start', title: 'Tell EMF which Nexus mod this is, so Check for updates can ask about it',
      onclick: () => {
        updates.linking = rowId(m);
        updates.linkText = '';
        renderDetails(true);
        const i = $('link-input');
        if (i) i.focus();
      },
    }, 'Link to a Nexus mod…'));
  }
  if (!parts.length) return null;
  return el('div', { class: 'd-section updates' }, el('h3', {}, 'Updates on Nexus'), parts);
}

// ---- controls ----
function selectTab(name) {
  if (name === 'browse' && !nexusOn()) name = 'mods';
  tab = name;
  for (const o of document.querySelectorAll('.tab[data-tab]')) o.setAttribute('aria-selected', String(o.dataset.tab === name));
  if (tab === 'emf') send({ cmd: 'logs' });
  if (state) render();
  else if (tab === 'browse') renderBrowse();
}
for (const t of document.querySelectorAll('.tab[data-tab]')) t.addEventListener('click', () => selectTab(t.dataset.tab));
$('nexus-chip').addEventListener('click', showAccount);
for (const s of document.querySelectorAll('.seg[data-log]')) {
  s.addEventListener('click', () => {
    logWhich = s.dataset.log;
    for (const o of document.querySelectorAll('.seg[data-log]')) o.setAttribute('aria-selected', String(o === s));
    renderLog();
  });
}
$('logs-refresh').addEventListener('click', () => send({ cmd: 'logs' }));
$('logs-copy').addEventListener('click', () => send({ cmd: 'copy', text: logs[logWhich] || '' }));
$('warnings-copy').addEventListener('click', () => {
  if (!state) return;
  const lines = state.warnings.map((w) => w.level + ': ' + w.text);
  send({ cmd: 'copy', text: 'EMF warnings for ' + state.game + '\n' + lines.join('\n') + '\n\nStart-up report:\n' + state.report.join('\n') });
});
$('filter').addEventListener('input', (e) => {
  filterText = e.target.value;
  if (state && state.game_found) renderList();
});
$('play').addEventListener('click', () => (state && state.server ? selectTab('server') : send({ cmd: 'play' })));

// ---- the Play menu: Play, Play without EMF mods, Play without any mods (docs/app.md "Play") ----
// The two starts without mods leave the mods out for one game start: the host writes the loader's one-shot flag
// (emf\play_once.txt) and starts the game; the next start loads them again.
function playMenu(open) {
  const menu = $('play-menu');
  if (menu.hidden === !open) return;
  menu.hidden = !open;
  $('play-more').setAttribute('aria-expanded', String(open));
  if (open) menu.querySelector('[role=menuitem]').focus();
}
function playWith(mode) {
  const item = $(mode === 'no-emf' ? 'play-no-emf' : mode === 'no-mods' ? 'play-no-mods' : 'play-normal');
  if (item.getAttribute('aria-disabled') === 'true') return;  // its line under it says why
  playMenu(false);
  $('play-more').focus();
  send(mode ? { cmd: 'play', mode } : { cmd: 'play' });
}
$('play-more').addEventListener('click', (e) => { e.stopPropagation(); playMenu($('play-menu').hidden); });
$('play-normal').addEventListener('click', () => playWith(''));
$('play-no-emf').addEventListener('click', () => playWith('no-emf'));
$('play-no-mods').addEventListener('click', () => playWith('no-mods'));
document.addEventListener('click', (e) => { if (!$('play-group').contains(e.target)) playMenu(false); });
$('play-menu').addEventListener('keydown', (e) => {
  const items = [...$('play-menu').querySelectorAll('[role=menuitem]')];  // the disabled ones too: they say why
  const i = items.indexOf(document.activeElement);
  if (e.key === 'Escape') {
    e.preventDefault();
    playMenu(false);
    $('play-more').focus();
  } else if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
    e.preventDefault();
    items[(i + (e.key === 'ArrowDown' ? 1 : items.length - 1)) % items.length].focus();
  } else if (e.key === 'Home' || e.key === 'End') {
    e.preventDefault();
    items[e.key === 'Home' ? 0 : items.length - 1].focus();
  } else if (e.key === 'Tab') {
    playMenu(false);
  }
});
$('change-folder').addEventListener('click', () => send({ cmd: 'pick_folder' }));
$('nogame-pick').addEventListener('click', () => send({ cmd: 'pick_folder' }));
$('folder-path').addEventListener('click', () => { if (state && state.game) send({ cmd: 'open_folder', path: state.game }); });

for (const s of document.querySelectorAll('.seg[data-sort]')) {
  s.addEventListener('click', () => {
    if (browse.sort === s.dataset.sort) return;
    browse.sort = s.dataset.sort;
    for (const o of document.querySelectorAll('.seg[data-sort]')) o.setAttribute('aria-checked', String(o === s));
    search(0);
  });
}
$('browse-form').addEventListener('submit', (e) => {
  e.preventDefault();
  browse.text = $('browse-text').value.trim();
  search(0);
});
$('browse-install').addEventListener('click', () => pickArchive(null));
$('mods-install').addEventListener('click', () => pickArchive(null));
$('updates-check').addEventListener('click', checkUpdates);
$('modal').addEventListener('click', (e) => { if (e.target === $('modal') && modal && modal.mode !== 'busy') closeModal(); });
document.addEventListener('keydown', (e) => { if (e.key === 'Escape' && modal && modal.mode !== 'busy') closeModal(); });

for (const o of document.querySelectorAll('.tab[data-tab]')) o.setAttribute('aria-selected', String(o.dataset.tab === tab));
if (tab === 'emf') send({ cmd: 'logs' });
send({ cmd: 'state' });
send({ cmd: 'account' });

// ---- Mod profiles (docs/app.md "Profiles") ----
// The on/off state of every mod under a name: the picker above the list shows the current one, or "(changed)" when the
// switches differ from it. Save as, Switch, Rename, Delete, Export and Import go to the host (app/bridge_profiles.cpp);
// Switch is locked while the game runs, like the switches, and runs on the host's worker: until it is done the picker
// and the list's switches wait (profile_busy). This block listens to the host's messages itself.
const profiles = { pick: null, sheet: null, lastReturn: null, busy: false };

function profileList() {
  return (state && state.profiles && state.profiles.list) || [];
}

function profileLabel(p) {
  const cur = state.profiles.current === p.slug;
  if (p.error) return p.slug + '.json (not usable)';
  return p.name + (cur ? (state.profiles.changed ? ' (changed)' : ' (current)') : '');
}

// The profile the picker points at: the player's choice, else the current one, else the first.
function pickedProfile() {
  const list = profileList();
  const has = (slug) => list.some((p) => p.slug === slug);
  if (profiles.pick && has(profiles.pick)) return list.find((p) => p.slug === profiles.pick);
  if (state.profiles.current && has(state.profiles.current)) return list.find((p) => p.slug === state.profiles.current);
  return list[0] || null;
}

function renderProfiles() {
  const bar = $('profiles-bar');
  if (!bar) return;
  if (!state || !state.game_found || !state.profiles) {
    bar.hidden = true;
    return;
  }
  bar.hidden = false;
  const list = profileList();
  const p = pickedProfile();
  const running = !!state.game_running;
  const busy = profiles.busy;
  const usable = !!(p && !p.error);
  const select = el('select', {
    id: 'profile-select', 'aria-label': 'Profile', disabled: !list.length,
    title: 'Profiles: the on/off state of every mod under a name',
    onchange: (e) => { profiles.pick = e.target.value; renderProfiles(); },
  }, list.length ? list.map((x) => el('option', { value: x.slug, selected: p && x.slug === p.slug }, profileLabel(x)))
    : el('option', { value: '' }, 'No profiles yet'));
  const isCurrent = usable && state.profiles.current === p.slug;
  const sw = el('button', {
    class: 'primary small', type: 'button', id: 'profile-switch', disabled: !usable || running || busy,
    title: busy ? 'Switching…' : running ? 'Close the game first to switch mods'
      : !usable ? (p ? p.error : 'Save a profile first')
      : isCurrent && !state.profiles.changed ? 'The mods are as this profile has them' : 'Switch every mod to this profile (takes effect at the next game start)',
    onclick: () => {
      if (!usable) return;
      send({ cmd: 'profile_switch', slug: p.slug });
    },
  }, busy ? 'Switching…' : 'Switch');
  const small = (id, text, title, onclick, off) => el('button', { class: 'ghost small', type: 'button', id, title, disabled: !!off || busy, onclick }, text);
  const status = busy ? 'Switching the mods to the profile…' : !state.profiles.current ? 'No profile chosen yet'
    : state.profiles.changed ? 'Switches changed since ' + state.profiles.current_name : 'Mods as ' + state.profiles.current_name + ' has them';
  fill(bar,
    el('span', { class: 'profiles-label' }, 'Profile'),
    select, sw,
    small('profile-save', 'Save as…', 'Save the on/off state of every mod as a profile', () => showProfileSheet({ mode: 'save' })),
    small('profile-rename', 'Rename…', 'Give this profile another name', () => showProfileSheet({ mode: 'rename', slug: p.slug, name: p.name }), !usable),
    small('profile-delete', 'Delete…', 'Delete this profile (never a mod)', () => showProfileSheet({ mode: 'delete', slug: p.slug, name: p.error ? p.slug + '.json' : p.name }), !p),
    small('profile-export', 'Export…', 'Save this profile as a file to share your modlist', () => send({ cmd: 'profile_export', slug: p.slug }), !usable),
    small('profile-import', 'Import…', 'Add a profile file someone shared', () => send({ cmd: 'profile_import' })),
    el('span', { class: 'profiles-status' + (state.profiles.changed ? ' changed' : ''), id: 'profile-status' }, status));
}

function showProfileSheet(s) {
  if (!profiles.sheet) profiles.lastReturn = document.activeElement;
  profiles.sheet = s;
  renderProfileSheet();
}

function closeProfileSheet() {
  if (profiles.sheet && profiles.sheet.mode === 'import') send({ cmd: 'profile_import_cancel' });
  profiles.sheet = null;
  $('profile-modal').hidden = true;
  const back = profiles.lastReturn;
  if (back && back.focus && document.contains(back)) back.focus();
}

function itemLine(i, withState) {
  const bits = [i.name || i.id];
  if (withState) bits.push(i.on ? 'on' : 'off');
  const kind = { emf: 'EMF mod', eml: 'EML mod', chain: 'DLL mod', other: 'other loader' }[i.source] || i.source;
  let text = bits.join(': ') + ' (' + kind + (i.nexus_id ? ', Nexus ' + i.nexus_id : '') + ')';
  if (i.why) text += ' — ' + i.why;
  return el('li', {}, text);
}

function sheetList(title, items, withState, cls) {
  if (!items || !items.length) return null;
  return [el('h3', { class: 'sheet-h' + (cls ? ' ' + cls : '') }, title + ' (' + items.length + ')'),
    el('ul', { class: 'part-lines profile-items' }, items.map((i) => itemLine(i, withState)))];
}

function renderProfileSheet() {
  const box = $('profile-modal');
  const sheet = $('profile-sheet');
  const s = profiles.sheet;
  if (!s) {
    box.hidden = true;
    return;
  }
  const close = (text) => el('button', { class: 'ghost', type: 'button', 'data-focus': 'close', onclick: closeProfileSheet }, text);
  const head = (eyebrow, title, cls) => el('div', { class: 'sheet-head' },
    eyebrow ? el('div', { class: 'd-eyebrow' }, eyebrow) : null,
    el('h2', { id: 'profile-sheet-title', class: 'sheet-title' + (cls ? ' ' + cls : '') }, title));
  let focus = null;
  if (s.mode === 'save' || s.mode === 'rename') {
    const name = el('input', {
      type: 'text', id: 'profile-name', class: 'profile-name', maxlength: '40', spellcheck: 'false', autocomplete: 'off',
      value: s.name || '', placeholder: 'Vanilla+, Building, Testing…', 'aria-label': 'Profile name',
    });
    const withSettings = el('input', { type: 'checkbox', id: 'profile-settings', checked: !!s.settings });
    const go = () => {
      const v = name.value.trim();
      if (!v) { name.focus(); return; }
      if (s.mode === 'save') send({ cmd: 'profile_save', name: v, settings: withSettings.checked });
      else send({ cmd: 'profile_rename', slug: s.slug, name: v });
      profiles.sheet = Object.assign({}, s, { name: v, settings: withSettings.checked, waiting: true });
    };
    name.addEventListener('keydown', (e) => { if (e.key === 'Enter') { e.preventDefault(); go(); } });
    const n = state.mods.filter((m) => !m.is_loader).length;
    fill(sheet,
      head(s.mode === 'save' ? 'Save as a profile' : 'Rename', s.mode === 'save' ? 'Save the switches as a profile' : 'Rename ' + s.name),
      el('div', { class: 'sheet-body' },
        s.mode === 'save' ? el('p', { class: 'muted' }, 'Saves the on/off state of every mod here (' + n + (n === 1 ? ' mod' : ' mods') +
          ') under a name. Switching to it later sets each mod back, at the next game start.') : null,
        el('label', { class: 'profile-field' }, el('span', {}, 'Name'), name),
        el('p', { class: 'fineprint' }, 'Up to 40 characters, none of \\ / : * ? " < > |'),
        s.mode === 'save' ? el('label', { class: 'profile-check' }, withSettings,
          el('span', {}, 'Include settings: each EMF mod’s settings are saved too, and set back when you switch to it')) : null),
      el('div', { class: 'sheet-foot' }, close('Cancel'),
        el('button', { class: 'primary', type: 'button', id: 'profile-sheet-go', onclick: go }, s.mode === 'save' ? 'Save' : 'Rename')));
    focus = name;
  } else if (s.mode === 'replace') {
    const go = el('button', {
      class: 'primary danger', type: 'button', id: 'profile-sheet-go',
      onclick: () => {
        send({ cmd: 'profile_save', name: s.name, settings: s.settings, replace: true });
        profiles.sheet = Object.assign({}, s, { waiting: true });
      },
    }, 'Replace');
    fill(sheet, head('Save as a profile', 'Replace ' + s.existing + '?'),
      el('div', { class: 'sheet-body' },
        el('p', {}, 'A profile named ' + s.existing + ' is there already. Replace it with the switches as they are now' +
          (s.settings ? ', with the settings' : '') + '?')),
      el('div', { class: 'sheet-foot' }, close('Cancel'), go));
    focus = go;
  } else if (s.mode === 'delete') {
    const go = el('button', {
      class: 'primary danger', type: 'button', id: 'profile-sheet-go',
      onclick: () => {
        send({ cmd: 'profile_delete', slug: s.slug });
        profiles.sheet = Object.assign({}, s, { waiting: true });
      },
    }, 'Delete');
    fill(sheet, head('Delete', 'Delete the profile ' + s.name + '?'),
      el('div', { class: 'sheet-body' }, el('p', {}, 'Only the profile goes. No mod is switched, removed or changed.')),
      el('div', { class: 'sheet-foot' }, close('Cancel'), go));
    focus = go;
  } else if (s.mode === 'report') {
    const r = s.report;
    const settingsLine = r.settings_set || r.settings_unchanged || r.settings_failed.length || r.settings_skipped.length
      ? el('p', { class: 'muted' }, r.settings_set + (r.settings_set === 1 ? ' setting set, ' : ' settings set, ') + r.settings_unchanged + ' already so.') : null;
    const on = r.switched.filter((i) => i.on), off = r.switched.filter((i) => !i.on);
    fill(sheet, head('Switched profile', r.profile, r.ok ? 'good' : 'bad'),
      el('div', { class: 'sheet-body' },
        el('p', { class: 'muted', id: 'profile-report-summary' }, r.switched.length + (r.switched.length === 1 ? ' mod switched, ' : ' mods switched, ') +
          r.unchanged + ' already so. Everything takes effect at the next game start.'),
        sheetList('Could not switch (the others were switched)', r.failed, true, 'bad'),
        sheetList('Switched on', on, false), sheetList('Switched off', off, false),
        sheetList('Not in this folder', r.missing, true),
        sheetList('Read-only here, left as they are', r.read_only, true),
        sheetList('Recorded read-only (their own loader switched them where the profile was saved): not switched', r.recorded_read_only, true),
        sheetList('Not in this profile, left as they are', r.not_in_profile, true),
        settingsLine,
        sheetList('Settings that could not be set', r.settings_failed, false, 'bad'),
        sheetList('Settings skipped', r.settings_skipped, false)),
      el('div', { class: 'sheet-foot' }, close('OK')));
  } else if (s.mode === 'import') {
    const m = s.msg;
    if (!m.ok) {
      fill(sheet, head('Import a profile', 'Not imported', 'bad'),
        el('div', { class: 'sheet-body' }, el('div', { class: 'd-error', role: 'alert' }, el('span', {}, m.error)),
          el('p', { class: 'mono profile-file' }, m.file)),
        el('div', { class: 'sheet-foot' }, close('OK')));
    } else {
      const name = el('input', {
        type: 'text', id: 'profile-name', class: 'profile-name', maxlength: '40', spellcheck: 'false', autocomplete: 'off',
        value: s.name !== undefined ? s.name : m.name, 'aria-label': 'Profile name',
      });
      const go = () => {
        const v = name.value.trim();
        if (!v) { name.focus(); return; }
        send({ cmd: 'profile_import_save', name: v, replace: m.exists && v === m.name });
        profiles.sheet = Object.assign({}, s, { name: v, waiting: true });
      };
      name.addEventListener('keydown', (e) => { if (e.key === 'Enter') { e.preventDefault(); go(); } });
      const facts = [m.mods + (m.mods === 1 ? ' mod' : ' mods'), m.with_settings ? 'with settings' : '',
        m.created ? 'saved ' + m.created : '', m.emf_version ? 'EMF ' + m.emf_version : ''].filter(Boolean).join(' · ');
      // what Switch would do here, before anything is saved or switched
      const flips = m.would_switch || [], sets = m.would_set || [];
      const onNames = flips.filter((i) => i.on).map((i) => i.name || i.id), offNames = flips.filter((i) => !i.on).map((i) => i.name || i.id);
      const preview = [
        el('h3', { class: 'sheet-h' }, 'Switching to it here would'),
        el('ul', { class: 'part-lines', id: 'profile-import-preview' },
          onNames.length ? el('li', {}, 'switch on: ' + onNames.join(', ')) : null,
          offNames.length ? el('li', {}, 'switch off: ' + offNames.join(', ')) : null,
          sets.length ? el('li', {}, 'set ' + sets.length + (sets.length === 1 ? ' setting: ' : ' settings: ') +
            sets.map((x) => x.id + ' = ' + x.value).join(', ')) : null,
          !onNames.length && !offNames.length && !sets.length ? el('li', {}, 'change nothing: the mods here are as it has them') : null),
        sheetList('Could not be switched here', m.would_not, true),
        sheetList('Recorded read-only: never switched', m.recorded_read_only, true)];
      fill(sheet, head('Import a profile', m.name),
        el('div', { class: 'sheet-body' },
          el('p', { class: 'muted' }, facts),
          el('p', { class: 'mono profile-file' }, m.file),
          preview,
          m.missing.length
            ? sheetList('Missing in this folder', m.missing, true)
            : el('p', { class: 'muted', id: 'profile-import-complete' }, 'Every mod it lists is in this folder.'),
          m.missing.length ? el('p', { class: 'fineprint' }, 'Install the missing mods first (their Nexus ids are shown where the profile knows them). Switching to the profile without them sets the others and reports the missing ones.') : null,
          el('label', { class: 'profile-field' }, el('span', {}, 'Save as'), name),
          m.exists ? el('div', { class: 'sheet-warn', role: 'status' }, 'A profile named ' + m.existing_name + ' is there already: importing under this name replaces it. Change the name to keep both.') : null,
          el('p', { class: 'fineprint' }, 'Importing adds the profile to your list. Nothing is switched until you switch to it.')),
        el('div', { class: 'sheet-foot' }, close('Cancel'),
          el('button', { class: 'primary', type: 'button', id: 'profile-sheet-go', onclick: go }, m.exists ? 'Import and replace' : 'Import')));
      focus = name;
    }
  }
  box.hidden = false;
  (focus || sheet.querySelector('[data-focus="close"]') || sheet).focus();
}

function profilesOnMessage(m) {
  if (!m || typeof m !== 'object') return;
  if (m.type === 'state') {
    renderProfiles();
  } else if (m.type === 'profile_exists') {
    showProfileSheet({ mode: 'replace', name: m.name, existing: m.existing_name, settings: !!m.settings });
  } else if (m.type === 'profile_report') {
    // a clean switch is said in a toast (the result); a report with something to read opens
    const r = m;
    const worth = r.failed.length || r.missing.length || r.read_only.length || (r.recorded_read_only || []).length ||
      r.not_in_profile.length || r.settings_failed.length || r.settings_skipped.length;
    if (worth) showProfileSheet({ mode: 'report', report: r });
  } else if (m.type === 'profile_import') {
    showProfileSheet({ mode: 'import', msg: m });
  } else if (m.type === 'profile_busy') {
    profiles.busy = !!m.busy;
    pending = profiles.busy;  // the list's switches wait for the profile too
    if (state) render();
    renderProfiles();
  } else if (m.type === 'result' && /^profile_/.test(m.cmd)) {
    const s = profiles.sheet;
    if (m.ok && s && s.waiting && s.mode !== 'report') {
      if (m.cmd === 'profile_save' || m.cmd === 'profile_rename' || m.cmd === 'profile_import_save') profiles.pick = null;
      profiles.sheet = null;  // done: the toast says so
      closeProfileSheet();
    } else if (s && s.waiting) {
      profiles.sheet = Object.assign({}, s, { waiting: false });  // refused: the sheet stays, the toast says why
    }
    renderProfiles();
  }
}

if (host) host.addEventListener('message', (e) => profilesOnMessage(e.data));
$('profile-modal').addEventListener('click', (e) => { if (e.target === $('profile-modal')) closeProfileSheet(); });
document.addEventListener('keydown', (e) => { if (e.key === 'Escape' && profiles.sheet) closeProfileSheet(); });
