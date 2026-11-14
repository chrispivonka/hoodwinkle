-- Hoodwinkle multiplayer schema (Neon Postgres).
-- Players have no accounts. Each browser keeps a random secret token; the
-- database stores only its SHA-256 hash and hands back a random public id.
-- The API connects as the low-privilege role hw_api, which can't touch the
-- tables at all: its only way in is the security-definer functions below,
-- which validate every write. RLS with no policies is a second lock.

create extension if not exists pgcrypto;

create table public.hw_players (
  id uuid primary key default gen_random_uuid(),
  token_hash text not null unique,
  created_at timestamptz not null default now()
);

create table public.hw_plays (
  player_id uuid not null references public.hw_players(id) on delete cascade,
  day date not null,
  q smallint not null check (q between 0 and 2),
  lie text check (char_length(lie) between 2 and 40),
  status text not null check (status in ('ok', 'close')),
  pick text check (pick ~ '^(t|s[0-3]|u:[0-9a-f-]{36})$'),
  shown text[] check (shown is null or cardinality(shown) <= 6),
  created_at timestamptz not null default now(),
  picked_at timestamptz,
  primary key (player_id, day, q)
);
create index hw_plays_day_idx on public.hw_plays (day);

alter table public.hw_players enable row level security;
alter table public.hw_plays enable row level security;
revoke all on public.hw_players, public.hw_plays from public;

-- Returns the caller's public id, creating the player on first visit.
create or replace function public.hw_player(p_token text)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_hash text;
  v_id uuid;
begin
  if p_token is null or char_length(p_token) < 32 or char_length(p_token) > 128 then
    raise exception 'invalid token';
  end if;
  v_hash := encode(public.digest(p_token, 'sha256'), 'hex');
  insert into public.hw_players (token_hash) values (v_hash)
    on conflict (token_hash) do nothing;
  select id into v_id from public.hw_players where token_hash = v_hash;
  return v_id;
end $$;

create or replace function public.hw_submit_lie(p_token text, p_day date, p_q int, p_lie text, p_close boolean)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_id uuid := public.hw_player(p_token);
  v_lie text := btrim(p_lie);
begin
  if p_day not between (now() at time zone 'utc')::date - 1 and (now() at time zone 'utc')::date + 1 then
    raise exception 'that puzzle is closed';
  end if;
  if v_lie ~* '(f+u+c+k|sh[i1]t|c+u+n+t|b[i1]tch|n[i1]gg|f[a@]gg|r[e3]t[a@]rd|wh[o0]re|sl[u]t|k[i1]ke|ch[i1]nk|tr[a@]nn|r[a@]p(e|ist)|n[a@]z[i1]|https?:|www\.)' then
    raise exception 'lie rejected';
  end if;
  insert into public.hw_plays (player_id, day, q, lie, status, pick, picked_at)
  values (v_id, p_day, p_q, v_lie,
          case when p_close then 'close' else 'ok' end,
          case when p_close then 't' end,
          case when p_close then now() end)
  on conflict (player_id, day, q) do nothing;
end $$;

create or replace function public.hw_submit_pick(p_token text, p_day date, p_q int, p_pick text, p_shown text[])
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_id uuid := public.hw_player(p_token);
begin
  if p_pick = 'u:' || v_id::text then
    raise exception 'you cannot pick your own lie';
  end if;
  update public.hw_plays
     set pick = p_pick, shown = p_shown, picked_at = now()
   where player_id = v_id and day = p_day and q = p_q and pick is null;
end $$;

-- Everything a client needs for one day: every player's lies and picks for
-- that day (keyed by public id, never the token), plus how many people the
-- caller's lies fooled on each of the last seven days.
create or replace function public.hw_day(p_token text, p_day date)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_id uuid := public.hw_player(p_token);
  v_players jsonb;
  v_history jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object('id', player_id, 'q', qs)), '[]'::jsonb)
    into v_players
    from (
      select player_id,
             jsonb_agg(jsonb_build_object('q', q, 'lie', lie, 'status', status, 'pick', pick, 'shown', shown) order by q) as qs
        from public.hw_plays
       where day = p_day
       group by player_id
       limit 5000
    ) t;

  select coalesce(jsonb_object_agg(day, fooled), '{}'::jsonb)
    into v_history
    from (
      select day, count(*) as fooled
        from public.hw_plays
       where pick = 'u:' || v_id::text
         and day >= p_day - 7
       group by day
    ) h;

  return jsonb_build_object('me', v_id, 'players', v_players, 'history', v_history);
end $$;

revoke all on function public.hw_player(text) from public;
revoke all on function public.hw_submit_lie(text, date, int, text, boolean) from public;
revoke all on function public.hw_submit_pick(text, date, int, text, text[]) from public;
revoke all on function public.hw_day(text, date) from public;

-- hw_api is created separately (it needs a password); these grants are all it gets.
grant execute on function public.hw_submit_lie(text, date, int, text, boolean) to hw_api;
grant execute on function public.hw_submit_pick(text, date, int, text, text[]) to hw_api;
grant execute on function public.hw_day(text, date) to hw_api;
