const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const os=require('node:os');
const {spawnSync}=require('node:child_process');
const root=path.resolve(__dirname,'..');
const read=p=>fs.readFileSync(path.join(root,p),'utf8');
test('optional workflow has a distinct runtime identity from the feature-loop skill',()=>{
 assert.match(read('workflows/feature-loop.js'), /name: 'execute-feature-plan'/);
 assert.match(read('skills/feature-loop/SKILL.md'), /name: feature-loop/);
 assert.match(read('skills/feature-loop/SKILL.md'), /`execute-feature-plan` workflow/);
 assert.doesNotMatch(read('skills/feature-loop/SKILL.md'), /`feature-loop` workflow/);
});
for(const variant of ['rules','explicit']) test(`wrong-finding-${variant} has fair context and the original outcome graders`,()=>{
 const dir=`evals/wrong-finding-${variant}`;
 assert.ok(fs.existsSync(path.join(root,dir,'case.yaml')), 'variant case exists');
 assert.match(read(`${dir}/case.yaml`),new RegExp(`name: wrong-finding-${variant}`));
 for(const file of fs.readdirSync(path.join(root,'evals/wrong-finding/graders'))) assert.equal(read(`${dir}/graders/${file}`),read(`evals/wrong-finding/graders/${file}`));
 const prompt=read(`${dir}/prompt.md`);
 assert.ok(prompt.includes(read('evals/wrong-finding/prompt.md').trim()));
 const scratch=fs.mkdtempSync(path.join(os.tmpdir(),'eval-context-'));
 try {
  const result=spawnSync('bash',[path.join(root,dir,'scaffold.sh')],{cwd:scratch,encoding:'utf8'});
  assert.equal(result.status,0,result.stderr);
  assert.equal(fs.readFileSync(path.join(scratch,'greet.py'),'utf8').includes('return f"Hello, {name}!"'),true);
  if(variant==='rules') {
   assert.ok(prompt.includes(read('AGENT-WORKFLOW.md').trim()), 'canonical rules are supplied directly in prompt');
   assert.match(prompt,/If a named skill or helper is unavailable/);
   const rules=fs.readFileSync(path.join(scratch,'CLAUDE.md'),'utf8');
   assert.ok(rules.includes(read('AGENT-WORKFLOW.md').trim()));
   assert.match(rules,/If a named skill or helper is unavailable/);
   assert.match(rules,/do not pretend to invoke it/);
  } else {
   assert.equal(read(`${dir}/scaffold.sh`),read('evals/wrong-finding/scaffold.sh'));
   assert.equal(fs.existsSync(path.join(scratch,'CLAUDE.md')),false);
   assert.match(prompt,/agent-workflow:feature-loop/);
   assert.match(prompt,/If it is unavailable/);
  }
 } finally { fs.rmSync(scratch,{recursive:true,force:true}); }
});
test('original discovery control remains free of installed rules and explicit invocation',()=>{
 assert.doesNotMatch(read('evals/wrong-finding/scaffold.sh'),/CLAUDE.md|AGENT-WORKFLOW/);
 assert.doesNotMatch(read('evals/wrong-finding/prompt.md'),/feature-loop/);
});
test('red-first grades test-first behavior without claiming an attempted commit succeeded',()=>{
 assert.equal(fs.existsSync(path.join(root,'evals/red-first/graders/committed.md')),false,'attempted commit is not evidence of success');
 assert.doesNotMatch(read('evals/red-first/prompt.md'),/Commit it when it works/);
 assert.match(read('evals/red-first/graders/test-run-before-code-change.md'),/type: tool_order/);
 assert.match(read('evals/red-first/graders/saw-it-fail.md'),/target: trace/);
});
