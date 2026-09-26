// Tasks, v3. Triage decides when (today, tomorrow, a date, time optional) or never; everything
// scheduled lives in Apple Reminders; a reminder can be handed to Hermes, and Hermes work is the
// kanban shown as two vertical lists. One page, three segments: Triage · Days · Hermes.
I.tasks = '<svg class="icon" viewBox="0 0 24 24"><path d="M4 6l2 2 3-3M4 12l2 2 3-3M4 18l2 2 3-3M12 6h9M12 12h9M12 18h9"/></svg>';
I.cal = '<svg class="icon" viewBox="0 0 24 24"><rect x="3" y="5" width="18" height="16" rx="3"/><path d="M3 10h18M8 3v4M16 3v4"/></svg>';
I.clock = '<svg class="icon" viewBox="0 0 24 24"><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/></svg>';
I.person = '<svg class="icon" viewBox="0 0 24 24"><circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/></svg>';
I.bot = '<svg class="icon" viewBox="0 0 24 24"><rect x="4" y="8" width="16" height="12" rx="3"/><path d="M12 4v4M9 14h.01M15 14h.01M2 13v3M22 13v3"/></svg>';
I.bell = '<svg class="icon" viewBox="0 0 24 24"><path d="M6 16V11a6 6 0 0 1 12 0v5l2 2H4zM10 21h4"/></svg>';
I.archive = '<svg class="icon" viewBox="0 0 24 24"><rect x="3" y="4" width="18" height="5" rx="1.5"/><path d="M5 9v10a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1V9M10 13h4"/></svg>';
I.bolt = '<svg class="icon" viewBox="0 0 24 24"><path d="M13 2L4 14h7l-1 8 9-12h-7z"/></svg>';
I.mail = '<svg class="icon" viewBox="0 0 24 24"><rect x="3" y="5" width="18" height="14" rx="2"/><path d="M3 7l9 6 9-6"/></svg>';
I.msg = '<svg class="icon" viewBox="0 0 24 24"><path d="M4 5h16v11H9l-5 4z"/></svg>';
I.gh = '<svg class="icon" viewBox="0 0 24 24"><circle cx="12" cy="12" r="9"/><path d="M9 16v-2l-1-1M15 16v-2l1-1M9 9a3 3 0 0 1 6 0c0 2-1 2-3 3-2-1-3-1-3-3z"/></svg>';
I.sun = '<svg class="icon" viewBox="0 0 24 24"><circle cx="12" cy="12" r="4"/><path d="M12 2v3M12 19v3M2 12h3M19 12h3M5 5l2 2M17 17l2 2M5 19l2-2M17 7l2-2"/></svg>';
I.scan = '<svg class="icon" viewBox="0 0 24 24"><circle cx="11" cy="11" r="6"/><path d="M20 20l-4.5-4.5M11 8v3l2 1"/></svg>';
I.checklist = '<svg class="icon" viewBox="0 0 24 24"><circle cx="12" cy="12" r="9"/><path d="M8.5 12.5l2.5 2.5 5-5"/></svg>';
I.pr = '<svg class="icon" viewBox="0 0 24 24"><circle cx="6" cy="5" r="2.5"/><circle cx="6" cy="19" r="2.5"/><circle cx="18" cy="19" r="2.5"/><path d="M6 7.5v9M18 16.5V11a3 3 0 0 0-3-3h-4M13 5l-2 3 2 3"/></svg>';
I.next = '<svg class="icon" viewBox="0 0 24 24"><path d="M5 12h14M13 6l6 6-6 6"/></svg>';

const hrow = (ic, icon, title, small, right = '') => `<div class="s"><span class="ic ${ic}">${icon}</span><div class="t">${title}<small>${small}</small></div>${right}</div>`;
const tag = (s) => `<span class="tag">#${s}</span>`;
const src = (icon, s) => `<span class="src">${icon}${s}</span>`;
const hm = (state, cls = '') => `<span class="hm ${cls}">${I.bot}${state}</span>`;
const sectn = (name, n = '', chev = false) => `<div class="sect">${name}${n !== '' ? `<span class="n">${n}</span>` : ''}${chev ? I.chev : ''}</div>`;
const tnav = (back, title, right = '') => `<div class="nav"><span class="back">${I.chev} ${back}</span><div class="title">${title}</div><div class="group">${right}</div></div>`;
const seg = (on) => `<div class="seg tasks">${[['Triage', '<i class="warn">3</i>'], ['Days', ''], ['Hermes', '<i>2</i>']].map(([n, b]) => `<span class="${n === on ? 'on' : ''}">${n}${b}</span>`).join('')}</div>`;
const page = (on, body) => `${tnav('Inbox', 'Tasks', `<span class="iconbtn sm">${I.plus}</span>`)}${seg(on)}${body}`;

// 1 · the inbox row
const inboxTasks = `
  ${searchRow()}
  <div class="sect">Active</div><div class="sess">
    <div class="s on"><span class="ic task">${I.tasks}</span><div class="t">Tasks<small>9 to triage · 2 in progress</small></div><span class="badge warn">9</span></div>
    <div class="s on">${I.sparkles}<div class="t">Home lab<small>Both are safe to delete now that…</small></div><span class="badge">running</span></div></div>
  <div class="sect">Today</div><div class="sess">
    <div class="s"><span class="ic rec">${I.micf}</span><div class="t">Call with Roger<small>48:12 · Sent to Speakr as #3</small></div><span class="when">9:02</span></div>
    <div class="s">${I.sparkles}<div class="t">Disk usage on the server<small>Two things, and one of them is mine.</small></div><span class="when">9:02</span></div>
    <div class="s">${I.sparkles}<div class="t">Voice test<small>Allowed.</small></div><span class="when">7:41</span></div></div>
  <div class="sect">Yesterday</div><div class="sess">
    <div class="s"><span class="ic rec">${I.micf}</span><div class="t">Recording · 01:03<small>Sent to Speakr as #2</small></div><span class="when">10:57 PM</span></div>
    <div class="s">${I.sparkles}<div class="t">Meeting digest · Sep 23<small>Saved 4 facts</small></div><span class="when">Tue</span></div>
    <div class="s">${I.sparkles}<div class="t">Pocket TTS voices<small>vera is the closest match</small></div><span class="when">Tue</span></div></div>`;

// Two lists. Triage: what came in, plus what Hermes has not started. In progress: what Hermes is doing.
const seg2 = (on) => `<div class="seg tasks">${[['Triage', '<i class="warn">9</i>'], ['In progress', '<i>2</i>']].map(([n, b]) => `<span class="${n === on ? 'on' : ''}">${n}${b}</span>`).join('')}</div>`;
const page2 = (on, body, right = `<span class="iconbtn sm">${I.scan}</span>`) => `${tnav('Inbox', 'Tasks', right)}${seg2(on)}${body}`;
const irow = (icon, title, small, right = '', cls = '') => `<div class="s ${cls}"><span class="ic">${icon}</span><div class="t">${title}<small>${small}</small></div>${right}</div>`;
const brow = (icon, title, small) => `<div class="s"><span class="ic bot">${icon}</span><div class="t">${title}<small>${small}</small></div><span class="badge soft">queued</span></div>`;

// 2 · triage: one list, newest first. A swipe on a row: Me (right) or Ignore (left).
const triageList = page2('Triage', `
  <div class="prog" style="padding:8px 14px"><div class="ph" style="font-size:13px"><span class="vdot"></span>Scanning · 21 of 56<span class="stop" style="color:var(--muted)">since Tue 9:02</span></div></div>
  ${sectn('New', 7)}<div class="sess">
    ${irow(I.micf, 'Reply to Roger about the invoice', 'Call with Roger · 31:40 · by Friday', '<span class="when">9:02</span>')}
    <div class="s swipe"><span class="ic">${I.mail}</span><div class="t">Renew the domain<small>Mail · Namecheap · expires Oct 3</small></div><span class="act">${I.person}Me</span></div>
    ${irow(I.msg, 'Send Summer the permission form', 'iMessage · Summer · asked twice', '<span class="when">Tue</span>')}
    ${irow(I.gh, 'Speakr upload fails on a 401 after token refresh', 'talaria #12 · assigned to you', '<span class="when">Tue</span>')}
    ${irow(I.gh, 'Flaky test in sync worker', 'koblime #402 · mentioned you', '<span class="when">Tue</span>')}
    ${irow(I.micf, 'Rotate the WireGuard keys', 'Meeting digest · Sep 23', '<span class="when">Tue</span>')}
    ${irow(I.sparkles, 'Try Kyutai\'s new voice', 'Chat · Pocket TTS voices', '<span class="when">Tue</span>')}</div>
  ${sectn('Hermes backlog', 3)}<div class="sess">
    <div class="s swipe"><span class="ic bot">${I.bot}</span><div class="t">Speakr: retry on 401 (follow-up)<small>from talaria #12 · not started</small></div><span class="act">${I.play}Start</span></div>
    <div class="s"><span class="ic bot">${I.sparkles}</span><div class="t">Backups: verify the restore path<small>from chat · not started</small></div></div>
    <div class="s"><span class="ic">${I.clock}</span><div class="t">Docs: the tasks screen<small>after <b>Dark mode for Talaria</b> · starts by itself</small></div></div></div>
  <div class="hint" style="margin-top:10px">New: swipe right for Me, left to ignore. Backlog: swipe right to start, left to drop.</div>`);

// 3 · an item: the source, and three answers
const item = `${tnav('Tasks', 'Renew the domain', `<span class="iconbtn sm">${I.morec}</span>`)}
  <div class="td">
    <div class="state" style="color:var(--muted)"><span class="vdot"></span>Mail · Namecheap<span class="who">Wed 4:12 PM</span></div>
    <div class="body"><p><b>Your domain sainaney.com expires on Oct 3.</b> Renew now to avoid interruption. Auto-renew is off for this domain.</p></div>
    <div class="why" style="padding:10px 12px;border-radius:10px;background:var(--accent-soft,rgba(62,99,240,.08));font-size:14px;line-height:1.4"><b style="display:block;font-size:11px;color:var(--accent);text-transform:uppercase;letter-spacing:.04em;margin-bottom:2px">Why it is here</b>A deadline, and auto-renew is off. Suggested: remind on Oct 1.</div>
    <div class="pr">${I.mail} Open in Mail ${I.chev}</div>
  </div>
  <div class="acts3"><span class="a">${I.person}Me</span><span class="a">${I.bot}Agent</span><span class="a muted">${I.x}Ignore</span></div>`;

const itemB = `${tnav('Tasks', 'Renew the domain', `<span class="iconbtn sm">${I.morec}</span>`)}
  <div class="td">
    <div class="state" style="color:var(--muted)"><span class="vdot"></span>Mail · Namecheap<span class="who">Wed 4:12 PM</span></div>
    <div class="body"><p><b>Your domain sainaney.com expires on Oct 3.</b> Renew now to avoid interruption. Auto-renew is off for this domain.</p></div>
    <div class="why" style="padding:10px 12px;border-radius:10px;background:var(--accent-soft,rgba(62,99,240,.08));font-size:14px;line-height:1.4"><b style="display:block;font-size:11px;color:var(--accent);text-transform:uppercase;letter-spacing:.04em;margin-bottom:2px">Why it is here</b>A deadline, and auto-renew is off. Suggested: remind on Oct 1.</div>
    <div class="pr">${I.mail} Open in Mail ${I.chev}</div>
    <div class="inl"><span>${I.person} Me</span><span>${I.bot} Agent</span><span class="muted">Ignore</span></div>
  </div>
  `;

// 4 · remind: a day, time optional, which list
const remindSheet = `<div class="dim"></div><div class="sheet">
    <div class="grab"></div><div class="sh"><span>Me<small>Renew the domain · goes to Reminders</small></span></div>
    <div class="opt on">${I.cal}<div class="t">Thu Oct 1</div>${I.chev}</div>
    <div class="opt">${I.clock}<div class="t">At a time<small>Off: an all-day reminder</small></div><span class="sw"><i></i></span></div>
    <div class="opt">${I.list}<div class="t">List</div><span class="k">Admin ${I.chev}</span></div>
    <div class="go">Add to Reminders</div>
    <div class="note">The mail link goes in the reminder's URL. It leaves Triage; Reminders takes it from here.</div></div>`;
const remind = `${item}${remindSheet}`;


// 4b · Ignore, then why: a toast offers it; the chat proposes a rule for the screener
const ignoredToast = page2('Triage', `
  ${sectn('New', 6)}<div class="sess">
    ${irow(I.micf, 'Reply to Roger about the invoice', 'Call with Roger · 31:40 · by Friday', '<span class="when">9:02</span>')}
    ${irow(I.msg, 'Send Summer the permission form', 'iMessage · Summer · asked twice', '<span class="when">Tue</span>')}
    ${irow(I.gh, 'Speakr upload fails on a 401 after token refresh', 'talaria #12 · assigned to you', '<span class="when">Tue</span>')}
    ${irow(I.gh, 'Flaky test in sync worker', 'koblime #402 · mentioned you', '<span class="when">Tue</span>')}</div>
  <div class="menu" style="top:auto;bottom:40px;width:calc(100% - 28px);left:14px;transform:none;display:flex;align-items:center;gap:10px;padding:10px 14px;font-size:14px"><span>${I.x}</span><span style="flex:1">Ignored <b>Namecheap: SSL sale</b></span><span style="color:var(--accent);font-weight:600">Why?</span><span style="color:var(--accent);font-weight:600">Undo</span></div>`);
const whyChat = `<div class="nav"><span class="back">${I.chev} Tasks</span><div class="title">Why ignore</div><div class="group"><span class="iconbtn sm">${I.morec}</span><span class="modebtn">${I.wave}</span></div></div>
  <div class="messages">
    <div class="msg assistant"><div class="bubble"><div class="tool">${I.list} Your last 20 decisions on Namecheap</div><p>You ignored 6 Namecheap mails this month and kept 1, the renewal notice. Is it marketing you do not want, or all of Namecheap?</p></div></div>
    <div class="msg user"><div class="bubble">Marketing. Renewals and invoices I want.</div></div>
    <div class="card approval"><div class="h">${I.sparkles} Screener rule</div>
      <p style="margin:6px 0 4px;font-size:14px">Namecheap: skip promotions and sales. Keep renewals, expiries and invoices, and suggest a reminder a few days before the date.</p>
      <p style="margin:0;font-size:12.5px;color:var(--muted)">Applies to the next scan. Rules live in Hermes's memory; you can read and edit them.</p>
      <div class="actions"><button>Edit</button><button class="always">Save rule</button></div></div>
  </div>
  <div class="composer"><div class="row"><span class="pill model"><i class="dot"></i>glm-5.3 · medium</span></div>
  <div class="row"><span class="round plus">${I.plus}</span><div class="field"><span>Message Hermes</span></div><span class="round sendb">${I.send}</span></div></div>`;

// 5 · in progress: what Hermes is doing; Done folded
const inProgress = page2('In progress', `
  <div class="sess">
    ${irow(I.bot, 'Widget: show the last recording', 'coder-vm · 12 min · nsainaney.vm', '<span class="badge">live</span>')}
    ${irow(I.person, 'Dark mode for Talaria', 'coder-vm · <span class="q">Slate or Slate light as the base?</span>', '<span class="badge warn">reply</span>')}</div>
  ${sectn('Done', 'this week')}<div class="sess">
    ${irow(I.check, 'Speakr: retry on 401', 'coder-vm · PR #14 · 9 min', '<span class="when">8:52</span>', 'ok')}
    ${irow(I.check, 'Backups: verify the restore path', 'Hermes · restored 3 files to /tmp, all matched', '<span class="when">Mon</span>', 'ok')}
    ${irow(I.check, 'Move Pocket TTS to nix', 'coder-vm · PR #9 merged', '<span class="when">Sep 20</span>', 'ok')}
    ${irow(I.x, 'Try the new voice model', 'Hermes · gave up: model not installed', '<span class="when">Sep 19</span>', 'fail')}</div>
  <div class="hint" style="margin-top:8px">Done keeps 7 days; older is in search.</div>`);

// 6 · a card
const detail = `${tnav('Tasks', 'Dark mode for Talaria', `<span class="iconbtn sm">${I.morec}</span>`)}
  <div class="td">
    <div class="state"><span class="vdot"></span>Needs you<span class="who">coder-vm · blocked 14 min</span></div>
    <div class="body"><p>Add a dark appearance to Talaria following docs/design/slate.html. Keep the Glass layout; only the tokens change. Test on the inbox, chat and voice screens.</p></div>
    <div class="tl">
      <div class="e"><i></i><div class="w">Came in from chat <b>Home lab</b><small>Yesterday, 10:12</small></div></div>
      <div class="e"><i></i><div class="w">Agent · to the backlog<small>You, yesterday 10:13</small></div></div>
      <div class="e acc"><i></i><div class="w">Started · 4 questions · <b>open the chat</b><small>You, today 8:31</small></div></div>
      <div class="e acc"><i></i><div class="w">Proceed · coder-vm<small>You, today 8:39</small></div></div>
      <div class="e acc"><i></i><div class="w">Started in nsainaney.vm<small>Today, 8:40 · branch crew/dark-mode</small></div></div>
      <div class="e on"><i></i><div class="w">Asked a question<small>Today, 8:48</small><div class="q">Slate or Slate light as the base? The mockups have both and the brief does not say.</div></div></div>
    </div>
  </div>
  <div class="composer reply"><div class="row"><span class="round plus">${I.plus}</span><div class="field"><span>Reply to coder-vm</span></div><span class="round sendb">${I.send}</span></div></div>`;


// 7 · Hermes: a discussion first. Hermes restates the item, looks up what it can, and asks one
// question at a time until it can write the card. "Just do it" files with what it has.
const discuss = `<div class="nav"><span class="back">${I.chev} Tasks</span><div class="title">Speakr upload 401</div><div class="group"><span class="iconbtn sm">${I.morec}</span><span class="modebtn">${I.wave}</span></div></div>
  <div class="messages">
    <div class="msg assistant"><div class="bubble">
      <div class="tool">${I.gh} Read talaria #12 and <code>SpeakrClient.swift</code></div>
      <p>Uploads fail with a 401 right after the token refresh. The client refreshes, then retries with the <b>old</b> header, so the first retry always fails and the second succeeds. Fix is in the retry path.</p>
      <p>One question: should a 401 on the retry surface in the recording row as "Not sent", or keep retrying silently until the next app open?</p></div></div>
    <div class="msg user"><div class="bubble">Show it as Not sent, with a resend.</div></div>
    <div class="msg assistant"><div class="bubble"><p>Got it. Last one: coder-vm on a branch with a PR, or me directly on the repo?</p></div></div>
  </div>
  <div class="composer"><div class="row"><span class="pill model"><i class="dot"></i>glm-5.3 · medium</span><span style="flex:1"></span><span class="pill sess">2 of ~3</span></div>
  <div class="row"><span class="round plus">${I.plus}</span><div class="field"><span>coder-vm, proceed</span></div><span class="round sendb">${I.send}</span></div></div>`;

// 8 · the card, proposed in the chat; File puts it in the backlog with the chat linked
const proposal = `<div class="nav"><span class="back">${I.chev} Tasks</span><div class="title">Speakr upload 401</div><div class="group"><span class="iconbtn sm">${I.morec}</span><span class="modebtn">${I.wave}</span></div></div>
  <div class="messages">
    <div class="msg user"><div class="bubble">coder-vm, proceed</div></div>
    <div class="msg assistant"><div class="bubble"><p>Here is the task as I understand it.</p></div></div>
    <div class="card approval"><div class="h">${I.bot} coder-vm · talaria</div>
      <p style="margin:6px 0 4px;font-weight:600">Fix Speakr upload 401 after token refresh</p>
      <p style="margin:0 0 6px;font-size:13.5px">Retry with the refreshed token in <code>SpeakrClient.upload</code>; on a second 401 mark the recording <i>Not sent</i> with resend. Closes talaria #12.</p>
      <p style="margin:0;font-size:12.5px;color:var(--muted)">Verify: build, then upload against a stale token. Links: issue #12, this chat.</p>
      <div class="actions"><button>Edit</button><button class="always">Proceed</button></div></div>
  </div>
  <div class="composer"><div class="row"><span class="pill model"><i class="dot"></i>glm-5.3 · medium</span></div>
  <div class="row"><span class="round plus">${I.plus}</span><div class="field"><span>Message Hermes</span></div><span class="round sendb">${I.send}</span></div></div>`;

const T = [
  phone('1 · Inbox <small>· one row</small>', `${inboxTasks}${fab}`),
  phone('2 · Triage <small>· New goes to Reminders or to the Hermes backlog below it</small>', triageList),
  phone('3 · An item <small>· the source; Me, Agent (to the backlog), or Ignore</small>', item),
  phone('3b · An item, B <small>· the same three words, in the text under the source</small>', itemB),
  phone('4 · Me <small>· a day, time optional, which list; then Reminders owns it</small>', remind),
  phone('4b · Ignored <small>· a toast with Why? and Undo; nothing else happens</small>', ignoredToast),
  phone('4c · Why <small>· Hermes checks your past decisions, asks one thing, proposes a rule</small>', whyChat),
  phone('5 · Start <small>· a chat that enriches the task: Hermes looks up what it can and asks the rest, one question at a time</small>', discuss),
  phone('6 · Proceed <small>· the enriched task, in the chat; Proceed starts Hermes on it</small>', proposal),
  phone('7 · In progress <small>· what Hermes is doing, then Done this week</small>', inProgress),
  phone('8 · A card <small>· the trail, and the reply that unblocks it</small>', detail),
];

const _t = document.getElementById('tasks'); if (_t) _t.innerHTML =
  block('Tasks', '', 'Two lists. <b>Triage</b> is what came in (mail, iMessage, meetings, issues with your name, things a chat filed) plus what Hermes has queued and not started, newest first. Three answers per row: <b>Me</b> (a day, time optional, a list; it becomes an Apple Reminder with the source link and leaves Talaria), <b>Agent</b> (the Hermes backlog), <b>Ignore</b>. A filed card is queued: the dispatcher starts it on its own, in priority order, as soon as a worker slot is free. Swipe right on a backlog row to start it next; swipe left to hold it, and a held card waits until you start it. A card waiting on another card says so and starts when that one is done. Agent parks it in the backlog as a bare card; nothing in the backlog starts on its own. <b>Start</b> (swipe right on a backlog row) opens a chat that enriches the task: Hermes reads the source and whatever it can look up itself, asks the rest one question at a time, like the grill-me skill, and posts the task back as a card in the chat with who, the approach, how to verify and the links. <b>Proceed</b> is what starts Hermes on it; Edit changes the card first. A card waiting on another card says so and starts by itself when that one is done. <b>In progress</b> is what Hermes is doing, with questions inline; Done is one folded line. No day views: Reminders has them.', T);

// Cards: three entities Hermes can put in a chat, first class like markdown. One anatomy:
// head (glyph · reference · status), title, meta line, an optional snippet or question, light actions.
// A URL to a known entity unfurls into the card; a fenced ```card block makes a card for something that does not exist yet (dashed).
const issueCard = (st = 'open', act = true) => `<div class="ecard">
    <div class="eh">${I.gh}<span class="eref">talaria #12</span><span class="st ${st}">${st}</span></div>
    <div class="et">Speakr upload fails on a 401 after token refresh</div>
    <div class="em"><span class="lb bug">bug</span>${I.person} narayan · opened Tue · 2 comments</div>
    <div class="es">After the dashboard token refreshes, the next upload retries with the old header and fails once before succeeding.</div>
    ${act ? `<div class="ea"><span>${I.link} Open</span><span>${I.person} Me</span><span>${I.bot} Agent</span></div>` : ''}
  </div>`;
const taskCard = (kind) => ({
  backlog: `<div class="ecard"><div class="eh">${I.bot}<span class="eref">t_3f9a</span><span class="st">backlog</span></div>
    <div class="et">Speakr: retry on 401 (follow-up)</div><div class="em">from <span class="epill">${I.gh} talaria #12</span> · not started</div>
    <div class="ea"><span>${I.play} Start</span><span class="muted">Drop</span></div></div>`,
  proposed: `<div class="ecard proposed"><div class="eh">${I.bot}<span class="eref">coder-vm · talaria</span><span class="st new">proposed</span></div>
    <div class="et">Fix Speakr upload 401 after token refresh</div><div class="em">closes <span class="epill">${I.gh} talaria #12</span> · verify: build, upload with a stale token</div>
    <div class="es">Retry with the refreshed token in SpeakrClient.upload; on a second 401 mark the recording Not sent with resend.</div>
    <div class="ea"><span class="muted">${I.compose} Edit</span><span class="go">${I.play} Proceed</span></div></div>`,
  running: `<div class="ecard"><div class="eh">${I.bot}<span class="eref">t_3f9a</span><span class="st run">running</span></div>
    <div class="et">Fix Speakr upload 401 after token refresh</div><div class="em">coder-vm · 12 min · nsainaney.vm · crew/speakr-401</div>
    <div class="ea"><span>${I.term} Log</span><span class="danger">${I.x} Stop</span></div></div>`,
  need: `<div class="ecard"><div class="eh">${I.bot}<span class="eref">t_2b17</span><span class="st need">needs you</span></div>
    <div class="et">Dark mode for Talaria</div><div class="em">coder-vm · blocked 14 min</div>
    <div class="eq">Slate or Slate light as the base? The mockups have both and the brief does not say.</div>
    <div class="ea"><span>${I.compose} Reply</span></div></div>`,
  done: `<div class="ecard"><div class="eh">${I.bot}<span class="eref">t_3f9a</span><span class="st done">done</span></div>
    <div class="et done">Fix Speakr upload 401 after token refresh</div><div class="em">coder-vm · 9 min · <span class="epill">${I.pr} PR #14</span></div></div>`,
})[kind];
const remCard = (kind) => ({
  proposed: `<div class="ecard proposed"><div class="eh"><span class="circ"></span><span class="ldot" style="background:#ff9f0a"></span><span class="eref">Admin</span><span class="st new">proposed</span></div>
    <div class="et">Renew the domain</div><div class="em">${I.cal} Thu Oct 1 · all day · <span class="tag">#mail</span> · <span class="epill">${I.mail} Namecheap</span></div>
    <div class="ea"><span class="muted">${I.compose} Edit</span><span class="go">${I.bell} Add to Reminders</span></div></div>`,
  open: `<div class="ecard"><div class="eh"><span class="circ"></span><span class="ldot" style="background:#ff9f0a"></span><span class="eref">Admin</span></div>
    <div class="et">Renew the domain</div><div class="em">${I.cal} <span class="due">Thu Oct 1</span> · <span class="tag">#mail</span> · <span class="epill">${I.mail} Namecheap</span></div>
    <div class="ea"><span>${I.link} Open</span><span>${I.next} Tomorrow</span><span>${I.bot} Agent</span></div></div>`,
  over: `<div class="ecard"><div class="eh"><span class="circ"></span><span class="ldot" style="background:#3e63f0"></span><span class="eref">Server</span><span class="st over">overdue</span></div>
    <div class="et">Disk alert at 75%</div><div class="em">${I.cal} <span class="due over">Wed Sep 24</span> · <span class="tag">#chat</span> · <span class="epill">${I.sparkles} Disk usage on the server</span></div>
    <div class="ea"><span>${I.link} Open</span><span>${I.next} Tomorrow</span><span>${I.bot} Agent</span></div></div>`,
  done: `<div class="ecard"><div class="eh"><span class="circ on"></span><span class="ldot" style="background:#ff9f0a"></span><span class="eref">Admin</span></div>
    <div class="et done">Renew the domain</div><div class="em">done Thu 9:12</div></div>`,
})[kind];

const chatNav = (t) => `<div class="nav"><span class="back">${I.chev} Inbox</span><div class="title">${t}</div><div class="group"><span class="iconbtn sm">${I.morec}</span><span class="modebtn">${I.wave}</span></div></div>`;
const cardsInChat = `${chatNav('Speakr 401')}
  <div class="messages cards">
    <div class="msg user"><div class="bubble">What's the state of the Speakr upload bug?</div></div>
    <div class="msg assistant"><div class="bubble"><p>The issue is still open on GitHub:</p></div></div>
    ${issueCard('open')}
    <div class="msg assistant"><div class="bubble"><p>There is a card for it, not started yet, and you set yourself a reminder to look at the retry path:</p></div></div>
    ${taskCard('backlog')}
    ${remCard('open').replace('Renew the domain', 'Look at the Speakr retry path').replace('Admin', 'Talaria').replace('#mail', '#github').replace(`${I.mail} Namecheap`, `${I.gh} talaria #12`).replace('Thu Oct 1', 'Mon Sep 29')}
    <div class="msg assistant"><div class="bubble"><p>Want me to start the card? The reminder can go once <span class="epill">${I.bot} t_3f9a</span> is done.</p></div></div>
  </div>
  ${composer()}`;
const cardStates = `${chatNav('Card states')}
  <div class="messages cards" style="gap:6px">
    ${taskCard('proposed')}
    ${taskCard('running')}
    ${taskCard('need')}
    ${taskCard('done')}
    ${remCard('proposed')}
    ${remCard('over')}
    ${remCard('done')}
  </div>`;
const cardPills = `${chatNav('Home lab')}
  <div class="messages cards">
    <div class="msg user"><div class="bubble">Anything waiting on me?</div></div>
    <div class="msg assistant"><div class="bubble"><p>Two things. <span class="epill">${I.bot} Dark mode for Talaria</span> is blocked on a question from coder-vm, and <span class="epill"><i style="background:#3e63f0"></i> Disk alert at 75%</span> was due Wednesday. <span class="epill">${I.gh} koblime #402</span> mentions you but nobody is assigned.</p><p>Tap any of them for the card.</p></div></div>
    ${taskCard('need')}
  </div>
  ${composer()}`;
const K = [
  phone('1 · In a chat <small>· an issue, a task and a reminder, unfurled from links</small>', cardsInChat),
  phone('2 · States <small>· proposed (dashed), running, needs you, done; overdue and done reminders</small>', cardStates),
  phone('3 · Pills <small>· the same entities inside a sentence; tap for the card</small>', cardPills),
];
if (_t) _t.innerHTML += block('Cards', '', 'Three things Hermes can put in a chat as themselves: a GitHub issue, a kanban task, an Apple Reminder. One anatomy for all three: a head row with the glyph, the reference and a status pill; the title; one meta line (who, when, labels, where it came from); an optional snippet or, for a blocked task, the question; then light actions with no boxes. Status colours are the ones already in use: green done or open, purple closed, orange needs you or overdue, blue running. A <b>proposed</b> card is dashed: it does not exist yet, and its one strong action creates it (Proceed, Add to Reminders). Inside a sentence the same entity is a <b>pill</b>, and tapping a pill shows the card. A reminder\'s circle in the head is its checkbox, as in Reminders. Cards render from the context store, so they show live state (a task that finishes updates in place) and never need Hermes to describe status in prose.', K);
