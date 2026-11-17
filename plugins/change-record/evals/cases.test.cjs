// Sanity checks on the eval cases, without running an agent: every case has the three parts,
// every grader has a known type, file-targeted graders name the record id the prompt gives,
// and the shared scaffold builds a repository with the plugin's docs/changes/ in it.
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const os=require('node:os');
const {spawnSync}=require('node:child_process');
const root=__dirname;
const cases=fs.readdirSync(root).filter(d=>fs.existsSync(path.join(root,d,'case.yaml')));
const KNOWN=new Set(['tool_used','regex','llm','tool_order','file_exists']);
test('there are cases',()=>assert.ok(cases.length>=8,cases.join(',')));
for(const c of cases) test(`${c} is well formed`,()=>{
  const dir=path.join(root,c);
  const yaml=fs.readFileSync(path.join(dir,'case.yaml'),'utf8');
  assert.match(yaml,new RegExp(`^name: ${c}$`,'m'));
  assert.match(yaml,/scaffold_script: scaffold.sh/);
  const prompt=fs.readFileSync(path.join(dir,'prompt.md'),'utf8');
  assert.ok(prompt.trim().length>20);
  const graders=fs.readdirSync(path.join(dir,'graders'));
  assert.ok(graders.includes('skill-fired.md'),'activation indicator present');
  const idInPrompt=(prompt.match(/`(2026-11-08-[a-z-]+)`/)||[])[1];
  for(const g of graders){
    const text=fs.readFileSync(path.join(dir,'graders',g),'utf8');
    const type=(text.match(/^type: (\w+)/m)||[])[1];
    assert.ok(KNOWN.has(type),`${c}/${g}: unknown grader type ${type}`);
    const filePath=(text.match(/path: (docs\/changes\/[^\s]+)/)||[])[1];
    if(filePath) assert.ok(idInPrompt && filePath.includes(idInPrompt),`${c}/${g}: targets ${filePath} but the prompt names ${idInPrompt}`);
    if(type==='llm') assert.ok(/PASS if/.test(text),`${c}/${g}: llm criteria state PASS`);
  }
});
test('the shared scaffold builds a committed repository with docs/changes/ from the templates',()=>{
  const scratch=fs.mkdtempSync(path.join(os.tmpdir(),'cr-eval-'));
  try{
    const r=spawnSync('bash',[path.join(root,'record-before-code','scaffold.sh')],{cwd:scratch,encoding:'utf8'});
    assert.equal(r.status,0,r.stderr);
    for(const f of ['greet.py','tests/test_greet.py','README.md','docs/changes/README.md','docs/changes/TEMPLATE.md']) assert.ok(fs.existsSync(path.join(scratch,f)),f);
    assert.equal(fs.readFileSync(path.join(scratch,'docs/changes/TEMPLATE.md'),'utf8'),fs.readFileSync(path.join(root,'..','templates/docs-changes/TEMPLATE.md'),'utf8'));
    const log=spawnSync('git',['-C',scratch,'log','--oneline'],{encoding:'utf8'}).stdout;
    assert.match(log,/greet: initial/);
    const t=spawnSync('python3',['-m','unittest','discover','-s','tests','-t','.'],{cwd:scratch,encoding:'utf8'});
    assert.equal(t.status,0,t.stderr);
  } finally { fs.rmSync(scratch,{recursive:true,force:true}); }
});
// A machine may sign every commit (commit.gpgsign), and the suites make thousands; a signing
// service that ran out of file handles once failed every test that commits (record
// 2026-11-17-unsigned-scratch-commits). So no scaffold signs: here the global configuration
// asks for signing with a program that records each call and fails.
test('no scaffold signs a commit or a tag, whatever the global configuration asks',()=>{
  const tmp=fs.mkdtempSync(path.join(os.tmpdir(),'cr-sign-'));
  try{
    const calls=path.join(tmp,'calls'), signer=path.join(tmp,'signer'), config=path.join(tmp,'gitconfig');
    fs.writeFileSync(signer,`#!/bin/sh\necho "$*" >> '${calls}'\nexit 1\n`,{mode:0o755});
    fs.writeFileSync(config,['[user]','\tname = Signer','\temail = signer@example.com','\tsigningkey = /no/such/key.pub',
      '[commit]','\tgpgsign = true','[tag]','\tgpgsign = true',`[gpg]`,`\tprogram = ${signer}`,`[gpg "ssh"]`,`\tprogram = ${signer}`,''].join('\n'));
    const env={...process.env,GIT_CONFIG_GLOBAL:config};
    const plugin=path.join(root,'..');
    const scaffolds=[
      ...cases.map(c=>[c,path.join(root,c,'scaffold.sh'),[]]),
      ...fs.readdirSync(path.join(plugin,'outcome-evals/tasks')).filter(t=>fs.existsSync(path.join(plugin,'outcome-evals/tasks',t,'scaffold.sh')))
        .map(t=>[`outcome task ${t}`,path.join(plugin,'outcome-evals/tasks',t,'scaffold.sh'),[]]),
      ['ci/scratch.sh',path.join(plugin,'ci/scratch.sh'),['repo']],
    ];
    assert.ok(scaffolds.length>=14,scaffolds.map(s=>s[0]).join(','));
    for(const [name,script,args] of scaffolds){
      const scratch=fs.mkdtempSync(path.join(tmp,'s-'));
      const r=spawnSync('bash',[script,...args],{cwd:scratch,env,encoding:'utf8'});
      assert.equal(r.status,0,`${name}: ${r.stderr}`);
      const repo=args.length?path.join(scratch,args[0]):scratch;
      const n=spawnSync('git',['-C',repo,'rev-list','--count','--all'],{env,encoding:'utf8'});
      assert.ok(Number(n.stdout)>=1,`${name}: no commit was made (${n.stderr})`);
    }
    assert.equal(fs.existsSync(calls)?fs.readFileSync(calls,'utf8'):'','','the signing program was called');
  } finally { fs.rmSync(tmp,{recursive:true,force:true}); }
});

// The regex graders, run against fixtures in the trace's own encoding (one JSON object per
// tool call, as trace.jsonl holds them), so a grader that recognises a record only when the
// Write tool wrote it, or a tier line only in one markdown style, fails here before it misreads
// a run.
const grader=(c,g)=>{
  const text=fs.readFileSync(path.join(root,c,'graders',g),'utf8');
  const pattern=(text.match(/^pattern: '([\s\S]*?)'\s*$/m)||[])[1];
  const flags=(text.match(/^flags: (\w+)/m)||[])[1]||'';
  const match=(text.match(/^match: (\S+)/m)||[])[1];
  assert.ok(pattern,`${c}/${g} has a pattern`);
  return {re:new RegExp(pattern,flags),match,target:(text.match(/^target: (\w+)/m)||[])[1]};
};
const call=(name,input,id='toolu_01')=>JSON.stringify({type:'assistant',message:{content:[{type:'tool_use',id,name,input}]}})+'\n';
const cwd='/tmp/claude-eval-x/home/cwd/';
const record=id=>`---\nid: ${id}\ntier: 1\nstatus: open\n---\n# Title\n\n## Goal\n"quoted" words\n`;
const writeRecord=id=>call('Write',{file_path:`${cwd}docs/changes/${id}.md`,content:record(id)});
const heredocRecord=id=>call('Bash',{command:`git checkout -q -b x && cat > docs/changes/${id}.md <<'EOF'\n${record(id)}EOF\ngit add docs/changes`});
const cpRecord=id=>call('Bash',{command:`cp docs/changes/TEMPLATE.md docs/changes/${id}.md`});
const readRecord=id=>call('Bash',{command:`cat docs/changes/README.md docs/changes/TEMPLATE.md; ls docs/changes/${id}.md`})+call('Read',{file_path:`${cwd}docs/changes/${id}.md`});
const writeGreet=call('Write',{file_path:`${cwd}greet.py`,content:'import sys\nprint("hi")\n'});
const heredocGreet=call('Bash',{command:`cat > greet.py <<'EOF'\nimport sys\nprint("hi")\nEOF`});
const readGreet=call('Bash',{command:'cat greet.py && cat > tests/test_greet.py <<\'EOF\'\nimport unittest\nEOF'});
const probe=call('Bash',{command:'python3 -c "import fileinput; print(fileinput.input)"'});
test('record-before-code sees a record written by Write or by a shell heredoc, in either order',()=>{
  const {re}=grader('record-before-code','record-before-code.md');
  assert.ok(re.test(writeRecord('2026-11-08-shout')+writeGreet),'Write then code');
  assert.ok(re.test(heredocRecord('2026-11-08-shout')+heredocGreet),'heredoc then code');
  assert.ok(!re.test(writeGreet+writeRecord('2026-11-08-shout')),'code then Write');
  assert.ok(!re.test(heredocGreet+heredocRecord('2026-11-08-shout')),'code then heredoc');
  assert.ok(re.test(readGreet+heredocRecord('2026-11-08-shout')+heredocGreet),'reading greet.py and writing its test first is not code');
});
test('probed-before-record fails a probe that comes after a record written by heredoc',()=>{
  const {re}=grader('probed-facts-labelled','probed-before-record.md');
  assert.ok(re.test(probe+writeRecord('2026-11-08-names-file')),'probe then Write');
  assert.ok(re.test(probe+heredocRecord('2026-11-08-names-file')),'probe then heredoc');
  assert.ok(!re.test(writeRecord('2026-11-08-names-file')+probe),'Write then probe');
  assert.ok(!re.test(heredocRecord('2026-11-08-names-file')+probe),'heredoc then probe');
  assert.ok(!re.test(cpRecord('2026-11-08-names-file')+probe),'cp of the template then probe');
  assert.ok(re.test(readRecord('2026-11-08-names-file')+probe+writeRecord('2026-11-08-names-file')),'reading docs/changes first is not writing the record');
});
test('declares-tier-0 reads the common markdown styles of the line',()=>{
  const {re}=grader('tier-0-no-record','declares-tier-0.md');
  for(const s of ['Tier: 0','**Tier: 0**','**Tier**: 0','**Tier:** 0','Tier:0','- Tier: 0 (no behaviour change)']) assert.ok(re.test(s),s);
  for(const s of ['Tier: 1','Tier: 10','tier: 0']) assert.ok(!re.test(s),`not ${s}`);
});
test('no-record-written and no-code-written see a file made by shell, and not one only read',()=>{
  const r=grader('tier-0-no-record','no-record-written.md');
  assert.equal(r.match,'not_contains'); assert.equal(r.target,'trace');
  assert.ok(r.re.test(writeRecord('2026-11-08-typo')),'Write');
  assert.ok(r.re.test(heredocRecord('2026-11-08-typo')),'heredoc');
  assert.ok(r.re.test(cpRecord('2026-11-08-typo')),'cp of the template');
  assert.ok(!r.re.test(readRecord('2026-11-08-typo')+writeGreet),'reading docs/changes and writing code');
  const g=grader('tier-2-stops-before-code','no-code-written.md');
  assert.equal(g.match,'not_contains'); assert.equal(g.target,'trace');
  assert.ok(g.re.test(writeGreet),'Write');
  assert.ok(g.re.test(heredocGreet),'heredoc');
  assert.ok(!g.re.test(readGreet+writeRecord('2026-11-08-audit-log')),'reading greet.py, writing its test and the record');
});

// Review of the first fixtures: the greet.py guard must read commands the way the record side
// does (JSON-aware, a path before greet.py, not tests/test_greet.py), a record slug may contain
// an s, one command may not both write the code and count as the thing before it, and red-first
// must see a failing run, not any run and any failure.
// The runner writes a failing result's keys as content, is_error, tool_use_id and a passing
// one's as tool_use_id, type, content; both shapes are in the real traces.
const result=(text,is_error,id='toolu_01')=>JSON.stringify({type:'user',message:{role:'user',content:[is_error?{type:'tool_result',content:text,is_error:true,tool_use_id:id}:{tool_use_id:id,type:'tool_result',content:text}]}})+'\n';
const unittest=call('Bash',{command:'python3 -m unittest discover -s tests -t . 2>&1 | tail -5'});
const failed=result('Exit code 1\n\n----------------------------------------------------------------------\nRan 4 tests in 0.002s\n\nFAILED (failures=1)',true);
const passed=result('----------------------------------------------------------------------\nRan 3 tests in 0.001s\n\nOK',false);
const writeTest=call('Write',{file_path:`${cwd}tests/test_greet.py`,content:'import unittest\nfrom greet import greet\n'});
const codeByShell=[
  call('Bash',{command:'sed -i "s/Hello/HELLO/" greet.py'}),
  call('Bash',{command:'echo "SHOUT = True" >> greet.py'}),
  call('Bash',{command:"cat > ./greet.py <<'EOF'\nimport sys\nEOF"}),
  call('Bash',{command:`tee ${cwd}greet.py <<'EOF'\nimport sys\nEOF`}),
];
const notCode=[
  call('Bash',{command:"tee tests/test_greet.py <<'EOF'\nimport unittest\nEOF"}),
  call('Bash',{command:"sed -i 's/a/b/' tests/test_greet.py"}),
  call('Bash',{command:'cp greet.py greet.py.bak'}),
  call('Bash',{command:"sed -i 's/a/b/' README.md && cat greet.py"}),
  call('Bash',{command:'python3 greet.py --shout Ada > /tmp/out.txt'}),
];
test('the greet.py guard reads shell forms the way the record side does',()=>{
  const rbc=grader('record-before-code','record-before-code.md').re;
  const trb=grader('red-first','test-run-before-code-change.md').re;
  const ncw=grader('tier-2-stops-before-code','no-code-written.md').re;
  for(const c of codeByShell){
    assert.ok(!rbc.test(c+writeRecord('2026-11-08-shout')),`code first: ${c.slice(80,150)}`);
    assert.ok(!trb.test(c+unittest),`code before the run: ${c.slice(80,150)}`);
    assert.ok(ncw.test(c),`writes greet.py: ${c.slice(80,150)}`);
  }
  for(const c of notCode){
    assert.ok(rbc.test(c+writeRecord('2026-11-08-shout')),`not code: ${c.slice(80,150)}`);
    assert.ok(trb.test(c+unittest),`not code before the run: ${c.slice(80,150)}`);
    assert.ok(!ncw.test(c),`does not write greet.py: ${c.slice(80,150)}`);
  }
});
test('one command that writes the code and runs the tests is not a run before the code',()=>{
  const trb=grader('red-first','test-run-before-code-change.md').re;
  const both=call('Bash',{command:"cat > greet.py <<'EOF'\nimport sys\nEOF\npython3 -m unittest discover -s tests -t ."});
  assert.ok(!trb.test(writeTest+both),'write and run in one command');
  assert.ok(trb.test(writeTest+unittest+failed+writeGreet),'run, then write');
  const pbr=grader('probed-facts-labelled','probed-before-record.md').re;
  const probeAndRecord=call('Bash',{command:`python3 -c "import fileinput" && cat > docs/changes/2026-11-08-names-file.md <<'EOF'\n---\nEOF`});
  assert.ok(!pbr.test(probeAndRecord),'probe and record in one command');
});
test('saw-it-fail needs a failing test run before greet.py changes',()=>{
  const {re}=grader('red-first','saw-it-fail.md');
  assert.ok(re.test(writeTest+unittest+failed+writeGreet+unittest+passed),'red then green');
  assert.ok(re.test(writeTest+heredocGreet.replace('greet.py','tests/test_greet.py')+unittest+result('Ran 1 test\n\nFAILED (errors=1)',true)+heredocGreet),'an erroring run counts as a failing one');
  assert.ok(!re.test(writeTest+unittest+passed+writeGreet+unittest+failed),'green, code, then red');
  assert.ok(!re.test(writeTest+writeGreet+unittest+failed),'code first, then red');
  assert.ok(!re.test(writeTest+unittest+result('Exit code 1\nTraceback\nSyntaxError: invalid syntax',true)+writeGreet),'a run that did not reach the tests is not a failing test');
  assert.ok(!re.test(writeTest+result('AssertionError is what unittest raises',false)+writeGreet),'the word in a result of some other command is not a failing run');
});
test('a record slug with an s in it is still a record written by shell',()=>{
  const {re}=grader('tier-0-no-record','no-record-written.md');
  assert.ok(re.test(heredocRecord('2026-11-08-spelling')),'heredoc');
  assert.ok(re.test(call('Bash',{command:'tee docs/changes/2026-11-08-readme-fixes.md <<EOF\nx\nEOF'})),'tee');
});

// Third review: a same-named copy of greet.py elsewhere is not a write of the code; the failing
// result must belong to the unittest call, not to any later command; and a probe is also pydoc,
// -m, piped stdin or a scratch script that is then run.
test('a copy of greet.py to another directory is not a write of the code',()=>{
  const rbc=grader('record-before-code','record-before-code.md').re;
  const ncw=grader('tier-2-stops-before-code','no-code-written.md').re;
  for(const cmd of ['cp greet.py /tmp/greet.py','cp greet.py backup/greet.py','mkdir -p /tmp/probe && cat greet.py > /tmp/probe/greet.py']){
    const c=call('Bash',{command:cmd});
    assert.ok(rbc.test(c+writeRecord('2026-11-08-shout')),`not code: ${cmd}`);
    assert.ok(!ncw.test(c),`does not write the repository greet.py: ${cmd}`);
  }
  for(const cmd of ['cp /tmp/new_greet.py greet.py','cp /tmp/greet.py ./greet.py','cat /tmp/x > /tmp/claude-eval-x/home/cwd/greet.py']){
    const c=call('Bash',{command:cmd});
    assert.ok(!rbc.test(c+writeRecord('2026-11-08-shout')),`code: ${cmd}`);
    assert.ok(ncw.test(c),`writes the repository greet.py: ${cmd}`);
  }
});
test('saw-it-fail ties the failing result to the unittest call',()=>{
  const {re}=grader('red-first','saw-it-fail.md');
  const run=call('Bash',{command:'python3 -m unittest discover -s tests -t . 2>&1 | tail -5'},'toolu_run');
  const probeCall=call('Bash',{command:'python3 -c "import fileinput; assert False"'},'toolu_probe');
  const probeFailed=result('Exit code 1\nTraceback (most recent call last):\nAssertionError',true,'toolu_probe');
  assert.ok(!re.test(writeTest+run+result('Ran 3 tests\n\nOK',false,'toolu_run')+probeCall+probeFailed+writeGreet),'a green run and a later failing probe');
  assert.ok(re.test(writeTest+run+result('Ran 4 tests\n\nFAILED (failures=1)',true,'toolu_run')+writeGreet),'the run itself failed');
  assert.ok(re.test(writeTest+run+result('Ran 4 tests\n\nFAILED (failures=1)',false,'toolu_run')+writeGreet),'a failing run piped through tail exits 0 and still counts');
  assert.ok(!re.test(writeTest+run+probeCall+probeFailed+result('Ran 3 tests\n\nOK',false,'toolu_run')+writeGreet),'results out of order do not cross');
});
test('probed-before-record accepts pydoc, -m, piped stdin and a scratch script that is run',()=>{
  const {re}=grader('probed-facts-labelled','probed-before-record.md');
  const rec=writeRecord('2026-11-08-names-file');
  const probes=[
    call('Bash',{command:'python3 -m pydoc fileinput | head -40'}),
    call('Bash',{command:'python3 -m fileinput --help; pydoc3 fileinput.input'}),
    call('Bash',{command:'echo "import fileinput; print(fileinput.input)" | python3'}),
    call('Write',{file_path:`${cwd}../probe.py`,content:'import fileinput\nprint(fileinput.input)\n'})+call('Bash',{command:'python3 ../probe.py'}),
    call('Bash',{command:"mkdir -p /tmp/p && cat > /tmp/p/probe.py <<'EOF'\nimport fileinput\nfor line in fileinput.input(['-']): pass\nEOF\npython3 /tmp/p/probe.py < /dev/null"}),
  ];
  for(const p of probes) assert.ok(re.test(p+rec),`probe: ${p.slice(80,170)}`);
  for(const p of probes) assert.ok(!re.test(rec+p),`record first: ${p.slice(80,170)}`);
  const notProbes=[
    call('Bash',{command:"cat > tests/test_names.py <<'EOF'\nimport fileinput\nEOF\npython3 -m unittest discover -s tests -t ."}),
    call('Write',{file_path:`${cwd}../probe.py`,content:'import fileinput\n'}),
    call('Write',{file_path:`${cwd}../probe.py`,content:'import sys\n'})+call('Bash',{command:'python3 ../probe.py'}),
    call('Bash',{command:'grep -n fileinput greet.py; python3 greet.py names.txt'}),
  ];
  for(const p of notProbes) assert.ok(!re.test(p+rec),`not a probe: ${p.slice(80,170)}`);
});

// R9 (record docs/changes/2026-11-09-skill-transcripts.md): the field graders `transcripts grade`
// runs on real sessions take the eval graders' own fixtures, with each call's result added (a
// field grader counts a call only when its result shows it ran), and give the eval grader's
// verdict, except where the generalisation differs on purpose (listed with the reason).
const transcripts=path.join(root,'..','bin','transcripts');
const ok=(c,text='ok')=>c+result(text,false,JSON.parse(c).message.content[0].id);
const created=c=>ok(c,'File created successfully');
const missing=c=>c+result('File does not exist.',true,JSON.parse(c).message.content[0].id);
const say=t=>JSON.stringify({type:'assistant',message:{content:[{type:'text',text:t}]}})+'\n';
const field=(trace,step)=>{
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),'field-'));
  try {
    fs.writeFileSync(path.join(dir,'s.jsonl'),trace);
    const r=spawnSync('python3',[transcripts,'grade','--transcript',path.join(dir,'s.jsonl'),'--cwd',cwd],{encoding:'utf8'});
    assert.equal(r.status,0,r.stderr);
    const row=r.stdout.trim().split('\n').map(l=>JSON.parse(l)).find(x=>x.step===step);
    return row.verdict;
  } finally { fs.rmSync(dir,{recursive:true,force:true}); }
};
const agree=(pairs,step,evalRe,diverge={})=>{
  for(const [name,evalTrace,fieldTrace] of pairs){
    const want=name in diverge?diverge[name][0]:(evalRe.test(evalTrace)?'pass':'fail');
    assert.equal(field(fieldTrace,step),want,`${step}: ${name}${name in diverge?' ('+diverge[name][1]+')':''}`);
  }
};
test('R9: record-before-code gives the eval grader\'s verdicts on its fixtures',()=>{
  const re=grader('record-before-code','record-before-code.md').re;
  const R=id=>writeRecord(id), r=id=>created(writeRecord(id));
  const pairs=[
    ['Write then code',R('2026-11-08-shout')+writeGreet,r('2026-11-08-shout')+ok(writeGreet)],
    ['heredoc then code',heredocRecord('2026-11-08-shout')+heredocGreet,ok(heredocRecord('2026-11-08-shout'))+ok(heredocGreet)],
    ['code then Write',writeGreet+R('2026-11-08-shout'),ok(writeGreet)+r('2026-11-08-shout')],
    ['code then heredoc',heredocGreet+heredocRecord('2026-11-08-shout'),ok(heredocGreet)+ok(heredocRecord('2026-11-08-shout'))],
    ['test first',readGreet+heredocRecord('2026-11-08-shout')+heredocGreet,ok(readGreet)+ok(heredocRecord('2026-11-08-shout'))+ok(heredocGreet)],
  ];
  // each with code after the record, as the field grader holds a step no code reached as not applicable
  for(const c of [...codeByShell,...notCode]) pairs.push([JSON.parse(c).message.content[0].input.command,c+R('2026-11-08-shout')+writeGreet,ok(c)+r('2026-11-08-shout')+ok(writeGreet)]);
  for(const cmd of ['cp greet.py /tmp/greet.py','cp greet.py backup/greet.py','mkdir -p /tmp/probe && cat greet.py > /tmp/probe/greet.py',
    'cp /tmp/new_greet.py greet.py','cp /tmp/greet.py ./greet.py','cat /tmp/x > /tmp/claude-eval-x/home/cwd/greet.py']){
    const c=call('Bash',{command:cmd});
    pairs.push([cmd,c+R('2026-11-08-shout')+writeGreet,ok(c)+r('2026-11-08-shout')+ok(writeGreet)]);
  }
  agree(pairs,'record-before-code',re,{'cp greet.py backup/greet.py':['fail','a new code file in the repository is code, wherever it is copied from']});
  assert.equal(field(writeGreet+R('2026-11-08-shout'),'record-before-code'),'not_applicable','calls with no result never ran: no record, no code');
});
test('R9: red-first gives saw-it-fail\'s verdicts on its fixtures',()=>{
  const re=grader('red-first','saw-it-fail.md').re;
  const run=call('Bash',{command:'python3 -m unittest discover -s tests -t . 2>&1 | tail -5'},'toolu_run');
  const probeCall=call('Bash',{command:'python3 -c "import fileinput; assert False"'},'toolu_probe');
  const probeFailed=result('Exit code 1\nTraceback (most recent call last):\nAssertionError',true,'toolu_probe');
  const testsByShell=heredocGreet.replace('greet.py','tests/test_greet.py');
  const both=call('Bash',{command:"cat > greet.py <<'EOF'\nimport sys\nEOF\npython3 -m unittest discover -s tests -t ."});
  agree([
    ['red then green',writeTest+unittest+failed+writeGreet+unittest+passed,ok(writeTest)+unittest+failed+ok(writeGreet)+unittest+passed],
    ['an erroring run',writeTest+testsByShell+unittest+result('Ran 1 test\n\nFAILED (errors=1)',true)+heredocGreet,
      ok(writeTest)+ok(testsByShell)+unittest+result('Ran 1 test\n\nFAILED (errors=1)',true)+ok(heredocGreet)],
    ['green, code, red',writeTest+unittest+passed+writeGreet+unittest+failed,ok(writeTest)+unittest+passed+ok(writeGreet)+unittest+failed],
    ['code first, then red',writeTest+writeGreet+unittest+failed,ok(writeTest)+ok(writeGreet)+unittest+failed],
    ['did not reach the tests',writeTest+unittest+result('Exit code 1\nTraceback\nSyntaxError: invalid syntax',true)+writeGreet,
      ok(writeTest)+unittest+result('Exit code 1\nTraceback\nSyntaxError: invalid syntax',true)+ok(writeGreet)],
    ['the word in another result',writeTest+result('AssertionError is what unittest raises',false)+writeGreet,
      writeTest+result('AssertionError is what unittest raises',false)+ok(writeGreet)],
    ['a green run, a failing probe',writeTest+run+result('Ran 3 tests\n\nOK',false,'toolu_run')+probeCall+probeFailed+writeGreet,
      ok(writeTest)+run+result('Ran 3 tests\n\nOK',false,'toolu_run')+probeCall+probeFailed+ok(writeGreet)],
    ['the run failed, flagged',writeTest+run+result('Ran 4 tests\n\nFAILED (failures=1)',true,'toolu_run')+writeGreet,
      ok(writeTest)+run+result('Ran 4 tests\n\nFAILED (failures=1)',true,'toolu_run')+ok(writeGreet)],
    ['the run failed, through tail',writeTest+run+result('Ran 4 tests\n\nFAILED (failures=1)',false,'toolu_run')+writeGreet,
      ok(writeTest)+run+result('Ran 4 tests\n\nFAILED (failures=1)',false,'toolu_run')+ok(writeGreet)],
    ['results out of order',writeTest+run+probeCall+probeFailed+result('Ran 3 tests\n\nOK',false,'toolu_run')+writeGreet,
      ok(writeTest)+run+probeCall+probeFailed+result('Ran 3 tests\n\nOK',false,'toolu_run')+ok(writeGreet)],
    ['code and run in one command',writeTest+both,ok(writeTest)+ok(both,'Ran 1 test\n\nFAILED (failures=1)')],
  ],'red-first',re);
  const denied=call('Bash',{command:'python3 -m unittest discover -s tests -t .'},'toolu_d');
  assert.equal(field(ok(writeTest)+denied+result('This command requires approval',true,'toolu_d')+ok(writeGreet),'red-first'),'fail','a denied run is not run');
});
test('R9: probe-before-record gives probed-before-record\'s verdicts on its fixtures',()=>{
  const re=grader('probed-facts-labelled','probed-before-record.md').re;
  const id='2026-11-08-names-file', R=writeRecord(id), r=created(writeRecord(id));
  const readR=call('Bash',{command:`cat docs/changes/README.md docs/changes/TEMPLATE.md; ls docs/changes/${id}.md`});
  const readF=call('Read',{file_path:`${cwd}docs/changes/${id}.md`});
  const pairs=[
    ['probe then Write',probe+R,ok(probe)+r],['probe then heredoc',probe+heredocRecord(id),ok(probe)+ok(heredocRecord(id))],
    ['Write then probe',R+probe,r+ok(probe)],['heredoc then probe',heredocRecord(id)+probe,ok(heredocRecord(id))+ok(probe)],
    ['cp of the template then probe',cpRecord(id)+probe,ok(cpRecord(id))+ok(probe)],
    ['reading docs/changes first',readRecord(id)+probe+R,ok(readR)+missing(readF)+ok(probe)+r],
    ['probe and record in one command',call('Bash',{command:`python3 -c "import fileinput" && cat > docs/changes/${id}.md <<'EOF'\n---\nEOF`})+R,
      ok(call('Bash',{command:`python3 -c "import fileinput" && cat > docs/changes/${id}.md <<'EOF'\n---\nEOF`}))+r],
  ];
  const probes=[
    [call('Bash',{command:'python3 -m pydoc fileinput | head -40'})],[call('Bash',{command:'python3 -m fileinput --help; pydoc3 fileinput.input'})],
    [call('Bash',{command:'echo "import fileinput; print(fileinput.input)" | python3'})],
    [call('Write',{file_path:`${cwd}../probe.py`,content:'import fileinput\nprint(fileinput.input)\n'}),call('Bash',{command:'python3 ../probe.py'})],
    [call('Bash',{command:"mkdir -p /tmp/p && cat > /tmp/p/probe.py <<'EOF'\nimport fileinput\nfor line in fileinput.input(['-']): pass\nEOF\npython3 /tmp/p/probe.py < /dev/null"})],
    [call('Bash',{command:"cat > tests/test_names.py <<'EOF'\nimport fileinput\nEOF\npython3 -m unittest discover -s tests -t ."})],
    [call('Write',{file_path:`${cwd}../probe.py`,content:'import fileinput\n'})],
    [call('Write',{file_path:`${cwd}../probe.py`,content:'import sys\n'}),call('Bash',{command:'python3 ../probe.py'})],
    [call('Bash',{command:'grep -n fileinput greet.py; python3 greet.py names.txt'})],
  ];
  probes.forEach((cs,i)=>{
    pairs.push([`probe ${i} first`,cs.join('')+R,cs.map(c=>ok(c)).join('')+r]);
    pairs.push([`probe ${i} after`,R+cs.join(''),r+cs.map(c=>ok(c)).join('')]);
  });
  agree(pairs,'probe-before-record',re,{'probe 7 first':['pass','a scratch script that is run is a probe; which dependency it probes is for the reader, since no field grader knows the change\'s'],
    'probe 5 first':['pass','a run of the tests before the record is a probe by the owner\'s ruling of 2026-11-12 (record 2026-11-12-grader-fixes); the eval grader asks for a probe of fileinput itself']});
});
test('R9: tier-declared reads Tier: 0 as declares-tier-0 does',()=>{
  const re=grader('tier-0-no-record','declares-tier-0.md').re;
  const typo=call('Edit',{file_path:`${cwd}greet.py`,old_string:'teh',new_string:'the'});
  agree(['Tier: 0','**Tier: 0**','**Tier**: 0','**Tier:** 0','Tier:0','- Tier: 0 (no behaviour change)','Tier: 1','Tier: 10','tier: 0']
    .map(s=>[s,s,ok(typo)+say(`Fixed the typo.\n\n${s}`)]),'tier-declared',re);
});

// The same cases as an evals.json (record docs/changes/2026-11-12-portable-evals.md): the open
// Agent Skills guide's format, generated from the case folders by export-evals-json into the
// skill's own folder, so tools that are not Claude's can read them.
const exporter=path.join(root,'export-evals-json');
const skillDir=path.join(root,'..','skills','change');
const scored=c=>fs.readdirSync(path.join(root,c,'graders')).filter(g=>g!=='skill-fired.md').sort();
const top=(c,g)=>{
  const text=fs.readFileSync(path.join(root,c,'graders',g),'utf8');
  return text.slice(4,text.indexOf('\n---',4));
};
const statements=(c,g)=>top(c,g).split('\n').filter(l=>/^# assertion:/.test(l)).map(l=>l.replace(/^# assertion:\s*/,'').trim());
test('every scored grader states what it checks in one plain sentence; skill-fired states nothing',()=>{
  let n=0;
  for(const c of cases){
    for(const g of scored(c)){
      const s=statements(c,g);
      assert.equal(s.length,1,`${c}/${g}: one "# assertion:" line in the top block, found ${s.length}`);
      assert.ok(s[0].length>20 && /[.]$/.test(s[0]),`${c}/${g}: a full sentence, got "${s[0]}"`);
      assert.ok(!/PASS if|FAIL if/.test(s[0]),`${c}/${g}: a statement, not the judge's instructions`);
      n++;
    }
    assert.equal(statements(c,'skill-fired.md').length,0,`${c}/skill-fired.md is an indicator, not an assertion`);
  }
  assert.equal(n,29);
});
test('a statement about what the agent did says it needs the transcript',()=>{
  for(const c of cases) for(const g of scored(c)){
    const t=top(c,g), s=statements(c,g)[0]||'';
    const actions=/^target: trace$/m.test(t) || /^type: tool_used$/m.test(t);
    const aboutAFile=['no-record-written.md','no-code-edited.md'].includes(g);
    if(actions && !aboutAFile) assert.match(s,/^The transcript shows /,`${c}/${g}`);
    else assert.doesNotMatch(s,/transcript/i,`${c}/${g}`);
  }
});
const run=(...args)=>spawnSync('python3',[exporter,...args],{encoding:'utf8'});
test('the committed evals.json and input files are what the case folders give',()=>{
  const r=run('--check');
  assert.equal(r.status,0,r.stdout+r.stderr);
});
test('evals.json has the guide\'s shape: one entry per case, its prompt, its description, its statements',()=>{
  const doc=JSON.parse(fs.readFileSync(path.join(skillDir,'evals','evals.json'),'utf8'));
  assert.deepEqual(Object.keys(doc),['skill_name','evals']);
  assert.equal(doc.skill_name,'change');
  assert.deepEqual(doc.evals.map(e=>e.name),[...cases].sort());
  assert.deepEqual(doc.evals.map(e=>e.id),doc.evals.map((_,i)=>i+1));
  for(const e of doc.evals){
    assert.deepEqual(Object.keys(e),['id','name','prompt','expected_output','files','assertions'],e.name);
    const prompt=fs.readFileSync(path.join(root,e.name,'prompt.md'),'utf8').trim();
    assert.ok(e.prompt.endsWith(prompt),`${e.name}: the case's own prompt, whole`);
    assert.match(e.prompt,/^The repository for this task is the folder `repo\/` of the input files/,e.name);
    const described=fs.readFileSync(path.join(root,e.name,'case.yaml'),'utf8').match(/^description: "(.*)"$/m)[1];
    assert.equal(e.expected_output,described,e.name);
    assert.deepEqual(e.assertions,scored(e.name).map(g=>statements(e.name,g)[0]),e.name);
    assert.deepEqual(e.files,['evals/files/repo/README.md','evals/files/repo/docs/changes/README.md','evals/files/repo/docs/changes/TEMPLATE.md',
      'evals/files/repo/greet.py','evals/files/repo/tests/__init__.py','evals/files/repo/tests/test_greet.py'],e.name);
    for(const f of e.files) assert.ok(fs.existsSync(path.join(skillDir,f)),`${e.name}: ${f} is in the skill folder`);
  }
});
test('the input files are the scaffold\'s, and --check fails when a prompt, a statement or a file has drifted',()=>{
  const scratch=fs.mkdtempSync(path.join(os.tmpdir(),'cr-export-'));
  try{
    const out=path.join(scratch,'skill');
    let r=run('--skill-dir',out);
    assert.equal(r.status,0,r.stderr);
    assert.equal(fs.readFileSync(path.join(out,'evals/files/repo/docs/changes/TEMPLATE.md'),'utf8'),fs.readFileSync(path.join(root,'..','templates/docs-changes/TEMPLATE.md'),'utf8'));
    assert.ok(!fs.existsSync(path.join(out,'evals/files/repo/.git')),'no git folder among the input files');
    assert.equal(run('--check','--skill-dir',out).status,0);
    const json=path.join(out,'evals','evals.json');
    const good=fs.readFileSync(json,'utf8');
    fs.writeFileSync(json,good.replace('upper case','lower case'));
    r=run('--check','--skill-dir',out);
    assert.equal(r.status,1); assert.match(r.stderr,/evals\.json is not what the case folders give/);
    fs.writeFileSync(json,good);
    fs.appendFileSync(path.join(out,'evals/files/repo/greet.py'),'# changed\n');
    r=run('--check','--skill-dir',out);
    assert.equal(r.status,1); assert.match(r.stderr,/evals\/files\/repo\/greet\.py differs/);
    fs.rmSync(path.join(out,'evals/files/repo/greet.py'));
    fs.writeFileSync(path.join(out,'evals/files/repo/extra.txt'),'x');
    r=run('--check','--skill-dir',out);
    assert.equal(r.status,1); assert.match(r.stderr,/greet\.py is missing/); assert.match(r.stderr,/extra\.txt is not one of the scaffold's files/);
    assert.equal(fs.readFileSync(json,'utf8'),good,'--check writes nothing');
    r=run('--bogus');
    assert.equal(r.status,2); assert.match(r.stderr,/usage: export-evals-json/);
  } finally { fs.rmSync(scratch,{recursive:true,force:true}); }
});
// A copy of the cases and the templates the scaffold reads, so a case can be broken without touching the real ones.
const copyOfCases=scratch=>{
  const plugin=path.join(scratch,'plugin');
  fs.cpSync(root,path.join(plugin,'evals'),{recursive:true,filter:s=>!/[\\/](results|node_modules)([\\/]|$)/.test(s)});
  fs.cpSync(path.join(root,'..','templates'),path.join(plugin,'templates'),{recursive:true});
  return {dir:path.join(plugin,'evals'),run:(...args)=>spawnSync('python3',[path.join(plugin,'evals','export-evals-json'),'--skill-dir',path.join(scratch,'skill'),...args],{encoding:'utf8'})};
};
test('the generator refuses a case it cannot state: a grader with no statement, or two, and cases from different repositories',()=>{
  const scratch=fs.mkdtempSync(path.join(os.tmpdir(),'cr-export-'));
  try{
    const {dir,run}=copyOfCases(scratch);
    assert.equal(run().status,0);
    const g=path.join(dir,'red-first','graders','saw-it-fail.md'), good=fs.readFileSync(g,'utf8');
    fs.writeFileSync(g,good.replace(/^# assertion:.*\n/m,''));
    let r=run();
    assert.equal(r.status,2); assert.match(r.stderr,/red-first\/graders\/saw-it-fail\.md needs one "# assertion:" line in its top block, found 0/);
    fs.writeFileSync(g,good.replace(/^(# assertion:.*\n)/m,'$1$1'));
    r=run();
    assert.equal(r.status,2); assert.match(r.stderr,/found 2/);
    fs.writeFileSync(g,good+'\n# assertion: A line below the top block is the judge\'s text, not a statement.\n');
    assert.equal(run().status,0,'a line outside the top block is not read');
    fs.writeFileSync(path.join(dir,'red-first','scaffold.sh'),'#!/bin/bash\nbash "$(dirname "$0")/../_scaffold/greet.sh" && echo extra > extra.txt\n');
    r=run();
    assert.equal(r.status,2); assert.match(r.stderr,/the cases start from different repositories/);
  } finally { fs.rmSync(scratch,{recursive:true,force:true}); }
});
test('a settings block on top of a prompt is not part of the prompt; writing again removes a stale input file; a missing evals.json is said',()=>{
  const scratch=fs.mkdtempSync(path.join(os.tmpdir(),'cr-export-'));
  try{
    const {dir,run}=copyOfCases(scratch);
    const p=path.join(dir,'red-first','prompt.md');
    fs.writeFileSync(p,'---\ntags: [x]\nmax_turns: 20\n---\n\n'+fs.readFileSync(p,'utf8'));
    assert.equal(run().status,0);
    const out=path.join(scratch,'skill','evals');
    const e=JSON.parse(fs.readFileSync(path.join(out,'evals.json'),'utf8')).evals.find(x=>x.name==='red-first');
    assert.doesNotMatch(e.prompt,/max_turns|tags:/);
    assert.match(e.prompt,/working directory\.\n\nQuick one before I head out/);
    fs.writeFileSync(path.join(out,'files','repo','stale.txt'),'x');
    assert.equal(run().status,0);
    assert.ok(!fs.existsSync(path.join(out,'files','repo','stale.txt')));
    fs.rmSync(path.join(out,'evals.json'));
    const r=run('--check');
    assert.equal(r.status,1); assert.match(r.stderr,/evals\/evals\.json is missing/);
  } finally { fs.rmSync(scratch,{recursive:true,force:true}); }
});

// The verification script the guide asks for (record 2026-11-12-portable-evals, task 2):
// skills/change/evals/verify checks, with no model, the statements code can check against the
// folder a run left, from evals/checks.json, which export-evals-json writes from the graders.
const verify=path.join(skillDir,'evals','verify');
const vrun=(...a)=>{ const r=spawnSync('python3',[verify,...a],{encoding:'utf8'}); let out=null; try{ out=JSON.parse(r.stdout); }catch{} return {status:r.status,out,stderr:r.stderr}; };
const leftBy=(scratch,name)=>{ const d=path.join(scratch,name); fs.cpSync(path.join(skillDir,'evals','files','repo'),d,{recursive:true}); return d; };
const aRecord=(id,tier,sections)=>`---\nid: ${id}\ntier: ${tier}\nstatus: open\n---\n# Title\n\n`+sections.map(s=>`## ${s}\ntext\n`).join('\n');
const T1=['Goal','Probed facts','Decisions','Tasks','Checks','Outcome'];
const by=(out,word)=>out.assertion_results.find(r=>r.text.includes(word));
test('checks.json holds one check per statement code can check, with the grader\'s own path and pattern',()=>{
  const doc=JSON.parse(fs.readFileSync(path.join(skillDir,'evals','checks.json'),'utf8'));
  const evals=JSON.parse(fs.readFileSync(path.join(skillDir,'evals','evals.json'),'utf8')).evals;
  assert.deepEqual(Object.keys(doc),['skill_name','checks']);
  assert.deepEqual(Object.keys(doc.checks),evals.map(e=>e.name));
  const kinds={};
  for(const e of evals) for(const c of doc.checks[e.name]){
    kinds[c.kind]=(kinds[c.kind]||0)+1;
    assert.ok(e.assertions.includes(c.assertion),`${e.name}/${c.grader}: its statement is one of the case's assertions`);
    assert.equal(statements(e.name,c.grader+'.md')[0],c.assertion);
    const t=top(e.name,c.grader+'.md');
    if(c.kind==='file_exists') assert.match(t,new RegExp(`^path: ${c.path.replace(/[.]/g,'\\.')}$`,'m'));
    if(c.kind==='file_matches'||c.kind==='message_matches'){
      const g=grader(e.name,c.grader+'.md');
      assert.equal(new RegExp(c.pattern,c.flags).source,g.re.source,`${e.name}/${c.grader}: the grader's pattern`);
      assert.equal(c.flags,g.re.flags);
    }
    if(c.kind==='file_matches') assert.match(t,new RegExp(`^  path: ${c.path.replace(/[.]/g,'\\.')}$`,'m'));
  }
  assert.deepEqual(kinds,{file_exists:5,file_matches:6,message_matches:2,only:1,unchanged:1});
});
test('the generator keeps checks.json in step, and refuses a check line it cannot read',()=>{
  const scratch=fs.mkdtempSync(path.join(os.tmpdir(),'cr-export-'));
  try{
    const {dir,run}=copyOfCases(scratch);
    assert.equal(run().status,0);
    const cj=path.join(scratch,'skill','evals','checks.json'), good=fs.readFileSync(cj,'utf8');
    fs.writeFileSync(cj,good.replace('"unchanged"','"changed"'));
    let r=run('--check');
    assert.equal(r.status,1); assert.match(r.stderr,/evals\/checks\.json is not what the case folders give/);
    fs.rmSync(cj);
    r=run('--check');
    assert.equal(r.status,1); assert.match(r.stderr,/evals\/checks\.json is missing/);
    const g=path.join(dir,'tier-2-stops-before-code','graders','no-code-edited.md');
    fs.writeFileSync(g,fs.readFileSync(g,'utf8').replace(/^# check: unchanged .*$/m,'# check: untouched greet.py'));
    r=run();
    assert.equal(r.status,2); assert.match(r.stderr,/no-code-edited\.md: "# check:" must be "unchanged PATH" or "only DIR NAME\.\.\."/);
    const edit=(c,name,from,to)=>{ const f=path.join(dir,c,'graders',name), t=fs.readFileSync(f,'utf8'); const n=t.replace(from,to); assert.notEqual(n,t,`${name} has ${from}`); fs.writeFileSync(f,n); return ()=>fs.writeFileSync(f,t); };
    fs.writeFileSync(g,fs.readFileSync(g,'utf8').replace('# check: untouched greet.py','# check: unchanged greet.py\n# check: unchanged README.md'));
    r=run();
    assert.equal(r.status,2,'two check lines are refused'); assert.match(r.stderr,/"# check:" must be/);
    fs.writeFileSync(g,fs.readFileSync(g,'utf8').replace('\n# check: unchanged README.md',''));
    assert.equal(run().status,0);
    let undo=edit('record-before-code','record-is-tier-1.md','match: contains','match: not_contains');
    r=run();
    assert.equal(r.status,2); assert.match(r.stderr,/record-is-tier-1\.md: a pattern in single quotes that must be found/);
    undo(); undo=edit('record-before-code','record-is-tier-1.md','flags: m','flags: mu');
    assert.equal(run().status,2,'a flag Python does not have is refused');
    undo(); undo=edit('record-before-code','record-is-tier-1.md',/^pattern: .*$/m,"pattern: '^tier:(?<n>\\s*1)'");
    r=run();
    assert.equal(r.status,2); assert.match(r.stderr,/record-is-tier-1\.md: Python cannot read the pattern/);
    undo(); undo=edit('record-before-code','record-exists.md','exists: true','exists: false');
    assert.equal(run().status,0);
    const made=JSON.parse(fs.readFileSync(cj,'utf8')).checks['record-before-code'].map(c=>c.grader);
    assert.deepEqual(made,['pr-body-names-record','record-has-sections','record-is-tier-1'],'a grader that asks for a file to be absent gets no check');
  } finally { fs.rmSync(scratch,{recursive:true,force:true}); }
});
test('verify: a record that is there, of the right tier, with its sections in order, passes the file checks; the rest is listed as not checked',()=>{
  const scratch=fs.mkdtempSync(path.join(os.tmpdir(),'cr-verify-'));
  try{
    const out=leftBy(scratch,'run');
    fs.writeFileSync(path.join(out,'docs/changes/2026-11-08-shout.md'),aRecord('2026-11-08-shout',1,T1));
    const r=vrun('record-before-code',out);
    assert.equal(r.status,0,r.stderr);
    assert.deepEqual(Object.keys(r.out),['eval','assertion_results','not_checked','summary']);
    assert.equal(r.out.eval,'record-before-code');
    assert.equal(r.out.assertion_results.length,3);
    for(const a of r.out.assertion_results){ assert.deepEqual(Object.keys(a),['text','passed','evidence']); assert.equal(a.passed,true,a.text); assert.ok(a.evidence.length>5); }
    assert.match(by(r.out,'says "tier: 1"').evidence,/tier: 1/);
    assert.match(by(r.out,'exists').evidence,/docs\/changes\/2026-11-08-shout\.md is there/);
    assert.deepEqual(r.out.summary,{passed:3,failed:0,total:3,pass_rate:1});
    assert.deepEqual(r.out.not_checked.map(n=>n.why).sort(),['needs a judge','needs the run\'s final message (--final-message FILE)','needs the run\'s transcript']);
    for(const n of r.out.not_checked) assert.ok(n.text.length>20);
  } finally { fs.rmSync(scratch,{recursive:true,force:true}); }
});
test('verify: a missing record, a wrong tier and sections out of order each fail, with the evidence, and the exit status is 1',()=>{
  const scratch=fs.mkdtempSync(path.join(os.tmpdir(),'cr-verify-'));
  try{
    const out=leftBy(scratch,'run');
    let r=vrun('record-before-code',out);
    assert.equal(r.status,1);
    assert.deepEqual(r.out.summary,{passed:0,failed:3,total:3,pass_rate:0});
    for(const a of r.out.assertion_results) assert.match(a.evidence,/docs\/changes\/2026-11-08-shout\.md is not in the outputs folder/);
    fs.writeFileSync(path.join(out,'docs/changes/2026-11-08-shout.md'),aRecord('2026-11-08-shout',2,['Goal','Decisions','Probed facts','Tasks','Checks','Outcome']));
    r=vrun('record-before-code',out);
    assert.equal(r.status,1);
    assert.equal(by(r.out,'exists').passed,true);
    assert.equal(by(r.out,'says "tier: 1"').passed,false);
    assert.match(by(r.out,'says "tier: 1"').evidence,/nothing in docs\/changes\/2026-11-08-shout\.md matches/);
    assert.equal(by(r.out,'in this order').passed,false);
    assert.deepEqual(r.out.summary,{passed:1,failed:2,total:3,pass_rate:0.33});
  } finally { fs.rmSync(scratch,{recursive:true,force:true}); }
});
test('verify: the final message is checked only when it is given',()=>{
  const scratch=fs.mkdtempSync(path.join(os.tmpdir(),'cr-verify-'));
  try{
    const out=leftBy(scratch,'run'), msg=path.join(scratch,'final.md');
    fs.writeFileSync(path.join(out,'docs/changes/2026-11-08-shout.md'),aRecord('2026-11-08-shout',1,T1));
    fs.writeFileSync(msg,'Done.\n\nChange: docs/changes/2026-11-08-shout.md\n');
    let r=vrun('record-before-code',out,'--final-message',msg);
    assert.equal(r.status,0); assert.equal(r.out.summary.total,4);
    assert.match(by(r.out,'final message contains').evidence,/Change: docs\/changes\/2026-11-08-shout\.md/);
    assert.equal(r.out.not_checked.length,2);
    fs.writeFileSync(msg,'Done. The record is in docs/changes.\n');
    r=vrun('record-before-code',out,'--final-message',msg);
    assert.equal(r.status,1);
    assert.equal(by(r.out,'final message contains').passed,false);
    assert.match(by(r.out,'final message contains').evidence,/nothing in the final message matches/);
    fs.writeFileSync(msg,'Typo fixed.\n\n**Tier: 0**\n');
    r=vrun('tier-0-no-record',out,'--final-message',msg);
    assert.equal(by(r.out,'says "Tier: 0"').passed,true);
    r=vrun('record-before-code',out,'--final-message',path.join(scratch,'none.md'));
    assert.equal(r.status,2); assert.match(r.stderr,/cannot read the final message/);
  } finally { fs.rmSync(scratch,{recursive:true,force:true}); }
});
test('verify: no record created, and greet.py unchanged, are read from the folder',()=>{
  const scratch=fs.mkdtempSync(path.join(os.tmpdir(),'cr-verify-'));
  try{
    const out=leftBy(scratch,'run');
    let r=vrun('tier-0-no-record',out);
    assert.equal(by(r.out,'holds only').passed,true);
    fs.writeFileSync(path.join(out,'docs/changes/2026-11-08-typo.md'),'x');
    r=vrun('tier-0-no-record',out);
    assert.equal(by(r.out,'holds only').passed,false);
    assert.match(by(r.out,'holds only').evidence,/also holds 2026-11-08-typo\.md/);
    fs.rmSync(path.join(out,'docs/changes/2026-11-08-typo.md')); fs.rmSync(path.join(out,'docs/changes/TEMPLATE.md'));
    r=vrun('tier-0-no-record',out);
    assert.equal(by(r.out,'holds only').passed,false);
    assert.match(by(r.out,'holds only').evidence,/lacks TEMPLATE\.md/);
    fs.rmSync(path.join(out,'docs'),{recursive:true});
    r=vrun('tier-0-no-record',out);
    assert.equal(r.status,1);
    assert.match(by(r.out,'holds only').evidence,/docs\/changes\/ is not in the outputs folder/);
    const two=leftBy(scratch,'run2');
    fs.writeFileSync(path.join(two,'docs/changes/2026-11-08-audit-log.md'),aRecord('2026-11-08-audit-log',2,['Goal','Probed facts','Problem','Requirements','Options and concerns','Decisions']));
    r=vrun('tier-2-stops-before-code',two);
    assert.equal(r.status,0,JSON.stringify(r.out));
    assert.equal(by(r.out,'greet.py is unchanged').passed,true);
    assert.equal(r.out.summary.total,4);
    fs.appendFileSync(path.join(two,'greet.py'),'# audit\n');
    r=vrun('tier-2-stops-before-code',two);
    assert.equal(r.status,1);
    assert.match(by(r.out,'greet.py is unchanged').evidence,/greet\.py differs from the input file/);
    fs.rmSync(path.join(two,'greet.py'));
    r=vrun('tier-2-stops-before-code',two);
    assert.match(by(r.out,'greet.py is unchanged').evidence,/greet\.py is not in the outputs folder/);
  } finally { fs.rmSync(scratch,{recursive:true,force:true}); }
});
test('verify: a case by its number, one with nothing to check, and what it refuses',()=>{
  const scratch=fs.mkdtempSync(path.join(os.tmpdir(),'cr-verify-'));
  try{
    const out=leftBy(scratch,'run');
    let r=vrun('6',out);
    assert.equal(r.status,0); assert.equal(r.out.eval,'red-first');
    assert.deepEqual(r.out.assertion_results,[]);
    assert.deepEqual(r.out.summary,{passed:0,failed:0,total:0,pass_rate:null});
    assert.deepEqual(r.out.not_checked.map(n=>n.why),['needs the run\'s transcript','needs the run\'s transcript']);
    r=vrun('no-such-case',out);
    assert.equal(r.status,2); assert.match(r.stderr,/no eval named no-such-case; there are: decisions-record-alternatives, /);
    r=vrun('red-first',path.join(scratch,'nowhere'));
    assert.equal(r.status,2); assert.match(r.stderr,/is not a folder/);
    r=vrun('red-first');
    assert.equal(r.status,2); assert.match(r.stderr,/usage: verify EVAL OUTPUTS/);
    r=vrun('red-first',out,'--bogus');
    assert.equal(r.status,2); assert.match(r.stderr,/usage: verify EVAL OUTPUTS/);
    // over all eight, on the untouched input files: 13 checked from files, 2 wait for the message, 7 for a judge, 7 for the transcript
    const why={}; let checked=0;
    for(const c of [...cases].sort()){ const v=vrun(c,out); checked+=v.out.assertion_results.length; for(const n of v.out.not_checked) why[n.why]=(why[n.why]||0)+1; }
    assert.equal(checked,13);
    assert.deepEqual(why,{'needs a judge':7,'needs the run\'s transcript':7,'needs the run\'s final message (--final-message FILE)':2});
  } finally { fs.rmSync(scratch,{recursive:true,force:true}); }
});
test('verify stands alone: a copy of the skill\'s evals folder works with nothing else of the plugin',()=>{
  const scratch=fs.mkdtempSync(path.join(os.tmpdir(),'cr-verify-'));
  try{
    fs.cpSync(path.join(skillDir,'evals'),path.join(scratch,'evals'),{recursive:true});
    const out=leftBy(scratch,'run');
    const r=spawnSync('python3',['-I',path.join(scratch,'evals','verify'),'tier-0-no-record',out],{encoding:'utf8'});
    assert.equal(r.status,0,r.stderr);
    assert.equal(JSON.parse(r.stdout).assertion_results.length,1);
  } finally { fs.rmSync(scratch,{recursive:true,force:true}); }
});
