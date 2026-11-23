// EMF.exe's Saves tab (docs/app.md "Saves"): the save backups the host keeps in %LOCALAPPDATA%\EMF\save-backups
// (app/bridge_saves.cpp). Loaded after app.js and uses its helpers (el, fill, $, send, toast, state, tab). Every text
// from the host (labels, character and world names from the game) goes in as text, never as HTML. It listens to the
// host's messages itself and has a dialog of its own (#saves-modal), so it stays apart from app.js.
'use strict';

const saves = {
  data: null,         // the host's last "saves" message
  sheet: null,        // {mode: 'restore' | 'delete' | 'busy' | 'done', ...}
  lastReturn: null,   // where the keyboard goes back to when the dialog closes
  drawn: '',          // what the list was last drawn from
  asked: false,       // a list was asked for since the tab opened
};
const SAVE_KIND = { starter: 'Starter', manual: 'Manual', auto: 'Automatic', 'before-restore': 'Before restore' };
// The label field is made once and kept, so drawing the tab again never loses what the player is typing.
const savesLabel = el('input', {
  id: 'saves-label', type: 'text', maxlength: '80', autocomplete: 'off', spellcheck: 'false',
  placeholder: 'Label (optional), e.g. before the boss', 'aria-label': 'A label for the new backup',
});
savesLabel.addEventListener('keydown', (e) => { if (e.key === 'Enter') { e.preventDefault(); savesBackupNow(); } });

function savesAsk() {
  saves.asked = true;
  send({ cmd: 'saves_list' });
}

function savesWhen(unix) {
  if (!unix) return '';
  return new Date(unix * 1000).toLocaleString(undefined, { year: 'numeric', month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' });
}

function savesBusy() {
  return (state && state.saves_busy) || (saves.data && saves.data.busy) || '';
}

function savesBackupNow() {
  if (savesBusy() || (saves.data && saves.data.working)) return;
  send({ cmd: 'saves_backup', label: savesLabel.value });
  saves.data = Object.assign({}, saves.data, { working: true });
  renderSaves(true);
}

function savesCount(n, one, many) {
  return n + ' ' + (n === 1 ? one : many);
}

function savesRow(b) {
  if (b.damaged) {
    return el('div', { class: 'save-row damaged', 'data-id': b.id },
      el('div', { class: 'save-main' },
        el('div', { class: 'save-title' }, el('span', { class: 'badge bad' }, 'Damaged'), el('span', { class: 'mono save-id' }, b.id)),
        el('div', { class: 'save-sub' }, 'EMF cannot read this backup: ' + (b.error || 'backup.json is missing.'))),
      el('div', { class: 'save-actions' },
        el('button', { class: 'ghost small', type: 'button', onclick: () => send({ cmd: 'saves_open', id: b.id }) }, 'Show'),
        el('button', { class: 'ghost small danger save-delete', type: 'button', onclick: () => savesShowSheet({ mode: 'delete', backup: b }) }, 'Delete…')));
  }
  const meta = [b.size_text, savesCount(b.files.length, 'file', 'files'), b.made_by ? 'made by ' + b.made_by : ''].filter(Boolean).join(' · ');
  return el('div', { class: 'save-row', 'data-id': b.id },
    el('div', { class: 'save-main' },
      el('div', { class: 'save-title' },
        el('span', { class: 'save-time' }, savesWhen(b.time) || b.time_local),
        el('span', { class: 'badge save-kind kind-' + b.kind }, SAVE_KIND[b.kind] || b.kind),
        b.label ? el('span', { class: 'save-label' }, b.label) : null),
      el('div', { class: 'save-sub' }, b.summary || 'Settings files only'),
      el('div', { class: 'save-meta' }, meta),
      b.problems && b.problems.length
        ? el('div', { class: 'save-problem', role: 'note' }, 'Incomplete. Not copied: ' + b.problems.join('; ')) : null),
    el('div', { class: 'save-actions' },
      el('button', { class: 'ghost small save-restore', type: 'button', title: 'Put every file of this backup back',
        onclick: () => savesShowSheet({ mode: 'restore', backup: b, all: true, chosen: [] }) }, 'Restore all…'),
      el('button', { class: 'ghost small save-pick-files', type: 'button', title: 'Choose the files to put back: one character or one world, say',
        onclick: () => savesShowSheet({ mode: 'restore', backup: b, all: false, chosen: [] }) }, 'Pick files…'),
      el('button', { class: 'ghost small danger save-delete', type: 'button', onclick: () => savesShowSheet({ mode: 'delete', backup: b }) }, 'Delete…'),
      el('button', { class: 'ghost small', type: 'button', title: 'Show this backup in Explorer', onclick: () => send({ cmd: 'saves_open', id: b.id }) }, 'Show')));
}

function renderSaves(force) {
  const page = $('saves-page');
  if (!page || tab !== 'saves') return;
  if (!saves.asked) savesAsk();
  const d = saves.data;
  const busy = savesBusy();
  const key = JSON.stringify([d, busy]);
  if (!force && key === saves.drawn) return;
  saves.drawn = key;
  const focused = document.activeElement === savesLabel;
  if (!d) {
    fill(page, el('h2', { class: 'page-title' }, 'Saves'), el('p', { class: 'muted' }, 'Loading…'));
    return;
  }
  const working = !!d.working;
  const a = d.auto || {};
  const autoLine = a.on === false
    ? 'Automatic backups are off.'
    : 'Automatic backups: when the game starts with EMF, at most once every ' + (a.min_minutes || 60) + ' minutes and only when a save changed; the newest ' + (a.keep || 10) + ' are kept.';
  const toggle = a.available ? el('label', { class: 'profile-check saves-auto' },
    el('input', { type: 'checkbox', id: 'saves-auto-on', checked: a.on !== false, onchange: (e) => send({ cmd: 'saves_auto', on: e.target.checked }) }),
    el('span', {}, 'Back up the saves when the game starts')) : null;
  fill(page,
    el('div', { class: 'title-row' },
      el('h2', { class: 'page-title' }, 'Saves'),
      el('button', { class: 'ghost small', id: 'saves-open', type: 'button', title: d.store, onclick: () => send({ cmd: 'saves_open' }) }, 'Open folder')),
    el('p', { class: 'muted' }, 'EMF keeps copies of your Enshrouded saves on this PC: characters and worlds, Steam Cloud and Local, with the game’s settings files. Restoring a backup never removes it.'),
    el('p', { class: 'saves-hint', id: 'saves-intro' }, 'To bring back one character or one world only (one that got damaged, say), click Pick files… on a backup and tick just that file. Your other saves stay as they are.'),
    !d.available ? el('div', { class: 'd-error', role: 'alert' }, el('span', {}, 'EMF keeps no save backups on this PC: Windows does not say where %LOCALAPPDATA% is.')) : null,
    el('div', { class: 'card saves-now' },
      el('div', { class: 'saves-now-row' }, savesLabel,
        el('button', { class: 'primary', id: 'saves-backup', type: 'button', disabled: !!busy || working || !d.available, onclick: savesBackupNow },
          working ? 'Working…' : 'Back up now')),
      busy ? el('p', { class: 'sheet-warn', id: 'saves-busy', role: 'status' }, busy) : null,
      el('p', { class: 'muted small saves-now-note' }, d.now_files
        ? 'Now on this PC: ' + savesCount(d.now_files, 'save file', 'save files') + ', ' + d.now_text + '.'
        : 'EMF finds no Enshrouded saves on this PC yet.')),
    el('p', { class: 'saves-policy', id: 'saves-policy' }, autoLine + ' Starter, manual and before-restore backups are kept until you delete them.'),
    toggle,
    el('h3', { class: 'section-title' }, 'Backups'),
    el('p', { class: 'muted small', id: 'saves-total' }, d.count
      ? savesCount(d.count, 'backup', 'backups') + ', ' + d.total_text + ' in all, in ' + d.store
      : 'No backups yet.'),
    el('div', { class: 'save-list', id: 'save-list' }, (d.list || []).map(savesRow)));
  if (focused) savesLabel.focus();
}

// ---- the dialog ----
function savesShowSheet(s) {
  if (!saves.sheet) saves.lastReturn = document.activeElement;
  saves.sheet = s;
  renderSavesSheet();
}

function savesCloseSheet() {
  saves.sheet = null;
  $('saves-modal').hidden = true;
  const back = saves.lastReturn;
  if (back && back.focus && document.contains(back)) back.focus();
}

function savesFileLine(f, s) {
  const id = 'save-file-' + f.path.replace(/[^A-Za-z0-9]/g, '-');
  const box = el('input', {
    type: 'checkbox', id, 'data-path': f.path, checked: s.chosen.includes(f.path),
    onchange: (e) => {
      const chosen = s.chosen.filter((p) => p !== f.path);
      if (e.target.checked) chosen.push(f.path);
      saves.sheet = Object.assign({}, s, { chosen });
      renderSavesSheet();
    },
  });
  const what = savesWhat(f);
  return el('label', { class: 'save-file', for: id }, box,
    el('span', { class: 'save-file-what' }, what),
    el('span', { class: 'save-file-meta' }, [f.modified ? 'saved ' + savesWhen(f.modified) : '', savesPlayed(f.play_seconds),
      savesSize(f.size)].filter(Boolean).join(' · ')));
}

// What a file is, as the player knows it: "Character: Ember (level 8) — character3.ksd", "World: Embervale — world1.ksd",
// "Character slot 2 — character1.ksd" while the name is unknown; other files by their name.
function savesWhat(f) {
  let what = '';
  if (f.type === 'character') what = /^character slot /.test(f.label) ? 'C' + f.label.slice(1) : 'Character: ' + f.label;
  else if (f.type === 'world') what = /^world slot /.test(f.label) ? 'W' + f.label.slice(1) : 'World: ' + f.label.replace(/^world /, '');
  return what ? what + ' — ' + f.name : f.name;
}

// "12 h played", "40 min played": a world's play time as the game's menu had it ('' when unknown)
function savesPlayed(seconds) {
  if (!seconds) return '';
  return seconds >= 3600 ? Math.round(seconds / 360) / 10 + ' h played' : Math.max(1, Math.round(seconds / 60)) + ' min played';
}

function savesSize(bytes) {
  if (bytes < 1024 * 1024) return (bytes / 1024 < 10 ? (Math.round(bytes / 102.4) / 10) : Math.round(bytes / 1024)) + ' KB';
  return (Math.round(bytes / 104857.6) / 10) + ' MB';
}

function savesGroups(files) {
  const groups = [];
  for (const f of files) {
    const name = f.storage === 'steam' ? 'Steam Cloud (Steam user ' + f.steam_id + ')' : 'Local';
    let g = groups.find((x) => x.name === name);
    if (!g) groups.push(g = { name, files: [] });
    g.files.push(f);
  }
  return groups;
}

const STEAM_WARNING = 'These are Steam Cloud saves. Steam keeps a copy of them online. EMF gives the restored files today’s ' +
  'time, so at the next game start Steam should upload them as the newest. If Steam instead says the files on this PC and ' +
  'in the cloud are in conflict, choose the files on this PC (Local); choosing the cloud copy brings back what you wanted to ' +
  'replace. (This has not been tried against Steam itself.)';

function renderSavesSheet() {
  const box = $('saves-modal');
  const sheet = $('saves-sheet');
  const s = saves.sheet;
  if (!s) {
    box.hidden = true;
    return;
  }
  const busy = savesBusy();
  const head = (eyebrow, title, cls) => el('div', { class: 'sheet-head' },
    eyebrow ? el('div', { class: 'd-eyebrow' }, eyebrow) : null,
    el('h2', { id: 'saves-sheet-title', class: 'sheet-title' + (cls ? ' ' + cls : '') }, title));
  const cancel = (text) => el('button', { class: 'ghost', type: 'button', id: 'saves-sheet-cancel', 'data-focus': 'close', onclick: savesCloseSheet }, text);
  let focus = null;
  if (s.mode === 'restore') {
    const b = s.backup;
    const files = b.files || [];
    const chosen = s.all ? files.map((f) => f.path) : s.chosen;
    const steam = files.some((f) => f.storage === 'steam' && chosen.includes(f.path));
    const pick = (all) => () => { saves.sheet = Object.assign({}, s, { all }); renderSavesSheet(); };
    const go = el('button', {
      class: 'primary', type: 'button', id: 'saves-sheet-go', disabled: !!busy || !chosen.length,
      onclick: () => {
        send({ cmd: 'saves_restore', id: b.id, paths: s.all ? [] : chosen });
        saves.sheet = { mode: 'busy', title: 'Restoring…', text: 'EMF first backs up the files it replaces, then copies the backup’s files back and checks them.' };
        renderSavesSheet();
      },
    }, !chosen.length ? 'Restore' : chosen.length === files.length ? 'Restore all' : 'Restore ' + savesCount(chosen.length, 'file', 'files'));
    fill(sheet,
      head('Restore', 'Restore the backup from ' + (savesWhen(b.time) || b.time_local) + (b.label ? ' (' + b.label + ')' : '')),
      el('div', { class: 'sheet-body' },
        busy ? el('div', { class: 'sheet-warn', role: 'status', id: 'saves-restore-busy' }, busy) : null,
        el('div', { class: 'save-pick', role: 'radiogroup', 'aria-label': 'What to restore' },
          el('label', { class: 'profile-check' }, el('input', { type: 'radio', name: 'save-pick', id: 'saves-pick-all', checked: !!s.all, onchange: pick(true) }),
            el('span', {}, 'The whole backup (' + savesCount(files.length, 'file', 'files') + ')')),
          el('label', { class: 'profile-check' }, el('input', { type: 'radio', name: 'save-pick', id: 'saves-pick-some', checked: !s.all, onchange: pick(false) }),
            el('span', {}, 'Only the files I choose: one character or one world, say'))),
        s.all ? null : el('p', { class: 'muted small', id: 'saves-pick-hint' }, 'Tick what you want back. Files you leave unticked stay as they are now.'),
        s.all ? el('p', { class: 'muted small' }, b.summary || '') : savesGroups(files).map((g) => [
          el('h3', { class: 'sheet-h' }, g.name),
          el('div', { class: 'save-files' }, g.files.map((f) => savesFileLine(f, s)))]),
        steam ? el('div', { class: 'sheet-warn save-steam', role: 'note', id: 'saves-steam-warning' }, STEAM_WARNING) : null,
        el('ul', { class: 'part-lines' },
          el('li', {}, 'First EMF backs up the files it replaces (a “Before restore” backup), so you can go back.'),
          el('li', {}, 'This backup stays in the list.'),
          el('li', {}, 'Only works while the game is closed.'))),
      el('div', { class: 'sheet-foot' }, cancel('Cancel'), go));
  } else if (s.mode === 'delete') {
    const b = s.backup;
    const go = el('button', {
      class: 'primary danger', type: 'button', id: 'saves-sheet-go',
      onclick: () => { send({ cmd: 'saves_delete', id: b.id, starter: b.kind === 'starter' }); savesCloseSheet(); },
    }, 'Delete');
    const when = b.damaged ? b.id : (savesWhen(b.time) || b.time_local);
    fill(sheet,
      head('Delete', 'Delete the backup from ' + when + '?'),
      el('div', { class: 'sheet-body' },
        b.label ? el('p', { id: 'saves-delete-label' }, 'Label: ', el('strong', {}, b.label)) : null,
        b.kind ? el('p', {}, 'Kind: ' + (SAVE_KIND[b.kind] || b.kind) + (b.size_text ? ', ' + b.size_text : '') + '.') : null,
        b.kind === 'starter' ? el('div', { class: 'sheet-warn', role: 'note', id: 'saves-delete-starter' }, 'This is your backup from before EMF was installed.') : null,
        el('p', { class: 'muted' }, 'The backup’s copies are deleted from this PC. Your saves are not touched.')),
      el('div', { class: 'sheet-foot' }, cancel('Cancel'), go));
  } else if (s.mode === 'busy') {
    fill(sheet, el('div', { class: 'sheet-busy' }, el('span', { class: 'spinner big', 'aria-hidden': 'true' }),
      el('h2', { id: 'saves-sheet-title', class: 'sheet-title' }, s.title), el('p', { class: 'muted' }, s.text)));
  } else if (s.mode === 'done') {
    const m = s.msg;
    fill(sheet,
      head('', m.ok ? 'Restored' : 'Not restored', m.ok ? 'good' : 'bad'),
      el('div', { class: 'sheet-body' },
        m.error ? el('div', { class: 'd-error', role: 'alert', id: 'saves-restore-error' }, el('span', {}, m.error)) : null,
        m.restored && m.restored.length ? el('ul', { class: 'part-lines done', id: 'saves-restored' }, m.restored.map((x) => el('li', {}, x))) : null,
        m.before_id ? el('p', { class: 'muted small' }, 'The files as they were before are in the backup marked “Before restore”.') : null,
        m.ok && m.steam ? el('div', { class: 'sheet-warn', role: 'note' }, STEAM_WARNING) : null),
      el('div', { class: 'sheet-foot' }, cancel('OK')));
  }
  box.hidden = false;
  (focus || sheet.querySelector('[data-focus="close"]') || sheet).focus();
}

function savesOnMessage(m) {
  if (!m || typeof m !== 'object') return;
  if (m.type === 'saves') {
    saves.data = m;
    renderSaves(true);
    if (saves.sheet && saves.sheet.mode === 'restore') renderSavesSheet();  // the game started or stopped meanwhile
  } else if (m.type === 'saves_restored') {
    saves.sheet = { mode: 'done', msg: m };
    if (!saves.lastReturn) saves.lastReturn = document.activeElement;
    renderSavesSheet();
  } else if (m.type === 'saves_note') {
    toast(m.text, !m.ok);
  } else if (m.type === 'result' && m.cmd === 'saves_backup' && m.ok) {
    savesLabel.value = '';
  } else if (m.type === 'state' && saves.sheet && saves.sheet.mode === 'restore') {
    renderSavesSheet();  // saves_busy may have changed
  }
}

if (host) host.addEventListener('message', (e) => savesOnMessage(e.data));
for (const t of document.querySelectorAll('.tab[data-tab="saves"]')) t.addEventListener('click', savesAsk);
$('saves-modal').addEventListener('click', (e) => { if (e.target === $('saves-modal') && saves.sheet && saves.sheet.mode !== 'busy') savesCloseSheet(); });
document.addEventListener('keydown', (e) => { if (e.key === 'Escape' && saves.sheet && saves.sheet.mode !== 'busy') savesCloseSheet(); });
if (tab === 'saves') savesAsk();
