-- The transcript store for `transcripts push` and `transcripts materialize`
-- (record docs/changes/2026-11-09-skill-transcripts.md, task 2).
--
-- Run once in the Supabase project's SQL editor. It is safe to run again: it creates what is
-- missing and resets every grant and policy to what is written here.
--
-- Keys:
--   * The publishable key (role `anon`) is the hooks' key. It may INSERT into `chunks` and
--     `sessions` and nothing else: no SELECT, UPDATE, DELETE or TRUNCATE, and no access to
--     `scores` or `judge_votes`. A duplicate insert is refused with 409 (23505) and changes nothing; `push`
--     counts that as already stored. `Prefer: resolution=ignore-duplicates` is not used: it is
--     ON CONFLICT DO NOTHING, which needs SELECT (probed: 401, 42501).
--   * The secret key (role `service_role`) is the read key, kept on the owner's machine:
--     `materialize` reads with it, and grading (tasks 3 and 4) writes `scores` and `judge_votes` with it.
--   * Signed-in users (role `authenticated`) get nothing.
--
-- No row is ever updated by a sender. A chunk's key is a hash chain over the redacted bytes,
-- so two senders never claim the same key for different bytes, and an index row is a new
-- version keyed by the hash of its own content.

create table if not exists public.chunks (
  session_id text   not null check (session_id ~ '^[A-Za-z0-9._-]{1,100}$'),
  stream     text   not null check (length(stream) between 1 and 300),
  -- sha256(start_id || ':' || sha256(data)), hex; the first chunk of a chain starts from
  -- sha256(session_id || '/' || stream)
  chunk_id   text   not null check (chunk_id ~ '^[0-9a-f]{64}$'),
  start_id   text   not null check (start_id ~ '^[0-9a-f]{64}$'),
  sender     text   not null check (length(sender) between 1 and 200),
  generation integer not null check (generation >= 1),   -- the sender's generation of this stream
  number     integer not null check (number >= 1),       -- the sender's chunk number in it
  lines      integer not null check (lines >= 0),
  bytes      bigint  not null check (bytes >= 0),        -- redacted, uncompressed
  redaction  integer not null,
  data       text    not null check (length(data) <= 8000000),  -- base64 of gzip of the lines
  created_at timestamptz not null default now(),
  primary key (session_id, stream, chunk_id)
);

create table if not exists public.sessions (
  session_id text   not null check (session_id ~ '^[A-Za-z0-9._-]{1,100}$'),
  row_id     text   not null check (row_id ~ '^[0-9a-f]{64}$'),  -- sha256 of the canonical entry
  sender     text   not null check (length(sender) between 1 and 200),
  version    integer not null check (version >= 1),     -- the sender's push count for the session
  entry      jsonb  not null check (length(entry::text) <= 2000000),  -- the redacted index entry
  created_at timestamptz not null default now(),
  primary key (session_id, row_id)
);

create table if not exists public.scores (
  session_id text   not null,
  step       text   not null,
  skill      text   not null,
  skill_blob text,
  grader     text   not null,
  verdict    text   not null check (verdict in ('pass', 'fail', 'not_applicable')),
  evidence   jsonb,
  graded_at  timestamptz not null default now(),
  primary key (session_id, step, grader, graded_at)
);

-- Task 4: every answer the judges gave (transcripts judge --store, with the read key), so a
-- verdict can be audited from its prompt and votes. A malformed, refused or failed answer is
-- kept with its status and is not a vote.
create table if not exists public.judge_votes (
  session_id    text    not null,
  question      text    not null,                       -- decisions-alternative, outcome-real-output
  judge         text    not null,                       -- judge/<version>:<kind>:<model>
  vote          integer not null check (vote between 1 and 9),
  status        text    not null check (status in ('vote', 'malformed', 'refused', 'error')),
  verdict       text    check (verdict in ('pass', 'fail')),
  reason        text,
  detail        text,
  answer        text    check (length(answer) <= 8000),  -- the judge's answer as given
  served_model  text,
  prompt        text    not null check (length(prompt) <= 200000),  -- redacted, as the judge saw it
  prompt_sha256 text    not null check (prompt_sha256 ~ '^[0-9a-f]{64}$'),
  record        text,
  record_sha256 text,
  judged_at     timestamptz not null,
  primary key (session_id, question, judge, vote, judged_at)
);

alter table public.chunks   enable row level security;
alter table public.sessions enable row level security;
alter table public.scores   enable row level security;
alter table public.judge_votes enable row level security;

-- Supabase grants every privilege on new public tables to anon and authenticated by default;
-- take them all back, then give the hooks' role INSERT alone.
revoke all on public.chunks, public.sessions, public.scores, public.judge_votes from public, anon, authenticated;
grant insert on public.chunks, public.sessions to anon;
grant all on public.chunks, public.sessions, public.scores, public.judge_votes to service_role;

drop policy if exists chunks_insert on public.chunks;
drop policy if exists sessions_insert on public.sessions;
create policy chunks_insert on public.chunks for insert to anon with check (true);
create policy sessions_insert on public.sessions for insert to anon with check (true);
-- No SELECT, UPDATE or DELETE policy exists for anon or authenticated, and no privilege either.
-- service_role bypasses row-level security.

-- ---- The text of a session, for a person to read (record docs/changes/2026-11-15-readable-store.md) ----
--
-- `chunks.data` is gzip, which no query can open. `messages` holds the same redacted text once
-- more, a row for each text, tool call and tool result of a transcript line, written by `push`
-- beside each chunk and by `transcripts messages` for what is already stored. The chunks stay
-- what `materialize` and the graders read; if the two ever disagree the chunks are right, and
-- `transcripts messages --check` says so.
--
-- The hooks' key (role `anon`) may INSERT into `messages` and nothing else. The view
-- `transcript` is for the dashboard and the read key. `shape` is the version of the rule that
-- read the rows: the view reads the one shape its text names, so that rows inserted under
-- another are not shown. When the rule changes, the number changes here and in the tool
-- (SHAPE in bin/transcripts) together, and this file is run again.

create table if not exists public.messages (
  session_id text    not null check (session_id ~ '^[A-Za-z0-9._-]{1,100}$'),
  stream     text    not null check (length(stream) between 1 and 300),
  chunk_id   text    not null check (chunk_id ~ '^[0-9a-f]{64}$'),  -- the chunk the row was read from
  shape      integer not null check (shape >= 1),                   -- the version of the rule that read it
  line       integer not null check (line >= 1),                    -- the line's number in that chunk
  block      integer not null check (block >= 0),                   -- the block's place in the line
  at         timestamptz,                                           -- the line's own timestamp
  who        text    not null check (who in ('user', 'assistant', 'tool', 'context')),
  kind       text    not null check (kind in ('text', 'call', 'result')),
  tool       text    check (length(tool) <= 200),                   -- the tool called, on a call
  call_id    text    check (length(call_id) <= 200),                -- ties a result to its call
  failed     boolean not null default false,                        -- a result the tool marked an error
  side       boolean not null default false,                        -- a subagent's line kept inline
  text       text    not null check (length(text) <= 3000000),      -- redacted, as the chunk holds it
  created_at timestamptz not null default now(),
  primary key (session_id, stream, chunk_id, shape, line, block)
);

alter table public.messages enable row level security;
revoke all on public.messages from public, anon, authenticated;
grant insert on public.messages to anon;
grant all on public.messages to service_role;
drop policy if exists messages_insert on public.messages;
create policy messages_insert on public.messages for insert to anon with check (true);

-- Each session's text in order, from the copy `materialize` rebuilds: the index row it ranks first, and for
-- each stream the chain of chunks that row's tip ends. A session `materialize` would not write (a stream whose
-- name is no transcript's, or whose chain does not reach its root, or a session whose id begins with a dot)
-- is not shown at all. A stream with no chunk yet has its root for a tip, and is whole.
create or replace view public.transcript as
with recursive best as (
  select distinct on (s.session_id) s.session_id,
         case when r.ok then s.entry->'sent'->'streams' else '{}'::jsonb end as streams
  from public.sessions s
  -- a row can be read when its streams are an object and its version is a number or is not there
  cross join lateral (select coalesce(jsonb_typeof(s.entry->'sent'->'streams') = 'object', false)
                             and coalesce(jsonb_typeof(s.entry->'redaction_version'), 'null') in ('number', 'null') as ok) r
  order by s.session_id,
           r.ok desc,
           case when r.ok and jsonb_typeof(s.entry->'redaction_version') = 'number'
                then (s.entry->>'redaction_version')::numeric else 0 end desc,
           coalesce(s.entry->>'last_timestamp', '') collate "C" desc,
           (select coalesce(sum(case when jsonb_typeof(x.value->'bytes') = 'number' then (x.value->>'bytes')::numeric else 0 end), 0)
              from jsonb_each(case when r.ok then s.entry->'sent'->'streams' else '{}'::jsonb end) x) desc,
           s.version desc,
           s.row_id collate "C"
), tips as (
  select b.session_id, x.key as stream, x.value->>'tip' as tip,
         encode(sha256(convert_to(b.session_id || '/' || x.key, 'UTF8')), 'hex') as root,
         x.key ~ '^(?:main|subagents/(?!(?:.*/)?\.\.?(?:/|$))[A-Za-z0-9._/-]+)$' as named
  from best b cross join lateral jsonb_each(b.streams) x
), chain as (
  select t.session_id, t.stream, t.root, c.chunk_id, c.start_id, 1 as depth, array[c.chunk_id] as seen
  from tips t
  join public.chunks c on c.session_id = t.session_id and c.stream = t.stream and c.chunk_id = t.tip
  where t.named
  union all
  select c.session_id, c.stream, h.root, c.chunk_id, c.start_id, h.depth + 1, h.seen || c.chunk_id
  from chain h
  join public.chunks c on c.session_id = h.session_id and c.stream = h.stream and c.chunk_id = h.start_id
  where c.chunk_id <> all (h.seen)          -- a chain that comes back on itself stops, and never reaches its root
), whole as (
  select session_id, stream from chain where start_id = root
  union
  select session_id, stream from tips where named and tip = root
), written as (
  select b.session_id from best b
  where b.session_id !~ '^\.'
    and not exists (select 1 from tips t
                    where t.session_id = b.session_id
                      and not exists (select 1 from whole w    -- only a stream named as a transcript is ever whole
                                      where w.session_id = t.session_id and w.stream = t.stream))
)
select m.session_id, m.stream,
       row_number() over (partition by m.session_id, m.stream order by h.depth desc, m.line, m.block) as n,
       m.at, m.who, m.kind, m.tool, m.failed, m.side, m.text, m.call_id
from chain h
join written s on s.session_id = h.session_id
join public.messages m on m.session_id = h.session_id and m.stream = h.stream and m.chunk_id = h.chunk_id
where m.shape = 1;

revoke all on public.transcript from public, anon, authenticated;
grant select on public.transcript to service_role;
-- From PostgreSQL 15 a view can read as the one who asks, which is what Supabase's advisor wants of a view.
do $$ begin
  if current_setting('server_version_num')::int >= 150000 then
    execute 'alter view public.transcript set (security_invoker = true)';
  end if;
end $$;

-- ---- The probe loop's ledger (docs/plans/2026-11-24-probe-loop.md, Store) ----
--
-- One row per scored probe and one per review loop per probe, inserted by the probe-score
-- workflow (bin/probe-store) with the publishable key, after it scores a probe pull request.
-- Scoring a probe again is new rows under the new scorer run, never an update. The answer
-- key's own words (its terms, counterexample and false claim) stay in the sealed run
-- artifact; what is kept here is what the scores are read from.
--
-- The hooks' key (role `anon`) may INSERT into both and nothing else; reading them is the
-- read key's, for the weekly report and the improver.

create table if not exists public.probe_runs (
  probe_id    text    not null check (probe_id ~ '^probe-[0-9]{1,20}$'),  -- probe-<planter run>
  scorer_run  bigint  not null check (scorer_run > 0),
  pr          integer not null check (pr > 0),
  repository  text    not null check (repository ~ '^[A-Za-z0-9._-]{1,100}/[A-Za-z0-9._-]{1,100}$'),
  kind        text    not null check (length(kind) between 1 and 60),
  loud        boolean not null,
  file        text    not null check (length(file) between 1 and 300),
  first_line  integer not null check (first_line >= 1),
  last_line   integer not null check (last_line >= first_line),
  planted_sha text    not null check (planted_sha ~ '^[0-9a-f]{40}$'),
  caught      integer not null check (caught >= 0),
  ran         integer not null check (ran >= caught),  -- loops that ran: not "not run", "failed" or "no data"
  created_at  timestamptz not null default now(),
  primary key (probe_id, scorer_run)
);

create table if not exists public.probe_verdicts (
  probe_id   text   not null,
  scorer_run bigint not null,
  loop       text   not null check (loop in ('tests', 'properties', 'mutation', 'ocr', 'ci-diagnose', 'ci-fix', 'verify', 'property-scout')),
  verdict    text   not null check (verdict in ('caught', 'missed', 'not run', 'failed', 'no data', 'judge')),
  evidence   text   not null check (length(evidence) <= 2000),
  created_at timestamptz not null default now(),
  primary key (probe_id, scorer_run, loop),
  foreign key (probe_id, scorer_run) references public.probe_runs (probe_id, scorer_run)
);

alter table public.probe_runs     enable row level security;
alter table public.probe_verdicts enable row level security;
revoke all on public.probe_runs, public.probe_verdicts from public, anon, authenticated;
grant insert on public.probe_runs, public.probe_verdicts to anon;
grant all on public.probe_runs, public.probe_verdicts to service_role;
drop policy if exists probe_runs_insert on public.probe_runs;
drop policy if exists probe_verdicts_insert on public.probe_verdicts;
create policy probe_runs_insert on public.probe_runs for insert to anon with check (true);
create policy probe_verdicts_insert on public.probe_verdicts for insert to anon with check (true);


-- ---- The weekly report's functions (docs/plans/2026-11-24-probe-loop.md, Phase 2) ----
--
-- probe-report.yml writes the week's report to its run summary with the publishable key, which
-- may read no table. These functions are all it may call: they run as their owner with a fixed
-- search path and return aggregates, never a verdict's evidence. The report is not posted
-- where the review agents read.
--
-- Every one takes an optional repo, "owner/name" in any case, and returns a repository column
-- in that form, lower case: with no repo they cover every repository in the store, a row per
-- repository; with one, only it. probe_runs keeps "Owner/Name" and sessions keep
-- "github.com/owner/name"; repo_key below turns both into "owner/name".
--
-- probe_report_loops and probe_report_probes: totals per loop and an outline of the recent
-- probes, from each probe's latest scoring only.
--
-- agent_health and agent_refused_commands read the GitHub agents' sessions (source agent, named
-- gh-aw-<workflow>-<run>-<attempt> by bin/agent-session-collect) started since a time: per agent,
-- its runs, tool calls, calls its allowlist refused, and other tool errors; and the commands it
-- was refused, by their first line, cut to 100 characters, from the redacted text. A call is
-- counted once, however many chunks or shapes hold its rows.
--
-- skill_usage reads each session's latest index row: per skill (and its plugin, the part before
-- the colon), the sessions started since a time that used it, all that ever did, and all by
-- where they ran. skill_grades reads `scores`, one verdict per session and step, its latest
-- grading (fields/1, /2 and /3 are versions of one grader, so a re-grading replaces the verdict
-- rather than adding one): pass, fail and not applicable, and when the skill was last graded;
-- a grading whose session the store does not hold has no repository.
--
-- agent_refused_calls: the same refused calls as agent_refused_commands, one row each, newest
-- first, with the session they were in (so a run can be linked) and the command's first line cut
-- to 300 characters; at most max_rows (up to 2000).
--
-- session_effort: per agent (a GitHub agent's sessions) or, for the others, per source (local,
-- cloud, dispatch, eval), the sessions started since a time, how many carry effort counts
-- (transcripts archive counts them per stream from 2026-11-26), and their sums over all streams,
-- subagents included: model calls, input, output and cache tokens, tool calls, the characters of
-- text the assistant wrote and of what it posted through gh-aw's safe outputs, and the cost a
-- gh-aw run reported, with how many reported one. A count that is not a number is passed over.
-- A gh-aw run's tokens are the totals its result reported for the whole run (run_input,
-- run_output, run_cache_read, run_cache_write) where it has them: its per-message usage is
-- taken as each message starts, before its output.
--
-- The return types changed when the repository column came in, so the earlier versions are
-- dropped first; running the file again drops and makes them again, with their grants.

drop function if exists public.probe_report_loops();
drop function if exists public.probe_report_probes(integer);
drop function if exists public.agent_health(timestamptz);
drop function if exists public.agent_refused_commands(timestamptz, integer);
drop function if exists public.skill_usage(timestamptz);
drop function if exists public.skill_grades();
drop function if exists public.probe_report_loops(text);
drop function if exists public.probe_report_probes(integer, text);
drop function if exists public.agent_health(timestamptz, text);
drop function if exists public.agent_refused_commands(timestamptz, integer, text);
drop function if exists public.skill_usage(timestamptz, text);
drop function if exists public.skill_grades(text);
drop function if exists public.session_effort(timestamptz, text);
drop function if exists public.agent_refused_calls(timestamptz, integer, text);

create or replace function public.repo_key(repository text)
returns text
language sql immutable set search_path = public, pg_temp
as $$
  select nullif(regexp_replace(lower(coalesce(repository, '')), '^(https?://)?github\.com/', ''), '')
$$;

create function public.probe_report_loops(repo text default null)
returns table (repository text, loop text, probes bigint, caught bigint, missed bigint, not_run bigint,
               failed bigint, no_data bigint, judge bigint)
language sql stable security definer set search_path = public, pg_temp
as $$
  with latest as (
    select distinct on (r.probe_id) r.probe_id, r.scorer_run, public.repo_key(r.repository) as repository
    from public.probe_runs r
    where repo is null or public.repo_key(r.repository) = public.repo_key(repo)
    order by r.probe_id, r.scorer_run desc
  )
  select l.repository, v.loop, count(*),
         count(*) filter (where v.verdict = 'caught'),  count(*) filter (where v.verdict = 'missed'),
         count(*) filter (where v.verdict = 'not run'), count(*) filter (where v.verdict = 'failed'),
         count(*) filter (where v.verdict = 'no data'), count(*) filter (where v.verdict = 'judge')
  from public.probe_verdicts v join latest l on l.probe_id = v.probe_id and l.scorer_run = v.scorer_run
  group by l.repository, v.loop order by l.repository, v.loop
$$;

create function public.probe_report_probes(max_rows integer default 12, repo text default null)
returns table (repository text, probe_id text, pr integer, kind text, loud boolean, file text, caught integer,
               ran integer, scored_at timestamptz)
language sql stable security definer set search_path = public, pg_temp
as $$
  select * from (
    select distinct on (r.probe_id) public.repo_key(r.repository), r.probe_id, r.pr, r.kind, r.loud, r.file,
           r.caught, r.ran, r.created_at
    from public.probe_runs r
    where repo is null or public.repo_key(r.repository) = public.repo_key(repo)
    order by r.probe_id, r.scorer_run desc
  ) latest order by latest.created_at desc, latest.probe_id limit greatest(least(max_rows, 100), 0)
$$;

create function public.agent_health(since timestamptz, repo text default null)
returns table (repository text, agent text, runs bigint, calls bigint, refused bigint, errors bigint)
language sql stable security definer set search_path = public, pg_temp
as $$
  with runs as (
    select s.session_id, regexp_replace(s.session_id, '^gh-aw-(.*)-[0-9]+-[0-9]+$', '\1') as agent,
           public.repo_key(max(s.entry ->> 'repository')) as repository
    from public.sessions s where s.session_id ~ '^gh-aw-.+-[0-9]+-[0-9]+$'
    group by s.session_id having min(s.created_at) >= since
       and (repo is null or public.repo_key(max(s.entry ->> 'repository')) = public.repo_key(repo))
  ), calls as (
    select distinct m.session_id, m.call_id from public.messages m
    where m.kind = 'call' and m.call_id is not null and m.session_id in (select session_id from runs)
  ), bad as (
    select distinct on (m.session_id, m.call_id) m.session_id, m.call_id,
           m.text ~* '^Permission to use .* has been denied|not allowed' as refused
    from public.messages m
    where m.kind = 'result' and m.failed and m.call_id is not null and m.session_id in (select session_id from runs)
    order by m.session_id, m.call_id
  )
  select r.repository, r.agent, count(distinct r.session_id),
         (select count(*) from calls c join runs r2 using (session_id)
          where r2.agent = r.agent and r2.repository is not distinct from r.repository),
         (select count(*) from bad b join runs r2 using (session_id)
          where r2.agent = r.agent and r2.repository is not distinct from r.repository and b.refused),
         (select count(*) from bad b join runs r2 using (session_id)
          where r2.agent = r.agent and r2.repository is not distinct from r.repository and not b.refused)
  from runs r group by r.repository, r.agent order by r.repository, r.agent
$$;

create function public.agent_refused_commands(since timestamptz, max_rows integer default 10, repo text default null)
returns table (repository text, agent text, tool text, command text, times bigint)
language sql stable security definer set search_path = public, pg_temp
as $$
  with runs as (
    select s.session_id, regexp_replace(s.session_id, '^gh-aw-(.*)-[0-9]+-[0-9]+$', '\1') as agent,
           public.repo_key(max(s.entry ->> 'repository')) as repository
    from public.sessions s where s.session_id ~ '^gh-aw-.+-[0-9]+-[0-9]+$'
    group by s.session_id having min(s.created_at) >= since
       and (repo is null or public.repo_key(max(s.entry ->> 'repository')) = public.repo_key(repo))
  ), refused as (
    select distinct m.session_id, m.call_id from public.messages m
    where m.kind = 'result' and m.failed and m.text ~* '^Permission to use .* has been denied|not allowed'
      and m.session_id in (select session_id from runs)
  ), tried as (
    select distinct on (c.session_id, c.call_id) c.session_id, c.tool,
           left(replace(split_part(coalesce(substring(c.text from '"command": "((?:[^"\\]|\\.)*)"'), c.tool, '?'),
                                   '\n', 1), '\"', '"'), 100) as command
    from public.messages c join refused f on f.session_id = c.session_id and f.call_id = c.call_id
    where c.kind = 'call'
    order by c.session_id, c.call_id
  )
  select r.repository, r.agent, coalesce(t.tool, '?'), t.command, count(*)
  from tried t join runs r using (session_id)
  group by r.repository, r.agent, t.tool, t.command
  order by count(*) desc, r.repository, r.agent, t.command
  limit greatest(least(max_rows, 50), 0)
$$;

create function public.skill_usage(since timestamptz, repo text default null)
returns table (repository text, skill text, plugin text, sessions bigint, sessions_all bigint, local bigint,
               cloud bigint, agent bigint, dispatch bigint)
language sql stable security definer set search_path = public, pg_temp
as $$
  with latest as (
    select distinct on (s.session_id) s.session_id, s.entry,
           min(s.created_at) over (partition by s.session_id) as began
    from public.sessions s order by s.session_id, s.version desc, s.created_at desc
  ), used as (
    select distinct l.session_id, l.began, l.entry ->> 'source' as source, k ->> 'name' as skill,
           public.repo_key(l.entry ->> 'repository') as repository
    from latest l, jsonb_array_elements(case when jsonb_typeof(l.entry -> 'skills') = 'array'
                                             then l.entry -> 'skills' else '[]'::jsonb end) k
    where coalesce(k ->> 'name', '') <> ''
      and (repo is null or public.repo_key(l.entry ->> 'repository') = public.repo_key(repo))
  )
  select u.repository, u.skill, case when position(':' in u.skill) > 0 then split_part(u.skill, ':', 1) end,
         count(*) filter (where u.began >= since), count(*),
         count(*) filter (where u.source = 'local'), count(*) filter (where u.source = 'cloud'),
         count(*) filter (where u.source = 'agent'), count(*) filter (where u.source = 'dispatch')
  from used u group by u.repository, u.skill order by u.repository, count(*) desc, u.skill
$$;

create function public.skill_grades(repo text default null)
returns table (repository text, skill text, step text, sessions bigint, pass bigint, fail bigint,
               not_applicable bigint, last_graded timestamptz)
language sql stable security definer set search_path = public, pg_temp
as $$
  with sessions_repo as (
    select distinct on (s.session_id) s.session_id, public.repo_key(s.entry ->> 'repository') as repository
    from public.sessions s order by s.session_id, s.version desc, s.created_at desc
  ), latest as (
    select distinct on (g.session_id, g.step) g.session_id, g.step, g.skill, g.verdict, g.graded_at, sr.repository
    from public.scores g left join sessions_repo sr on sr.session_id = g.session_id
    where repo is null or sr.repository = public.repo_key(repo)
    order by g.session_id, g.step, g.graded_at desc, g.grader desc
  )
  select l.repository, l.skill, l.step, count(distinct l.session_id),
         count(*) filter (where l.verdict = 'pass'), count(*) filter (where l.verdict = 'fail'),
         count(*) filter (where l.verdict = 'not_applicable'), max(l.graded_at)
  from latest l group by l.repository, l.skill, l.step order by l.repository, l.skill, l.step
$$;

create function public.agent_refused_calls(since timestamptz, max_rows integer default 500, repo text default null)
returns table (repository text, agent text, session_id text, tool text, command text, at timestamptz)
language sql stable security definer set search_path = public, pg_temp
as $$
  with runs as (
    select s.session_id, regexp_replace(s.session_id, '^gh-aw-(.*)-[0-9]+-[0-9]+$', '\1') as agent,
           public.repo_key(max(s.entry ->> 'repository')) as repository
    from public.sessions s where s.session_id ~ '^gh-aw-.+-[0-9]+-[0-9]+$'
    group by s.session_id having min(s.created_at) >= since
       and (repo is null or public.repo_key(max(s.entry ->> 'repository')) = public.repo_key(repo))
  ), refused as (
    select distinct m.session_id, m.call_id from public.messages m
    where m.kind = 'result' and m.failed and m.text ~* '^Permission to use .* has been denied|not allowed'
      and m.session_id in (select session_id from runs)
  ), tried as (
    select distinct on (c.session_id, c.call_id) c.session_id, c.tool, c.at,
           left(replace(split_part(coalesce(substring(c.text from '"command": "((?:[^"\\]|\\.)*)"'), c.tool, '?'),
                                   '\n', 1), '\"', '"'), 300) as command
    from public.messages c join refused f on f.session_id = c.session_id and f.call_id = c.call_id
    where c.kind = 'call'
    order by c.session_id, c.call_id
  )
  select r.repository, r.agent, t.session_id, coalesce(t.tool, '?'), t.command, t.at
  from tried t join runs r using (session_id)
  order by t.at desc nulls last, t.session_id, t.command
  limit greatest(least(max_rows, 2000), 0)
$$;

create function public.session_effort(since timestamptz, repo text default null)
returns table (repository text, who text, sessions bigint, measured bigint, calls numeric, input_tokens numeric,
               output_tokens numeric, cache_read_tokens numeric, cache_write_tokens numeric, tool_calls numeric,
               text_chars numeric, posted_chars numeric, cost_usd numeric, costed bigint)
language sql stable security definer set search_path = public, pg_temp
as $$
  with latest as (
    select distinct on (s.session_id) s.session_id, s.entry,
           min(s.created_at) over (partition by s.session_id) as began
    from public.sessions s order by s.session_id, s.version desc, s.created_at desc
  ), picked as (
    select l.session_id, public.repo_key(l.entry ->> 'repository') as repository,
           case when l.session_id ~ '^gh-aw-.+-[0-9]+-[0-9]+$'
                then regexp_replace(l.session_id, '^gh-aw-(.*)-[0-9]+-[0-9]+$', '\1')
                else coalesce(l.entry ->> 'source', '?') end as who,
           case when jsonb_typeof(l.entry -> 'streams') = 'object' then l.entry -> 'streams' else '{}'::jsonb end as streams
    from latest l
    where l.began >= since and (repo is null or public.repo_key(l.entry ->> 'repository') = public.repo_key(repo))
  ), counts as (
    select p.session_id, p.repository, p.who, f.k, f.v
    from picked p, jsonb_each(p.streams) st(name, val),
         jsonb_each(case when jsonb_typeof(st.val -> 'effort') = 'object' then st.val -> 'effort' else '{}'::jsonb end) f(k, v)
    where jsonb_typeof(f.v) = 'number' and (f.v #>> '{}')::numeric >= 0
  ), per as (
    select p.session_id, p.repository, p.who,
           exists (select 1 from jsonb_each(p.streams) st(name, val) where jsonb_typeof(st.val -> 'effort') = 'object') as measured,
           (select sum((c.v #>> '{}')::numeric) from counts c where c.session_id = p.session_id and c.k = 'calls') as calls,
           coalesce((select sum((c.v #>> '{}')::numeric) from counts c where c.session_id = p.session_id and c.k = 'run_input'),
                    (select sum((c.v #>> '{}')::numeric) from counts c where c.session_id = p.session_id and c.k = 'input')) as input_tokens,
           coalesce((select sum((c.v #>> '{}')::numeric) from counts c where c.session_id = p.session_id and c.k = 'run_output'),
                    (select sum((c.v #>> '{}')::numeric) from counts c where c.session_id = p.session_id and c.k = 'output')) as output_tokens,
           coalesce((select sum((c.v #>> '{}')::numeric) from counts c where c.session_id = p.session_id and c.k = 'run_cache_read'),
                    (select sum((c.v #>> '{}')::numeric) from counts c where c.session_id = p.session_id and c.k = 'cache_read')) as cache_read,
           coalesce((select sum((c.v #>> '{}')::numeric) from counts c where c.session_id = p.session_id and c.k = 'run_cache_write'),
                    (select sum((c.v #>> '{}')::numeric) from counts c where c.session_id = p.session_id and c.k = 'cache_write')) as cache_write,
           (select sum((c.v #>> '{}')::numeric) from counts c where c.session_id = p.session_id and c.k = 'tool_calls') as tool_calls,
           (select sum((c.v #>> '{}')::numeric) from counts c where c.session_id = p.session_id and c.k = 'text_chars') as text_chars,
           (select sum((c.v #>> '{}')::numeric) from counts c where c.session_id = p.session_id and c.k = 'posted_chars') as posted_chars,
           (select sum((c.v #>> '{}')::numeric) from counts c where c.session_id = p.session_id and c.k = 'cost_usd') as cost_usd
    from picked p
  )
  select r.repository, r.who, count(*), count(*) filter (where r.measured),
         coalesce(sum(r.calls), 0), coalesce(sum(r.input_tokens), 0), coalesce(sum(r.output_tokens), 0),
         coalesce(sum(r.cache_read), 0), coalesce(sum(r.cache_write), 0), coalesce(sum(r.tool_calls), 0),
         coalesce(sum(r.text_chars), 0), coalesce(sum(r.posted_chars), 0),
         sum(r.cost_usd), count(*) filter (where r.cost_usd is not null)
  from per r group by r.repository, r.who order by r.repository, r.who
$$;

revoke all on function public.repo_key(text), public.probe_report_loops(text), public.probe_report_probes(integer, text),
  public.agent_health(timestamptz, text), public.agent_refused_commands(timestamptz, integer, text),
  public.skill_usage(timestamptz, text), public.skill_grades(text), public.session_effort(timestamptz, text),
  public.agent_refused_calls(timestamptz, integer, text) from public, anon, authenticated;
grant execute on function public.probe_report_loops(text), public.probe_report_probes(integer, text),
  public.agent_health(timestamptz, text), public.agent_refused_commands(timestamptz, integer, text),
  public.skill_usage(timestamptz, text), public.skill_grades(text), public.session_effort(timestamptz, text),
  public.agent_refused_calls(timestamptz, integer, text) to anon, service_role;
grant execute on function public.repo_key(text) to service_role;
