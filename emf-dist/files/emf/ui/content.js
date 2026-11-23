// EMF.exe's card "EML content" on the EMF tab (docs/engine_parts/content_loader.md "What the player sees"): who applies
// the EML mods' content at the next start and why, the mods EMF builds and the ones it leaves out, the last build, the
// copy's disk use, and the few safe actions (app/bridge_content.cpp). Loaded after app.js and uses its helpers (el,
// fill, $, send, toast, state, tab). Every text from the host (mod names, the state's message and errors) goes in as
// text, never as HTML. It listens to the host's messages itself.
'use strict';

const content = {
  data: null,      // the host's last "content" message
  asked: false,    // a panel was asked for since the tab opened
  drawn: '',       // what the card was last drawn from
  running: false,  // the game ran at the last state: when it stops, the panel is asked for again (a build may have run)
  game: null,      // the folder the card is about: another one shown (the folder switch) starts the card afresh
};
const CONTENT_BADGE = {
  ready: ['ok', 'Ready'], builds_next: ['warn', 'Builds next'], failed: ['bad', 'Failed'], off: ['quiet', 'Off'],
  other_tool: ['eml', 'Other tool'], not_installed: ['quiet', 'Not installed'],
};
const CONTENT_MODES = [
  ['auto', 'Automatic', 'EMF builds it when EML and ShroudForge are not there (the default).'],
  ['on', 'On', 'The same, and the game’s console says why when EMF does not build it.'],
  ['off', 'Off', 'EMF never builds EML content.'],
];

// One folder however its path ends or is cased (the host's spelling and the scan's may differ).
function contentSameFolder(a, b) {
  const norm = (x) => String(x || '').replace(/[\\/]+$/, '').toLowerCase();
  return norm(a) === norm(b);
}

function contentAsk() {
  content.asked = true;
  send({ cmd: 'content' });
}

function contentRunning() {
  return state && state.game_running ? (state.running_reason || 'The game is running.') : '';
}

// "8.5 s", "28 s": as the loader's log line gives a build's time.
function contentSeconds(ms) {
  return ms < 10000 ? (ms / 1000).toFixed(1) + ' s' : Math.round(ms / 1000) + ' s';
}

function contentWhen(utc) {
  const t = Date.parse(utc);
  if (!utc || Number.isNaN(t)) return utc || '';
  return new Date(t).toLocaleString(undefined, { year: 'numeric', month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' });
}

function contentButton(id, label, cmd, title, extra) {
  const running = contentRunning();
  return el('button', {
    class: 'ghost small', type: 'button', id, disabled: !!running, title: running ? 'Close the game first: ' + running : title,
    onclick: () => send(Object.assign({ cmd, game: content.game }, extra || {})),  // the host refuses another folder
  }, label);
}

function renderContent() {
  const card = $('content-card');
  const head = $('content-title');
  if (!card || !head) return;
  const show = !!(state && state.game_found && state.emf_installed);
  card.hidden = head.hidden = !show;
  if (!show || tab !== 'emf') return;
  if (!content.asked) contentAsk();
  const p = content.data && content.data.panel;
  const running = contentRunning();
  const sig = JSON.stringify([p, running]);
  if (sig === content.drawn && card.childElementCount) return;
  content.drawn = sig;
  if (!p) {
    fill(card, el('p', { class: 'muted' }, 'Looking at the EML mods…'));
    return;
  }
  const badge = CONTENT_BADGE[p.status] || ['quiet', p.status];
  const owns = p.status === 'ready' || p.status === 'builds_next' || p.status === 'failed';
  const kids = [];
  kids.push(el('div', { class: 'content-head' },
    el('span', { class: 'badge ' + badge[0] }, badge[1]),
    el('h3', { id: 'content-headline' }, p.headline)));
  if (p.detail) kids.push(el('p', { id: 'content-detail' }, p.detail));
  if (p.why) kids.push(el('p', { class: 'muted small', id: 'content-why' }, 'The loader’s decision for the next start: ' + p.why));
  if (running) kids.push(el('p', { class: 'sheet-warn', role: 'note', id: 'content-running' }, 'Close the game to change these: ' + running));

  // When to apply
  const mode = el('select', { id: 'content-mode', disabled: !!running, title: running ? 'Close the game first: ' + running : null,
    'aria-describedby': 'content-mode-help' },
  CONTENT_MODES.map(([value, label]) => el('option', { value }, label)));
  mode.value = p.mode;
  mode.addEventListener('change', () => send({ cmd: 'content_mode', mode: mode.value, game: content.game }));
  const help = (CONTENT_MODES.find((m) => m[0] === p.mode) || CONTENT_MODES[0])[2];
  kids.push(el('div', { class: 'content-row' }, el('label', { for: 'content-mode' }, 'When to apply'), mode,
    el('span', { class: 'muted small', id: 'content-mode-help' }, help)));

  // the mods: what EMF builds, or (content off, another tool) what it would build
  if (p.mods.length) {
    kids.push(el('h4', { id: 'content-built-title' }, owns ? 'Built by EMF' : 'EMF would build'));
    kids.push(el('ul', { class: 'content-list', id: 'content-built' }, p.mods.map((m) =>
      el('li', {}, el('span', { class: 'content-name' }, m.name), ' ' + m.version,
        m.built ? null : el('span', { class: 'muted small' }, ' — not built yet')))));
  }
  if (p.left_out.length && p.take_over !== 'offer') {  // with the offer, the mods it would cost are listed there
    kids.push(el('h4', {}, 'Left out'));
    kids.push(el('ul', { class: 'content-list', id: 'content-left' }, p.left_out.map((l) =>
      el('li', {}, el('span', { class: 'content-name mono' }, l.folder), ': ' + l.why))));
  }

  // the last build
  const b = p.last_build;
  if (b) {
    const what = b.code === 0 ? 'worked' : b.code === -7 ? 'did not finish' : 'failed (code ' + b.code + ')';
    kids.push(el('div', { class: 'content-last', id: 'content-last' },
      el('h4', {}, 'Last build'),
      el('p', {}, [contentWhen(b.built_at), 'took ' + contentSeconds(b.ms), what, b.mods.length ? b.mods.length + (b.mods.length === 1 ? ' mod' : ' mods') : '']
        .filter(Boolean).join(' · ')),
      b.message ? el('p', { class: b.code === 0 ? 'muted' : 'd-error' }, el('span', {}, b.message)) : null,
      b.errors.length ? el('ul', { class: 'content-list errors' }, b.errors.map((e) => el('li', { class: 'mono' }, e)),
        b.errors_more ? el('li', { class: 'muted' }, '… and ' + b.errors_more + ' more (emf\\content.log has them all)') : null) : null,
      // a good build whose mods warned: part of a mod was not added (a creature pack after a game update)
      (b.warnings || []).length ? el('p', { class: 'content-line' }, b.code === 0
        ? 'A mod reported a problem; the rest of its content works:'
        : 'Mods also reported:') : null,
      (b.warnings || []).length ? el('ul', { class: 'content-list warnings', id: 'content-warnings' },
        b.warnings.map((w) => el('li', { class: 'mono' }, w)),
        b.warnings_more ? el('li', { class: 'muted' }, '… and ' + b.warnings_more + ' more (emf\\content.log has them all)') : null) : null));
  }

  // the patched game files
  if (p.patched_in_place) {
    kids.push(el('div', { class: 'sheet-warn', role: 'note', id: 'content-patched' },
      'The game’s enshrouded.kfc was patched in place earlier (by EML or ShroudForge). EMF builds from the original ' +
      '(enshrouded.kfc.bak) and never changes the game’s files. To clean them, let Steam check them: Steam > ' +
      'Enshrouded > Properties > Installed Files > Verify integrity of game files.'));
  }

  // EML's dbghelp.dll
  if (p.take_over === 'offer') {
    kids.push(el('div', { class: 'content-take' },
      el('p', {}, 'EML is installed and applies the content of the EML mods. EMF can do it instead, without EML: it renames ' +
        'EML’s dbghelp.dll to eml-dbghelp.dll (nothing is deleted). Give it back here at any time; uninstalling EMF ' +
        'puts it back too.'),
      p.take_over_loses.length ? [
        el('p', { class: 'sheet-warn', role: 'note', id: 'content-loses-note' },
          'These EML mods stop working until you give EML’s dbghelp.dll back: EMF leaves them out.'),
        el('ul', { class: 'content-list', id: 'content-loses' }, p.take_over_loses.map((l) =>
          el('li', {}, el('span', { class: 'content-name mono' }, l.folder), ': ' + l.why))),
      ] : null,
      contentButton('content-take-over', 'Let EMF load EML content', 'content_take_over', 'Set EML’s dbghelp.dll aside')));
  } else if (p.take_over === 'given') {
    kids.push(el('div', { class: 'content-take' },
      el('p', {}, 'EMF set EML’s dbghelp.dll aside as ' + p.set_aside + '. Give it back, and EML loads the EML mods again.'),
      contentButton('content-give-back', 'Give EML’s dbghelp.dll back', 'content_give_back', 'Rename it back to dbghelp.dll')));
  }

  // the copy and the build
  const actions = [];
  if (owns && b) actions.push(contentButton('content-rebuild', 'Build again at the next start', 'content_rebuild',
    'EMF forgets the last build, so the next start builds the content again'));
  if (p.copy_there) {
    actions.push(el('span', { class: 'muted small', id: 'content-bytes' }, 'Uses about ' + p.copy_text));
    actions.push(contentButton('content-remove', 'Remove the copy', 'content_remove',
      'Delete emf\\content\\client (the game’s files stay as they are)'));
  }
  if (actions.length) kids.push(el('div', { class: 'content-row' }, actions));
  card.className = 'card content-card ' + p.status;
  fill(card, kids);
}

function contentOnMessage(m) {
  if (!m || typeof m !== 'object') return;
  if (m.type === 'content') {
    if (state && !contentSameFolder(m.game, state.game)) return;  // about a folder that is not shown any more
    content.data = m;
    content.drawn = '';  // drawn again: a refused When to apply shows the stored value again
    if (m.cmd !== 'content') toast(m.ok ? m.text : m.why, !m.ok);
    renderContent();
  } else if (m.type === 'state') {
    if (!contentSameFolder(m.game, content.game) || content.game === null) {  // another folder: nothing of the last one's card stays, nor acts on it
      content.game = m.game;
      content.data = null;
      content.asked = false;
      content.drawn = '';
    }
    const running = !!m.game_running;
    if (content.running && !running) content.asked = false;  // the game stopped: a build may have run
    content.running = running;
    renderContent();
  }
}

if (host) host.addEventListener('message', (e) => contentOnMessage(e.data));
for (const t of document.querySelectorAll('.tab[data-tab="emf"]')) t.addEventListener('click', () => { content.asked = false; renderContent(); });
