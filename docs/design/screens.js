// The same four screens for every variant; the variant CSS decides how they look.
const I = {
  sidebar: '<svg class="icon" viewBox="0 0 24 24"><rect x="3" y="4" width="18" height="16" rx="3"/><path d="M9 4v16"/></svg>',
  sparkles: '<svg class="icon" viewBox="0 0 24 24"><path d="M12 3l1.8 5.2L19 10l-5.2 1.8L12 17l-1.8-5.2L5 10l5.2-1.8z"/><path d="M19 16l.7 2.3L22 19l-2.3.7L19 22l-.7-2.3L16 19l2.3-.7z"/></svg>',
  mic: '<svg class="icon" viewBox="0 0 24 24"><rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5 11a7 7 0 0 0 14 0M12 18v3M9 21h6"/></svg>',
  micf: '<svg class="icon fill" viewBox="0 0 24 24"><rect x="9" y="2" width="6" height="12" rx="3"/><path d="M6 11h2a4 4 0 0 0 8 0h2a6 6 0 0 1-5 5.9V20h3v2H8v-2h3v-3.1A6 6 0 0 1 6 11z"/></svg>',
  compose: '<svg class="icon" viewBox="0 0 24 24"><path d="M12 20h9"/><path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L8 18l-4 1 1-4z"/></svg>',
  gear: '<svg class="icon" viewBox="0 0 24 24"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"/></svg>',
  plus: '<svg class="icon" viewBox="0 0 24 24"><path d="M12 5v14M5 12h14"/></svg>',
  send: '<svg class="icon" viewBox="0 0 24 24"><path d="M12 19V5M5 12l7-7 7 7"/></svg>',
  play: '<svg class="icon fill" viewBox="0 0 24 24"><path d="M7 4l13 8-13 8z"/></svg>',
  pause: '<svg class="icon fill" viewBox="0 0 24 24"><rect x="6" y="4" width="4" height="16" rx="1"/><rect x="14" y="4" width="4" height="16" rx="1"/></svg>',
  check: '<svg class="icon" viewBox="0 0 24 24"><path d="M5 12l5 5L20 7"/></svg>',
  x: '<svg class="icon" viewBox="0 0 24 24"><path d="M6 6l12 12M18 6L6 18"/></svg>',
  link: '<svg class="icon" viewBox="0 0 24 24"><path d="M14 4h6v6M20 4l-9 9"/><path d="M19 14v5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V6a1 1 0 0 1 1-1h5"/></svg>',
  chev: '<svg class="icon" viewBox="0 0 24 24"><path d="M6 9l6 6 6-6"/></svg>',
  list: '<svg class="icon" viewBox="0 0 24 24"><path d="M8 6h13M8 12h13M8 18h13"/><circle cx="4" cy="6" r="1" fill="currentColor"/><circle cx="4" cy="12" r="1" fill="currentColor"/><circle cx="4" cy="18" r="1" fill="currentColor"/></svg>',
  term: '<svg class="icon" viewBox="0 0 24 24"><path d="M4 17l6-5-6-5M12 19h8"/></svg>',
  shield: '<svg class="icon" viewBox="0 0 24 24"><path d="M12 3l8 3v6c0 5-3.5 8-8 9-4.5-1-8-4-8-9V6z"/></svg>',
  cloud: '<svg class="icon" viewBox="0 0 24 24"><path d="M7 18a4 4 0 0 1-.6-8 6 6 0 0 1 11.4 1.5A3.5 3.5 0 0 1 17.5 18z"/><path d="M12 12v6M9.5 14.5L12 12l2.5 2.5"/></svg>',
  dot: '<svg class="icon fill" viewBox="0 0 24 24"><circle cx="12" cy="12" r="7"/></svg>',
  dashed: '<svg class="icon" viewBox="0 0 24 24" stroke-dasharray="3 3"><circle cx="12" cy="12" r="8"/></svg>',
  filter: '<svg class="icon" viewBox="0 0 24 24"><path d="M4 6h16M7 12h10M10 18h4"/></svg>',
  back15: '<svg class="icon" viewBox="0 0 24 24"><path d="M4 12a8 8 0 1 0 2.3-5.7"/><path d="M4 4v5h5"/><text x="12" y="15" font-size="7.5" text-anchor="middle" fill="currentColor" stroke="none" font-weight="700">15</text></svg>',
  fwd15: '<svg class="icon" viewBox="0 0 24 24"><path d="M20 12a8 8 0 1 1-2.3-5.7"/><path d="M20 4v5h-5"/><text x="12" y="15" font-size="7.5" text-anchor="middle" fill="currentColor" stroke="none" font-weight="700">15</text></svg>',
  trash: '<svg class="icon" viewBox="0 0 24 24"><path d="M4 7h16M10 11v6M14 11v6M6 7l1 13h10l1-13M9 7V4h6v3"/></svg>',
  more: '<svg class="icon fill" viewBox="0 0 24 24"><circle cx="5" cy="12" r="2"/><circle cx="12" cy="12" r="2"/><circle cx="19" cy="12" r="2"/></svg>',
  resend: '<svg class="icon" viewBox="0 0 24 24"><path d="M20 12a8 8 0 1 1-2.3-5.7"/><path d="M20 4v5h-5"/><path d="M9.5 12.5L12 15l4-4"/></svg>',
  wave: '<svg class="icon" viewBox="0 0 24 24"><path d="M4 10v4M8 6v12M12 9v6M16 4v16M20 10v4"/></svg>',
  keyboard: '<svg class="icon" viewBox="0 0 24 24"><rect x="3" y="6" width="18" height="12" rx="2"/><path d="M7 10h.01M11 10h.01M15 10h.01M7 14h10"/></svg>',
  morec: '<svg class="icon" viewBox="0 0 24 24"><circle cx="12" cy="12" r="9"/><circle cx="8" cy="12" r="1.2" fill="currentColor" stroke="none"/><circle cx="12" cy="12" r="1.2" fill="currentColor" stroke="none"/><circle cx="16" cy="12" r="1.2" fill="currentColor" stroke="none"/></svg>',
  sliders: '<svg class="icon" viewBox="0 0 24 24"><path d="M4 7h10M18 7h2M4 12h3M11 12h9M4 17h12M20 17h0"/><circle cx="16" cy="7" r="2"/><circle cx="9" cy="12" r="2"/><circle cx="18" cy="17" r="2"/></svg>',
  info: '<svg class="icon" viewBox="0 0 24 24"><circle cx="12" cy="12" r="9"/><path d="M12 11v5M12 8h.01"/></svg>',
  checkc: '<svg class="icon fill" viewBox="0 0 24 24"><path d="M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm-1.5 14.5L6 12l1.5-1.5 3 3 6-6L18 9z"/></svg>',
};
const phone = (name, inner, extra = '') => `<div class="frame"><h2>${name}</h2><div class="phone ${extra}"><div class="island"></div><div class="status"><span>9:41</span><span>●●●</span></div>${inner}<div class="home"></div></div></div>`;

const chat = phone('Chat', `
  <div class="nav">${I.sidebar}<div class="title">Home lab</div><div class="group">${I.wave}${I.sparkles}${I.compose}${I.gear}</div></div>
  <div class="messages">
    <div class="msg user"><div class="label">${I.mic} Voice</div><div class="bubble">What's eating the disk on the server?</div></div>
    <div class="msg assistant"><div class="bubble">
      <div class="tool">${I.term} Ran <code>df -h</code> and <code>du -sh /mnt/space/*</code></div>
      <p>Two things, and one of them is mine.</p>
      <ul><li><b>6.4 GB</b> in <code>services/hermes/pocket-tts</code>, left over from the benchmark.</li><li><b>443 MB</b> in <code>~/voice-bench</code>.</li></ul>
      <p>Both are safe to delete now that the service is managed by nix. Want me to remove them?</p>
    </div></div>
    <div class="msg user"><div class="bubble">Yes, both.</div></div>
    <div class="card approval"><div class="h">${I.shield} Hermes wants to run a command</div><div class="cmd">rm -rf /mnt/space/services/hermes/pocket-tts ~/voice-bench</div><div class="actions"><button class="deny">Deny</button><button class="once">Allow once</button><button class="always">Always</button></div></div>
  </div>
  <div class="composer"><div class="row"><span class="pill model"><i class="dot"></i>glm-5.3 · medium</span><span style="flex:1"></span><span class="pill sess">2 queued</span></div>
  <div class="row"><span class="round plus">${I.plus}</span><div class="field"><span>Message Hermes</span></div><span class="round sendb">${I.send}</span></div></div>`);

const rec = phone('Recording mode', `
  <div class="rec"><div class="bar">${I.list}${I.chev}</div>
    <div class="top"><div class="state"><span class="live">${I.micf}</span>Recording</div><div class="timer">12:34</div></div>
    <div class="note"></div>
    <div class="buttons"><div class="r"><span class="big pause">${I.pause}</span></div><div class="r"><span class="big cancel">${I.x}</span><span class="big done">${I.check}</span></div></div>
  </div>`);

const rows = [
  ['Wed, Sep 24 · 9:02 AM', '48:12 · 41 MB', 'Sent to Speakr as #3 · 2 hours ago', 'sent', true],
  ['Wed, Sep 24 · 7:40 AM', '00:12 · 151 KB', 'Recording now', 'live', false],
  ['Tue, Sep 23 · 10:57 PM', '01:03 · 742 KB', 'Sent to Speakr as #2 · yesterday', 'sent', false],
  ['Tue, Sep 23 · 9:39 PM', '00:24 · 287 KB', 'Not sent', 'none', false],
  ['Tue, Sep 23 · 9:33 PM', '00:26 · 299 KB', 'Not sent: Speakr returned HTTP 401', 'err', false],
];
const list = phone('Recordings', `
  <div class="nav"><span style="width:22px"></span><div class="title">Recordings</div><span class="done-btn">Done</span></div>
  <div class="list">${rows.map(([d, s, st, k, playing]) => `
    <div class="rowi k-${k}${playing ? ' playing' : ''}"><span class="round play">${playing ? I.pause : I.play}</span>
      <div class="meta"><div class="d">${d}</div><div class="s">${s}</div><div class="st">${st}</div>${playing ? `<div class="scrub"><span>18:04</span><div class="track"><i></i></div><span>48:12</span></div>` : ''}</div>
      <span class="stat">${k === 'sent' ? I.checkc : k === 'err' ? I.x : k === 'live' ? I.dot : I.dashed}</span>${k === 'sent' ? `<span class="lnk">${I.link}</span>` : k === 'none' || k === 'err' ? `<span class="lnk">${I.cloud}</span>` : ''}</div>`).join('')}
    <div class="foot">Recordings are deleted automatically after 30 days.</div></div>`);

const lock = phone('Lock Screen', `
  <div class="lock"><div class="time">9:41</div><div class="date">Wednesday, September 24</div>
    <div class="la"><span class="live">${I.micf}</span><div class="meta"><div class="h">Recording</div><div class="t">12:34</div></div><div class="acts"><span class="round cancel">${I.x}</span><span class="round pause">${I.pause}</span><span class="round done">${I.check}</span></div></div>
    <div class="widgets">
      <div class="widget"><div class="wh">${I.micf} Talaria</div><div class="center"><span class="mic">${I.micf}</span></div></div>
      <div class="widget"><div class="wh"><span class="live">${I.micf}</span> Recording<span class="t">12:34</span></div><div class="center"><div class="sm"><span class="round cancel">${I.x}</span><span class="round done">${I.check}</span></div><span class="round pause">${I.pause}</span></div></div>
    </div></div>`, 'locked');

// Rendering is done by frozen.js (variant pages) or nav.js (navigation page).
