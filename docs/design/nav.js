// Three ways to get around Talaria, each shown as: where you land, how you reach sessions, how you reach recordings.
const sessions = `
  <div class="search">${I.list} Search chats</div>
  <div class="sect">Pinned</div><div class="sess"><div class="s on">${I.sparkles}<div class="t">Home lab<small>Both are safe to delete now that…</small></div><span class="badge">running</span></div></div>
  <div class="sect">Today</div><div class="sess">
    <div class="s">${I.term}<div class="t">Disk usage on the server<small>Two things, and one of them is mine.</small></div><span class="when">9:02</span></div>
    <div class="s">${I.mic}<div class="t">Voice test<small>Allowed.</small></div><span class="when">7:41</span></div></div>
  <div class="sect">Yesterday</div><div class="sess">
    <div class="s">${I.cloud}<div class="t">Meeting digest · Sep 23<small>Saved 4 facts, proposed 2 reminders</small></div><span class="when">Tue</span></div>
    <div class="s">${I.term}<div class="t">Pocket TTS voices<small>vera is the closest match</small></div><span class="when">Tue</span></div></div>`;
const recRows = `<div class="list tight">${rows.slice(0,4).map(([d, s, st, k]) => `
    <div class="rowi k-${k}"><span class="round play">${I.play}</span><div class="meta"><div class="d">${d}</div><div class="s">${s}</div><div class="st">${st}</div></div>
    <span class="stat">${k === 'sent' ? I.checkc : k === 'err' ? I.x : k === 'live' ? I.dot : I.dashed}</span></div>`).join('')}</div>`;
const chatBody = `
  <div class="messages">
    <div class="msg user"><div class="label">${I.mic} Voice</div><div class="bubble">What's eating the disk on the server?</div></div>
    <div class="msg assistant"><div class="bubble"><div class="tool">${I.term} Ran <code>df -h</code></div><p>Two things, and one of them is mine: <b>6.4 GB</b> in <code>services/hermes/pocket-tts</code> and <b>443 MB</b> in <code>~/voice-bench</code>. Want me to remove them?</p></div></div>
    <div class="msg user"><div class="bubble">Yes, both.</div></div>
  </div>`;
const composer = (cls = '') => `<div class="composer ${cls}"><div class="row"><span class="pill model"><i class="dot"></i>glm-5.3 · medium</span></div>
  <div class="row"><span class="round plus">${I.plus}</span><div class="field"><span>Message Hermes</span></div><span class="round micb">${I.micf}</span><span class="round sendb">${I.send}</span></div></div>`;
const tabbar = (on) => `<div class="tabbar">${[['Chat', I.sparkles], ['Recorder', I.micf], ['Skills', I.list], ['Settings', I.gear]].map(([n, i]) => `<div class="tab ${n === on ? 'on' : ''}">${i}${n}</div>`).join('')}</div>`;

const B = [
  phone('Land: the chat <small>· title is a menu</small>', `<div class="nav">${I.sidebar}<div class="title"><span class="titlemenu">Home lab ${I.chev}</span></div><div class="group">${I.micf}${I.compose}</div></div>${chatBody}${composer()}`),
  phone('Sessions: swipe from the left <small>· drawer</small>', `<div class="nav">${I.sidebar}<div class="title">Home lab</div><div class="group">${I.micf}${I.compose}</div></div>${chatBody}${composer()}<div class="dim"></div><div class="drawer">${sessions}<div class="foot"><div class="s recs">${I.micf} Recordings</div><div class="s">${I.sparkles} Skills</div><div class="s">${I.gear} Settings</div></div></div>`),
  phone('Recordings: from the drawer <small>· pushed page, back returns</small>', `<div class="nav"><span class="back">${I.chev} Chats</span><div class="title">Recordings</div><span class="round micb" style="width:30px;height:30px">${I.micf}</span></div>${recRows}<div class="list"><div class="foot">Recordings are deleted automatically after 30 days.</div></div>`),
];
const menu = `<div class="dim"></div><div class="menu">
  <div class="mi">${I.compose} Rename</div><div class="mi">${I.sparkles} Skills for this chat</div><div class="mi">${I.list} Model · glm-5.3 · medium</div><div class="mi">${I.term} Pin</div><div class="mi danger">${I.x} Delete chat</div></div>`;
// One inbox: chats and recordings together, newest first, told apart by their icon.
const inbox = `
  <div class="search">${I.list} Search</div>
  <div class="sect">Active</div><div class="sess">
    <div class="s on"><span class="ic rec live">${I.micf}</span><div class="t">Recording · 00:12<small>Recording now</small></div><span class="badge livebadge">live</span></div>
    <div class="s on">${I.sparkles}<div class="t">Home lab<small>Both are safe to delete now that…</small></div><span class="badge">running</span></div></div>
  <div class="sect">Today</div><div class="sess">
    <div class="s"><span class="ic rec">${I.micf}</span><div class="t">Recording · 48:12<small>Sent to Speakr as #3</small></div><span class="when">9:02</span></div>
    <div class="s">${I.sparkles}<div class="t">Disk usage on the server<small>Two things, and one of them is mine.</small></div><span class="when">9:02</span></div>
    <div class="s">${I.sparkles}<div class="t">Voice test<small>Allowed.</small></div><span class="when">7:41</span></div></div>
  <div class="sect">Yesterday</div><div class="sess">
    <div class="s"><span class="ic rec">${I.micf}</span><div class="t">Recording · 01:03<small>Sent to Speakr as #2</small></div><span class="when">10:57 PM</span></div>
    <div class="s">${I.sparkles}<div class="t">Meeting digest · Sep 23<small>Saved 4 facts, proposed 2 reminders</small></div><span class="when">Tue</span></div>
    <div class="s"><span class="ic rec">${I.micf}</span><div class="t">Recording · 00:24<small>Not sent</small></div><span class="when">9:39 PM</span></div>
    <div class="s">${I.sparkles}<div class="t">Pocket TTS voices<small>vera is the closest match</small></div><span class="when">Tue</span></div></div>`;
const recDetail = `
  <div class="detail">
    <div class="dh"><span class="ic rec big">${I.micf}</span><div><div class="d">Wed, Sep 24 · 9:02 AM</div><div class="s">48:12 · 41 MB</div></div></div>
    <div class="player"><span class="round play">${I.pause}</span><div class="scrub"><span>18:04</span><div class="track"><i></i></div><span>48:12</span></div></div>
    <div class="status ok">${I.checkc} Sent to Speakr as #3 · 2 hours ago</div>
    <div class="acts"><span class="b">${I.cloud} Send again</span></div>
    <div class="acts"><span class="b danger">${I.x} Delete</span></div>
  </div>`;
const C = [
  phone('1 · Land: Inbox <small>· chats and recordings, newest first</small>', `<div class="nav"><span style="width:22px"></span><div class="title">Talaria</div><div class="group">${I.gear}</div></div>${inbox}<div class="fab"><span class="b">${I.compose} New chat</span><span class="b mic">${I.micf}</span></div>`),
  phone('2 · A chat <small>· pushed; back returns to the inbox</small>', `<div class="nav"><span class="back">${I.chev} Inbox</span><div class="title"><span class="titlemenu">Home lab ${I.chev}</span></div><div class="group">${I.sparkles}</div></div>${chatBody}${composer()}`),
  phone('3 · Chat title menu <small>· rename, skills, model, pin</small>', `<div class="nav"><span class="back">${I.chev} Inbox</span><div class="title"><span class="titlemenu">Home lab ${I.chev}</span></div><div class="group">${I.sparkles}</div></div>${chatBody}${composer()}${menu}`),
  phone('4 · A recording <small>· pushed; play, send, delete</small>', `<div class="nav"><span class="back">${I.chev} Inbox</span><div class="title">Recording</div><span style="width:22px"></span></div>${recDetail}`),
  phone('5 · Recorder <small>· the mic button on the inbox</small>', `<div class="rec"><div class="bar"><span class="back">${I.chev} Inbox</span>${I.chev}</div><div class="top"><div class="state"><span class="live">${I.micf}</span>Recording</div><div class="timer">12:34</div></div><div class="note"></div><div class="buttons"><div class="r"><span class="big pause">${I.pause}</span></div><div class="r"><span class="big cancel">${I.x}</span><span class="big done">${I.check}</span></div></div></div>`),
];
const block = (n, title, why, frames) => `<h2 class="v">${n} · ${title}</h2><p class="why">${why}</p><div class="gallery">${frames.join('')}</div>`;
document.getElementById('study').innerHTML =
  block('C', 'Inbox — chosen', 'One list for everything you did with Talaria: chats and recordings together, newest first, with the icon telling them apart (sparkles for a chat, red mic for a recording). Anything still going on, a running chat or a live recording, sits at the top under Active. Every row pushes a page with a real back button; the chat title opens a menu for rename, skills, model and pin. The two buttons at the bottom start a chat or a recording.', C) +
  block('B', 'Drawer — not chosen, kept for reference', 'What the app does today, tightened: land in the last chat, swipe from the left for sessions, and Recordings, Skills and Settings live at the bottom of the drawer. Fewest chrome pixels; everything else is a swipe or a push.', B);
