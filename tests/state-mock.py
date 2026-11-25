import os, pathlib, subprocess, tempfile, hashlib, pty, select, time
src=pathlib.Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory() as t:
    p=pathlib.Path(t); (p/'compose.yaml').touch(); mock=p/'docker'; calls=p/'calls'; anchor=p/'anchor'; anchor.write_text('test anchor\n')
    mock.write_text('''#!/bin/sh
printf '%s\\n' "$*" >> "$CALLS"
case "$1 $2" in
 'compose -f') case "$4" in ps) [ "$5" != -a ] || [ "$6" != -q ] || echo abc123;; config|down) :;; esac;;
 'inspect --format') case "$3" in *State.Status*) echo "${STATUS:-exited}";; *Mounts*) echo test_state;; *Image*) echo sha256:abc;; esac;;
 'volume inspect') :;;
 'ps -q') :;;
 'run --rm') case "$*" in *target=/state,readonly*) cat "$ANCHOR";; *) cat > "$ANCHOR";; esac;;
 *) exit 2;;
esac
'''); mock.chmod(0o755)
    env=dict(os.environ,PATH=str(p)+':'+os.environ['PATH'],CALLS=str(calls),ANCHOR=str(anchor),BACKUP_DIR=str(p/'backups'))
    def run(op,**kwargs): return subprocess.run([str(src/'scripts/state.sh'),op],cwd=p,env=dict(env,**kwargs),stdin=subprocess.DEVNULL,capture_output=True,text=True)
    r=run('backup',STATUS='running'); assert r.returncode and 'stop the resolver' in r.stderr
    r=run('backup'); assert r.returncode==0,r.stderr
    sets=list((p/'backups').iterdir()); assert len(sets)==1
    b=sets[0]; assert (b/'root.key').read_bytes()==anchor.read_bytes(); assert (b/'root.key.sha512').read_text().strip()==hashlib.sha512(anchor.read_bytes()).hexdigest()
    r=run('purge'); assert r.returncode and 'interactive terminal' in r.stderr; assert 'down --volumes' not in calls.read_text()
    r=run('restore',BACKUP_SET=str(b)); assert r.returncode and 'interactive terminal' in r.stderr
    (b/'root.key').write_text('corrupt'); r=run('restore',BACKUP_SET=str(b)); assert r.returncode and 'checksum mismatch' in r.stderr
    (b/'root.key').write_text('test anchor\n'); anchor.write_text('other state\n')
    def interactive(op,word,**kwargs):
        master,slave=pty.openpty(); proc=subprocess.Popen([str(src/'scripts/state.sh'),op],cwd=p,env=dict(env,**kwargs),stdin=slave,stdout=slave,stderr=slave); os.close(slave); out=b''; end=time.monotonic()+5
        while b'to continue:' not in out and time.monotonic()<end:
            if select.select([master],[],[],.2)[0]: out+=os.read(master,4096)
        assert b'to continue:' in out,out
        os.write(master,(word+'\n').encode()); code=proc.wait(timeout=5); os.close(master); return code
    assert interactive('restore','RESTORE',BACKUP_SET=str(b))==0; assert anchor.read_text()=='test anchor\n'
    assert interactive('purge','NO')!=0; assert 'down --volumes' not in calls.read_text()
    assert interactive('purge','PURGE')==0; assert 'down --volumes' in calls.read_text()
    assert not (p/'.state-ops.lock').exists()
    print('PASS mocked state operations: backup, SHA-512, running refusal, corrupt restore refusal, noninteractive refusal, confirmation and restore')
