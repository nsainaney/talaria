// The frozen screen set, rendered by each visual variant: inbox, text chat, voice chat,
// a recording expanded in place, the recorder, and the Lock Screen with widget + Live Activity.
const _sc = document.getElementById('screens');
if (_sc) _sc.innerHTML = C[0] + C[2] + V[1] + C[4] + C[5] + lock;
