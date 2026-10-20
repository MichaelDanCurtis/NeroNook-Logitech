#!/usr/bin/env python3
"""Signed module, isolated preferences and fake read-only CLI; no live host/HID."""
import json, pathlib, queue, subprocess, tempfile, threading, time, uuid, shutil

root = pathlib.Path(__file__).resolve().parents[1]
fixture_id = str(uuid.uuid4())
fixture = pathlib.Path(tempfile.gettempdir()) / ('nn-logi-fixture-' + fixture_id)
fixture.mkdir(mode=0o700)
app = fixture / 'OpenLogi.app'
binary = app / 'Contents/MacOS/openlogi'
binary.parent.mkdir(parents=True)
binary.write_text('''#!/usr/bin/env python3
import json,pathlib,sys
p=pathlib.Path(__file__).resolve().parents[3]
with (p/'calls.jsonl').open('a') as f:f.write(json.dumps(sys.argv[1:])+'\\n')
if sys.argv[1:]==['--help']:print('Commands: control Legacy fixture');raise SystemExit(0)
if sys.argv[1:]!=['control','devices']:raise SystemExit(2)
n=int((p/'counter').read_text()) if (p/'counter').exists() else 0
(p/'counter').write_text(str(n+1))
battery=[70,19,19,80,80,80,80,5][min(n,7)]
print(json.dumps(dict(schema_version=1,protocol_version=32,agent_version='fixture',inventory_health='Unavailable' if n==5 else 'Ready',devices=[dict(id='fixture-keyboard',name='Synthetic keyboard',online=n!=4,battery=dict(percentage=battery),capabilities=dict(pointer=False,buttons=True))])))
''')
binary.chmod(0o700)
settings = dict(application=str(app), mouse='', keyboard='fixture-keyboard', device='fixture-keyboard', tab='keyboard', keyboardEvents=True, keyboardLowBattery=20)
(fixture/'settings.json').write_text(json.dumps(settings))
p = subprocess.Popen([str(root/'build/Logitech Module.app/Contents/MacOS/LogitechPlugin'), '--neronook-plugin', '--protocol-fixture', fixture_id], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
messages = queue.Queue()
threading.Thread(target=lambda: [messages.put(json.loads(x)) for x in p.stdout], daemon=True).start()
session = str(uuid.uuid4()); plugin = 'cafe.nero.plugin.logitech'
def send(kind, **values):
    p.stdin.write(json.dumps(dict(apiVersion=1, type=kind, pluginID=plugin, session=session, sequence=0, **values))+'\n');p.stdin.flush()
try:
    send('hello', features=['actions-v1', 'dashboard-v1', 'panels-v1', 'custom-views-v1'])
    events=[]; channel=None; revision=None; deadline=time.monotonic()+55; disabled=False; finished=False
    while time.monotonic()<deadline:
        message=messages.get(timeout=max(.1, deadline-time.monotonic()))
        assert message['session'].lower()==session and message['pluginID']==plugin
        bus=message.get('bus', {})
        for panel in message.get('snapshot',{}).get('panels',[]):
            if panel['id']=='keyboard': revision=panel['customView']['revision']
        if bus.get('operation')=='register':
            channel=next(c for c in bus['registration']['channels'] if c['id']=='keyboard_events')
            assert channel['kind']=='event'
        if bus.get('operation')=='publish' and bus.get('address',{}).get('name')=='keyboard_events':
            value=bus['values'];assert value['event_id'].lower()==bus['requestID'].lower()
            assert value['device']=='fixture-keyboard' and value['observed_at']>0
            assert not disabled,'Event emitted after watch disabled'
            events.append(value)
        count=int((fixture/'counter').read_text()) if (fixture/'counter').exists() else 0
        if count>=7 and not disabled and message.get('snapshot',{}).get('badge')=='Connected':
            assert [x['kind'] for x in events]==['low_battery','battery_recovered','disconnected']
            assert len({x['event_id'] for x in events})==3
            send('viewEvent',viewEvent=dict(panelID='keyboard',name='keyboard_watch',revision=revision,values=dict(device='fixture-keyboard',enabled=False,threshold=20)))
            # Before changing the local watch, the host validates its custom-view
            # schema revision. No module action or hardware setting is requested.
            disabled=True
        if disabled and count>=8:
            panels=message.get('snapshot',{}).get('panels',[])
            keyboard=next((x for x in panels if x['id']=='keyboard'),None)
            if keyboard and keyboard['customView']['state']['events_enabled'] is False:
                finished=True;break
    assert finished,'Watch disable or fixture deadline failed'
    assert channel and [x['kind'] for x in events]==['low_battery','battery_recovered','disconnected']
    assert json.loads((fixture/'settings.json').read_text())['keyboardEvents'] is False
    assert all(json.loads(x) in [['control','devices'],['--help']] for x in (fixture/'calls.jsonl').read_text().splitlines())
    print('PASS: isolated signed module emits each fresh transition once, suppresses initial/repeated/outage recovery state, preserves event UUIDs, disables/persists watch, and invokes only read-only fixture inventory.')
finally:
    p.stdin.close()
    try:p.wait(timeout=3)
    except subprocess.TimeoutExpired:p.terminate();p.wait(timeout=3)
    shutil.rmtree(fixture)
