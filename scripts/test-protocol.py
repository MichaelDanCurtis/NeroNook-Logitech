#!/usr/bin/env python3
"""Read-only live handshake check; invalid writes are rejected before execution."""
import json, subprocess, pathlib, selectors, time, uuid
root=pathlib.Path(__file__).resolve().parents[1]
p=subprocess.Popen([str(root/'build/Logitech Module.app/Contents/MacOS/LogitechPlugin'),'--neronook-plugin'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,bufsize=1)
session=str(uuid.uuid4()); plugin='cafe.nero.plugin.logitech'
def send(kind,**kwargs):
 p.stdin.write(json.dumps(dict(apiVersion=1,type=kind,pluginID=plugin,session=session,sequence=0,**kwargs))+'\n');p.stdin.flush()
def wait_for(predicate):
 selector=selectors.DefaultSelector();selector.register(p.stdout,selectors.EVENT_READ)
 end=time.monotonic()+20
 try:
  while time.monotonic()<end:
   if selector.select(1):
    line=p.stdout.readline()
    if not line: raise AssertionError('module exited unexpectedly')
    message=json.loads(line)
    assert message['pluginID']==plugin and message['session'].lower()==session.lower()
    if predicate(message): return message
  raise AssertionError('module response deadline')
 finally: selector.close()
try:
 send('hello',features=['actions-v1','panels-v1','dashboard-v1','custom-views-v1'])
 ready=wait_for(lambda m:m['type']=='ready');assert 'actions-v1' in ready['features']
 snap=wait_for(lambda m:m['type']=='snapshot')['snapshot']
 assert [(p['id'],p['title']) for p in snap['panels']]==[('mouse','Mouse'),('keyboard','Keyboard')]
 assert all(p['customView']['entry']=='devices/index.html' for p in snap['panels'])
 assert all(p['customView']['state']['kind']==p['id'] for p in snap['panels'])
 assert all(len(json.dumps(p['customView']['state']).encode())<32768 for p in snap['panels'])
 assert len(snap['activity'])<=100
 request=str(uuid.uuid4())
 send('bus',bus=dict(operation='execute',requestID=request,address=dict(plugin=plugin,name='set_dpi'),values=dict(device='invalid',dpi=-1)))
 result=wait_for(lambda m:m['type']=='bus' and m.get('bus',{}).get('requestID','').lower()==request.lower())
 assert result['bus']['update']['phase']=='failed'
 print('PASS: handshake, separate custom device views, bounded state, status line, invalid action rejected without a write.')
finally:
 p.stdin.close()
 try:p.wait(timeout=3)
 except subprocess.TimeoutExpired:p.terminate();p.wait(timeout=3)
