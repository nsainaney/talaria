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

const menu = `<div class="dim"></div><div class="menu">
  <div class="mi">${I.compose} Rename</div><div class="mi">${I.sparkles} Skills for this chat</div><div class="mi">${I.list} Model · glm-5.3 · medium</div><div class="mi">${I.term} Pin</div><div class="mi danger">${I.x} Delete chat</div></div>`;
// One inbox: chats and recordings together, newest first, told apart by their icon.
const searchRow = (label = "All") => `<div class="searchrow top"><div class="search">${I.list} Search</div><span class="iconbtn">${I.gear}</span><span class="filter">${I.filter} ${label}</span></div>`;
const inbox = `
  ${searchRow()}
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
const inboxFiltered = `
  ${searchRow("Recordings")}
  <div class="sect">Active</div><div class="sess">
    <div class="s on"><span class="ic rec live">${I.micf}</span><div class="t">Recording · 00:12<small>Recording now</small></div><span class="badge livebadge">live</span></div></div>
  <div class="sect">Today</div><div class="sess">
    <div class="s"><span class="ic rec">${I.micf}</span><div class="t">Recording · 48:12<small>Sent to Speakr as #3</small></div><span class="when">9:02</span></div></div>
  <div class="sect">Yesterday</div><div class="sess">
    <div class="s"><span class="ic rec">${I.micf}</span><div class="t">Recording · 01:03<small>Sent to Speakr as #2</small></div><span class="when">10:57 PM</span></div>
    <div class="s"><span class="ic rec">${I.micf}</span><div class="t">Recording · 00:24<small>Not sent</small></div><span class="when">9:39 PM</span></div></div>
  <div class="menu filtermenu"><div class="mi">${I.list} All</div><div class="mi">${I.sparkles} Chats</div><div class="mi on">${I.micf} Recordings ${I.check}</div></div>`;
const recDetail = `
  <div class="detail">
    <div class="dh"><span class="ic rec big">${I.micf}</span><div><div class="d">Wed, Sep 24 · 9:02 AM</div><div class="s">48:12 · 41 MB</div></div></div>
    <div class="player"><span class="round play">${I.pause}</span><div class="scrub"><span>18:04</span><div class="track"><i></i></div><span>48:12</span></div></div>
    <div class="status ok">${I.checkc} Sent to Speakr as #3 · 2 hours ago</div>
    <div class="acts"><span class="b">${I.cloud} Send again</span></div>
    <div class="acts"><span class="b danger">${I.x} Delete</span></div>
  </div>`;
const C = [
  phone('1 · Land: Inbox <small>· chats and recordings, newest first</small>', `${inbox}<div class="fab"><span class="b">${I.compose} New chat</span><span class="b mic">${I.micf}</span></div>`),
  phone('2 · Filter <small>· All, Chats or Recordings</small>', `${inboxFiltered}<div class="fab"><span class="b">${I.compose} New chat</span><span class="b mic">${I.micf}</span></div>`),
  phone('3 · A chat <small>· pushed; back returns to the inbox</small>', `<div class="nav"><span class="back">${I.chev} Inbox</span><div class="title"><span class="titlemenu">Home lab ${I.chev}</span></div><div class="group">${I.sparkles}</div></div>${chatBody}${composer()}`),
  phone('4 · Chat title menu <small>· rename, skills, model, pin</small>', `<div class="nav"><span class="back">${I.chev} Inbox</span><div class="title"><span class="titlemenu">Home lab ${I.chev}</span></div><div class="group">${I.sparkles}</div></div>${chatBody}${composer()}${menu}`),
  phone('5 · A recording <small>· pushed; play, send, delete</small>', `<div class="nav"><span class="back">${I.chev} Inbox</span><div class="title">Recording</div><span style="width:22px"></span></div>${recDetail}`),
  phone('6 · Recorder <small>· the mic button on the inbox</small>', `<div class="rec"><div class="bar"><span class="back">${I.chev} Inbox</span>${I.chev}</div><div class="top"><div class="state"><span class="live">${I.micf}</span>Recording</div><div class="timer">12:34</div></div><div class="note"></div><div class="buttons"><div class="r"><span class="big pause">${I.pause}</span></div><div class="r"><span class="big cancel">${I.x}</span><span class="big done">${I.check}</span></div></div></div>`),
];
const block = (n, title, why, frames) => `<h2 class="v">${n}${title ? " · " + title : ""}</h2><p class="why">${why}</p><div class="gallery">${frames.join('')}</div>`;

// Voice chat: a minimal screen. Your words appear as they are understood; Hermes's reply renders
// with markdown; one big Pause (mic stops, Hermes waits) and a Stop that returns to the text chat.
const vTop = (status, cls = '') => `<div class="nav"><span class="back">${I.chev} Home lab</span><div class="title"></div><span style="width:22px"></span></div>
  <div class="vstatus ${cls}"><span class="vdot"></span>${status}</div>`;
const vButtons = (paused) => `<div class="vbuttons"><span class="big ${paused ? 'resume' : 'pause'}">${paused ? I.micf : I.pause}</span></div>`;
const V = [
  phone('1 · Listening <small>· what is understood, as you speak</small>', `${vTop('Listening', 'listen')}
    <div class="vbody">
      <div class="vh">Hermes</div><div class="vtext">The backup ran at 02:00 and finished clean. Anything else on the server?</div>
      <div class="vh you">You</div><div class="vtext you">Yeah, how much space is left on the big drive and how does that compare to last<span class="caret"></span></div>
    </div>${vButtons(false)}`),
  phone('2 · Hermes speaking <small>· the reply, with markdown</small>', `${vTop('Hermes is speaking', 'speak')}
    <div class="vbody">
      <div class="vh you">You</div><div class="vtext you">Yeah, how much space is left on the big drive and how does that compare to last month?</div>
      <div class="vh">Hermes</div><div class="vtext"><p>About <b>700 GB</b> free on the big drive, which is 62% full. Last month it was 55%.</p>
        <table class="vt"><tr><th>Drive</th><th>Used</th><th>Free</th></tr><tr><td>space</td><td>62%</td><td>700 GB</td></tr><tr><td>flame</td><td>41%</td><td>1.1 TB</td></tr><tr><td>wolf</td><td>78%</td><td>390 GB</td></tr></table>
        <p>Most of the growth is Speakr's audio. Want me to set a reminder when it passes 75%?</p></div>
    </div>${vButtons(false)}`),
  phone('3 · Paused <small>· mic off, Hermes waits</small>', `${vTop('Paused', 'paused')}
    <div class="vbody dim2">
      <div class="vh you">You</div><div class="vtext you">Yeah, how much space is left on the big drive and how does that compare to last month?</div>
      <div class="vh">Hermes</div><div class="vtext"><p>About <b>700 GB</b> free on the big drive, which is 62% full. Last month it was 55%.</p><p>Most of the growth is Speakr's audio. Want me to set a reminder when it passes 75%?</p></div>
    </div>${vButtons(true)}`),
];
document.getElementById('study').innerHTML =
  block('Modes', '', 'Three ways to use Talaria. <b>Chat</b>: the text composer, with the mic in it for dictating a message. <b>Voice chat</b>: the composer\'s mic held, or the waveform button in the chat title bar, opens the voice screen below; Back returns to the text chat with the exchange kept. <b>Meeting recording</b>: the mic on the inbox, the recorder screen, sent to Speakr. Chat and voice chat share a session; a recording is its own inbox row.', V) +
  block('Inbox', '', 'One list for everything you did with Talaria: chats and recordings together, newest first, with the icon telling them apart (sparkles for a chat, red mic for a recording). Anything still going on, a running chat or a live recording, sits at the top under Active. The filter next to search narrows the list to chats or recordings. Every row pushes a page with a real back button; the chat title opens a menu for rename, skills, model and pin. The two buttons at the bottom start a chat or a recording.', C);
