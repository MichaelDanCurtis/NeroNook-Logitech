#!/usr/bin/env python3
"""Owned signed module + fake API; no live host, HID or monitor commands."""
import json, pathlib, queue, subprocess, tempfile, threading, time, uuid, shutil, sys, os, signal
shutdown_case=sys.argv[1] if len(sys.argv)>1 else None
assert shutdown_case in [None,"sigterm","eof"]
root=pathlib.Path(__file__).resolve().parents[1]
fixture_id=str(uuid.uuid4()); fixture=pathlib.Path(tempfile.gettempdir())/('nn-logi-fixture-'+fixture_id)
fixture.mkdir(mode=0o700); app=fixture/'OpenLogi.app'; exe=app/'Contents/MacOS/openlogi'; exe.parent.mkdir(parents=True)
exe.write_text('''#!/usr/bin/env python3
import json,pathlib,sys,time
p=pathlib.Path(__file__).resolve().parents[3]; args=sys.argv[1:]
with (p/'calls.jsonl').open('a') as f:f.write(json.dumps(args)+'\\n')
def emit(data):print(json.dumps(dict(schema_version=1,ok=True,data=data)),flush=True)
if args==['--help']:print('  api  Machine-readable commands');raise SystemExit
if args==['api','--help']:print('host-switch-events watch-host-switch');raise SystemExit
if args==['api','devices']:
 emit(dict(inventory='ready',devices=[dict(id='fixture-keyboard',name='Synthetic keyboard',kind='keyboard',online=True,battery=dict(percentage=70),capabilities=dict(pointer=False,buttons=True))]));raise SystemExit
if args==['api','--save','host-switch-events','--device','fixture-keyboard','--set','off']:
 emit(dict(device='fixture-keyboard',host_switch_events=False,persistence='saved'));raise SystemExit
if args==['api','watch-host-switch','--device','fixture-keyboard']:
 (p/'stream-pid').write_text(str(__import__('os').getpid()))
 emit(dict(type='baseline',device='fixture-keyboard'))
 end=time.monotonic()+20
 while not (p/'ready-for-choice').exists() and time.monotonic()<end:time.sleep(.01)
 def choice(seq,channel,device='fixture-keyboard',age=0):
  emit(dict(type='host_switch',device=device,sequence=seq,channel=channel,observed_at_ms=int((time.time()-age)*1000)))
 choice(1,2);choice(1,2);choice(2,3,age=10)
 while not (p/'disabled').exists() and time.monotonic()<end:time.sleep(.01)
 choice(3,1);raise SystemExit
raise SystemExit(2)
''');exe.chmod(0o700)
(fixture/'settings.json').write_text(json.dumps(dict(application=str(app),mouse='',keyboard='fixture-keyboard',device='fixture-keyboard',tab='keyboard',hostSwitchEvents=True)))
p=subprocess.Popen([str(root/'build/Logitech Module.app/Contents/MacOS/LogitechPlugin'),'--neronook-plugin','--protocol-fixture',fixture_id],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,text=True)
messages=queue.Queue();threading.Thread(target=lambda:[messages.put(json.loads(x)) for x in p.stdout],daemon=True).start()
session=str(uuid.uuid4()); plugin='cafe.nero.plugin.logitech'
def send(kind,**values):p.stdin.write(json.dumps(dict(apiVersion=1,type=kind,pluginID=plugin,session=session,sequence=0,**values))+'\n');p.stdin.flush()
try:
 send('hello',features=['actions-v1','dashboard-v1','panels-v1','custom-views-v1'])
 events=[];revision=None;disabled=False;finished=False;registered=False;deadline=time.monotonic()+25
 while time.monotonic()<deadline:
  m=messages.get(timeout=max(.1,deadline-time.monotonic()));assert m['session'].lower()==session
  for panel in m.get('snapshot',{}).get('panels',[]):
   if panel['id']=='keyboard':
    revision=panel['customView']['revision']
    if shutdown_case is None and not disabled and panel['customView']['state']['host_switch_supported']:(fixture/'ready-for-choice').touch()
    if disabled and not panel['customView']['state']['host_switch_enabled']:
     (fixture/'disabled').touch();finished=True
  bus=m.get('bus',{})
  if shutdown_case and bus.get('operation')=='publish' and bus.get('address',{}).get('name')=='host_switch_status' and bus['values']['watching']:
   if shutdown_case=='sigterm':p.terminate()
   else:p.stdin.close()
   p.wait(timeout=3);finished=True;break
  if bus.get('operation')=='register':
   channels={c['id']:c for c in bus['registration']['channels']};assert channels['host_switch_choices']['kind']=='event' and channels['host_switch_status']['kind']=='state';registered=True
  if bus.get('operation')=='publish' and bus.get('address',{}).get('name')=='host_switch_choices':
   assert not disabled,'Choice after local stop';v=bus['values'];assert v['device']=='fixture-keyboard' and v['channel']==2 and v['event_id'].lower()==bus['requestID'].lower();events.append(v)
   assert len(events)==1,'Initial/repeated/stale choice replayed'
   send('viewEvent',viewEvent=dict(panelID='keyboard',name='host_watch',revision=revision,values=dict(device='fixture-keyboard',enabled=False)));disabled=True
  if finished and bus.get('operation')=='publish' and bus.get('address',{}).get('name')=='host_switch_status' and bus['values']['watching'] is False:break
 if shutdown_case:
  assert finished and registered and not events
 else:
  assert finished and disabled and registered and len(events)==1
  assert json.loads((fixture/'settings.json').read_text())['hostSwitchEvents'] is False
 pid=int((fixture/'stream-pid').read_text())
 # Stop owns this exact stream; once disabled it must exit rather than remain
 # a hidden hardware observer. Process polling does not synthesize key input.
 for _ in range(20):
  if subprocess.run(['ps','-p',str(pid)],stdout=subprocess.DEVNULL).returncode:break
  time.sleep(.05)
 else:raise AssertionError('Owned stream survived stop')
 allowed=[['--help'],['api','--help'],['api','devices'],['api','watch-host-switch','--device','fixture-keyboard'],['api','--save','host-switch-events','--device','fixture-keyboard','--set','off']]
 assert all(json.loads(x) in allowed for x in (fixture/'calls.jsonl').read_text().splitlines())
 if shutdown_case:print('PASS: '+shutdown_case+' terminates the owned reader without choices or changing the saved watch.')
 else:print('PASS: signed module uses exact agent-only stream, quiet baseline, one fresh choice with matching UUID, rejects duplicate/stale choices, stops its child and persists disable; no HID or monitor operation.')
finally:
 if not p.stdin.closed:p.stdin.close()
 try:p.wait(timeout=3)
 except subprocess.TimeoutExpired:p.terminate();p.wait(timeout=3)
 if (fixture/'stream-pid').exists():
  try:os.kill(int((fixture/'stream-pid').read_text()),signal.SIGTERM)
  except ProcessLookupError:pass
 shutil.rmtree(fixture)
