-- Player reports, timed-mode picks and a less trigger-happy word filter.

-- Reports: one per reporter per lie. A lie with 3 or more reports is hidden
-- from everyone except its author; a lie you reported is hidden from you.
create table public.hw_reports (
  reporter uuid not null references public.hw_players(id) on delete cascade,
  player_id uuid not null references public.hw_players(id) on delete cascade,
  day date not null,
  q smallint not null check (q between 0 and 2),
  created_at timestamptz not null default now(),
  primary key (reporter, player_id, day, q)
);
create index hw_reports_lie_idx on public.hw_reports (day, player_id, q);
alter table public.hw_reports enable row level security;
revoke all on public.hw_reports from public;

-- Timed mode: 'x' means the timer ran out before the player picked.
alter table public.hw_plays drop constraint hw_plays_pick_check;
alter table public.hw_plays add constraint hw_plays_pick_check
  check (pick ~ '^(t|x|s[0-3]|u:[0-9a-f-]{36})$');

create or replace function public.hw_report(p_token text, p_day date, p_q int, p_player uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_id uuid := public.hw_player(p_token);
begin
  if p_player = v_id then
    raise exception 'you cannot report your own lie';
  end if;
  if p_q not between 0 and 2 then
    raise exception 'bad question';
  end if;
  if not exists (select 1 from public.hw_plays where player_id = p_player and day = p_day and q = p_q and status = 'ok') then
    raise exception 'no such lie';
  end if;
  insert into public.hw_reports (reporter, player_id, day, q)
  values (v_id, p_player, p_day, p_q)
  on conflict do nothing;
end $$;

-- Word boundaries (\y) so words like "grape" and "Scunthorpe" get through.
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
  if v_lie ~* '(f+u+c+k|\ysh[i1]t|\yc+u+n+t|b[i1]tch|n[i1]gg|f[a@]gg|r[e3]t[a@]rd|wh[o0]re|\ysl[u]t|\yk[i1]ke|\ych[i1]nk|tr[a@]nn[iy]|\yr[a@]p(e|ist)\y|\yn[a@]z[i1]|https?:|www\.)' then
    raise exception 'lie rejected';
  end if;
  insert into public.hw_plays (player_id, day, q, lie, status, pick, picked_at)
  values (v_id, p_day, p_q, v_lie,
          case when p_close then 'close' else 'ok' end,
          case when p_close then 't' end,
          case when p_close then now() end)
  on conflict (player_id, day, q) do nothing;
end $$;

-- Same as before, but reported lies are blanked out (lie = null, status =
-- 'hidden') for everyone except their author.
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
      select p.player_id,
             jsonb_agg(jsonb_build_object(
               'q', p.q,
               'lie', case when hid.hidden then null else p.lie end,
               'status', case when hid.hidden then 'hidden' else p.status end,
               'pick', p.pick,
               'shown', p.shown) order by p.q) as qs
        from public.hw_plays p
        cross join lateral (
          select p.player_id <> v_id and p.status = 'ok' and (
                   (select count(*) from public.hw_reports r
                     where r.day = p.day and r.player_id = p.player_id and r.q = p.q) >= 3
                   or exists (select 1 from public.hw_reports r
                     where r.day = p.day and r.player_id = p.player_id and r.q = p.q and r.reporter = v_id)
                 ) as hidden
        ) hid
       where p.day = p_day
       group by p.player_id
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

revoke all on function public.hw_report(text, date, int, uuid) from public;
grant execute on function public.hw_report(text, date, int, uuid) to hw_api;
