(() => {
  const $ = id => document.getElementById(id);
  let state = {}, target = '', list = '', draft = {dpi:0, mode:'', threshold:0}, dirty = new Set();
  const parse = (raw, fallback) => { try { return JSON.parse(raw); } catch { return fallback; } };
  async function emit(name, values={}) {
    try { await window.nero.emit(name, values); }
    catch { $('notice').textContent = 'This control changed or is unavailable. Refresh and try again.'; $('notice').classList.add('notice'); }
  }
  const withTarget = extra => ({device: target, ...extra});
  function updateDraftControls() {
    $('dpi').value = draft.dpi;
    $('ratchet').setAttribute('aria-pressed', draft.mode === 'ratchet');
    $('free').setAttribute('aria-pressed', draft.mode === 'free');
    $('threshold').value = draft.threshold || 1;
    $('threshold-value').textContent = draft.threshold === 255 ? 'Always tactile' : draft.threshold ? String(draft.threshold) : 'Unavailable';
    for (const b of $('presets').children) b.classList.toggle('chosen', Number(b.dataset.value) === draft.dpi);
  }
  function render(s) {
    state = s;
    if (!s.kind) return;
    const mouse = s.kind === 'mouse';
    $('mouse').hidden = !mouse; $('keyboard').hidden = mouse;
    $('category').textContent = mouse ? 'MOUSE' : 'KEYBOARD';
    if (target !== s.device) { target = s.device; dirty.clear(); list = ''; }
    const deviceList = s.devices + target;
    if ($('device').dataset.list !== deviceList) {
      $('device').replaceChildren();
      const devices = parse(s.devices, []);
      if (!devices.some(d => d.id === target)) {
        const option = new Option(target ? 'Saved device unavailable' : `Choose a ${s.kind}…`, target); $('device').add(option);
      }
      devices.forEach(d => $('device').add(new Option(d.name + (d.online === 'true' ? '' : ' · offline'), d.id)));
      $('device').value = target; $('device').dataset.list = deviceList;
    }
    $('device').disabled = s.busy;
    $('connection').textContent = s.ready ? 'Connected' : 'Unavailable';
    $('connection').classList.toggle('offline', !s.ready);
    $('refresh').disabled = s.busy;
    const art = $(mouse ? 'mouse-art' : 'keyboard-art');
    art.src = s.art === 'generic' ? `generic-${s.kind}.svg` : `${s.kind}.svg`;
    art.classList.toggle('unavailable-art', !s.ready);
    art.alt = s.art === 'generic' ? `Generic ${s.kind} illustration` : mouse ? 'Original MX Master 3S illustration with sculpted thumb rest and metal scroll wheels' : 'Original full-size MX Keys S for Mac illustration with Mac modifiers, navigation cluster and number pad';
    $('mouse-battery').textContent = $('keyboard-battery').textContent = s.battery;
    $('mouse-power').textContent = s.ready ? s.power : 'Last known battery';
    $('keyboard-power').textContent = s.ready ? s.power : 'Unavailable';
    $('battery-label').textContent = s.ready ? 'BATTERY' : 'LAST KNOWN';
    if (mouse) {
      const allowed = parse(s.dpi_values, []);
      if (list !== s.dpi_values) {
        $('dpi').replaceChildren(); allowed.forEach(value => $('dpi').add(new Option(value.toLocaleString(),value)));
        if (!allowed.length) $('dpi').add(new Option('—',0));
        $('presets').replaceChildren();
        [800,1200,1600,2000,3200].filter(v => allowed.includes(v)).forEach(value => {
          const button = document.createElement('button'); button.textContent = value.toLocaleString(); button.dataset.value = value;
          button.onclick = () => { draft.dpi=value;dirty.add('dpi');updateDraftControls(); };
          $('presets').append(button);
        }); list = s.dpi_values;
      }
      for (const key of ['dpi','mode','threshold']) {
        if (dirty.has(key) && draft[key] === s[key]) dirty.delete(key);
        if (!dirty.has(key)) draft[key] = s[key];
      }
      $('dpi-current').textContent = s.dpi ? `Current · ${s.dpi.toLocaleString()}` : 'Unavailable';
      $('wheel-current').textContent = s.mode === 'free' ? 'Free spin' : s.mode === 'ratchet' ? 'Tactile' : 'Unavailable';
      const dpiOff = !s.ready || !allowed.length;
      $('dpi').disabled = dpiOff;
      for (const b of $('presets').children) b.disabled = dpiOff;
      $('apply-dpi').disabled = dpiOff || s.busy || !allowed.includes(Number(draft.dpi));
      const wheelOff = !s.ready || !['free','ratchet'].includes(s.mode);
      ['ratchet','free','threshold'].forEach(id => $(id).disabled = wheelOff);
      ['apply-wheel','apply-threshold'].forEach(id => $(id).disabled = wheelOff || s.busy);
      updateDraftControls();
    }
    $('host-watch-card').hidden=mouse;
    $('host-watch').textContent=s.host_switch_enabled?'Stop Easy-Switch watch':'Watch Easy-Switch';
    $('host-watch').disabled=s.busy||(!s.host_switch_enabled&&(!s.host_switch_supported||!s.events_ready));
    $('host-watch-status').textContent=s.host_switch_supported?s.host_switch_status:'OpenLogi needs its new host-switch event API';
    $('watch-keyboard').textContent = s.events_enabled ? 'Stop watching' : 'Watch changes';
    $('watch-keyboard').setAttribute('aria-pressed', s.events_enabled ? 'true' : 'false');
    $('watch-keyboard').disabled = s.busy || (!s.events_enabled && !s.events_ready);
    if (document.activeElement !== $('low-battery')) $('low-battery').value = s.low_battery || 20;
    $('low-battery').disabled = s.busy;
    $('last-event').textContent = s.events_enabled ? s.last_event : 'Off · no typing or key capture';
    $('last-event').title = $('last-event').textContent;
    $('notice').textContent = s.notice || (!s.ready ? s.status : mouse ? 'Temporary settings · saved profiles stay in OpenLogi' : 'Live device status · connected through OpenLogi');
    $('notice').title = $('notice').textContent;
    $('notice').classList.toggle('notice', !!s.notice);
    $('verified').textContent = s.busy ? 'Refreshing…' : s.ready ? `Read ${s.last_read}` : '';
  }
  $('device').onchange = e => emit('select',{device:e.target.value});
  $('refresh').onclick = () => emit('refresh'); $('settings').onclick = () => emit('settings');
  $('mouse-mappings').onclick = $('keyboard-mappings').onclick = () => emit('mappings');
  $('dpi').onchange = e => { draft.dpi = Number(e.target.value);dirty.add('dpi');updateDraftControls(); };
  $('ratchet').onclick = () => { draft.mode='ratchet';dirty.add('mode');updateDraftControls(); };
  $('free').onclick = () => { draft.mode='free';dirty.add('mode');updateDraftControls(); };
  $('threshold').oninput = e => { draft.threshold=Number(e.target.value);dirty.add('threshold');updateDraftControls(); };
  $('apply-dpi').onclick = () => emit('dpi',withTarget({value:Number(draft.dpi)}));
  $('apply-wheel').onclick = () => emit('wheel',withTarget({mode:draft.mode}));
  $('apply-threshold').onclick = () => emit('threshold',withTarget({value:Number(draft.threshold)}));
  $('host-watch').onclick=()=>emit('host_watch',withTarget({enabled:!state.host_switch_enabled}));
  $('watch-keyboard').onclick = () => emit('keyboard_watch',withTarget({enabled:!state.events_enabled,threshold:Number($('low-battery').value)}));
  $('low-battery').onchange = () => emit('keyboard_watch',withTarget({enabled:!!state.events_enabled,threshold:Number($('low-battery').value)}));
  window.nero?.onState(render);
})();
