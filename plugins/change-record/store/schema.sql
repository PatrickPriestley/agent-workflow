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
