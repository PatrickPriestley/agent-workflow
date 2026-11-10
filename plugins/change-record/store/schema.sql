-- The transcript store for `transcripts push` and `transcripts materialize`
-- (record docs/changes/2026-11-09-skill-transcripts.md, task 2).
--
-- Run once in the Supabase project's SQL editor. It is safe to run again: it creates what is
-- missing and resets every grant and policy to what is written here.
--
-- Keys:
--   * The publishable key (role `anon`) is the hooks' key. It may INSERT into `chunks` and
--     `sessions` and nothing else: no SELECT, UPDATE, DELETE or TRUNCATE, and no access to
--     `scores`. A duplicate insert is refused with 409 (23505) and changes nothing; `push`
--     counts that as already stored. `Prefer: resolution=ignore-duplicates` is not used: it is
--     ON CONFLICT DO NOTHING, which needs SELECT (probed: 401, 42501).
--   * The secret key (role `service_role`) is the read key, kept on the owner's machine:
--     `materialize` reads with it, and grading (tasks 3 and 4) writes `scores` with it.
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

alter table public.chunks   enable row level security;
alter table public.sessions enable row level security;
alter table public.scores   enable row level security;

-- Supabase grants every privilege on new public tables to anon and authenticated by default;
-- take them all back, then give the hooks' role INSERT alone.
revoke all on public.chunks, public.sessions, public.scores from public, anon, authenticated;
grant insert on public.chunks, public.sessions to anon;
grant all on public.chunks, public.sessions, public.scores to service_role;

drop policy if exists chunks_insert on public.chunks;
drop policy if exists sessions_insert on public.sessions;
create policy chunks_insert on public.chunks for insert to anon with check (true);
create policy sessions_insert on public.sessions for insert to anon with check (true);
-- No SELECT, UPDATE or DELETE policy exists for anon or authenticated, and no privilege either.
-- service_role bypasses row-level security.
