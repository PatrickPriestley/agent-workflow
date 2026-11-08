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
