-- 코드 듀얼 Supabase 스키마
-- Supabase 대시보드 > SQL Editor 에 통째로 붙여 넣고 Run 하세요. 여러 번 실행해도 안전합니다.

-- ===== 테이블 =====
create table if not exists public.settings (
  id int primary key default 1 check (id = 1),
  lang text not null default 'py' check (lang in ('py','js')),
  minutes int not null default 10 check (minutes in (3,5,10)),
  disabled text[] not null default '{}'
);
insert into public.settings (id) values (1) on conflict (id) do nothing;

-- 학급 입장 코드: 학생은 읽을 수 없고, 함수가 대신 확인합니다.
create table if not exists public.class_secret (
  id int primary key default 1 check (id = 1),
  join_code text not null default ''
);
insert into public.class_secret (id) values (1) on conflict (id) do nothing;

-- 교사로 인정할 이메일 목록 (Supabase Auth 계정 이메일과 같아야 합니다)
create table if not exists public.teachers (
  email text primary key
);

create table if not exists public.students (
  sid text primary key check (sid ~ '^[0-9]{4,10}$'),
  nick text not null default '' check (char_length(nick) <= 10),
  mon text,
  owned text[] not null default '{}',
  rating int not null default 1000,
  wins int not null default 0,
  draws int not null default 0,
  losses int not null default 0,
  history jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 교사가 만든 문제 (data 에 문제 전체가 JSON 으로 들어갑니다)
create table if not exists public.problems (
  id text primary key,
  lang text not null check (lang in ('py','js')),
  diff text not null check (diff in ('하','중','상')),
  data jsonb not null,
  created_at timestamptz not null default now()
);

-- ===== 권한 확인 함수 =====
create or replace function public.is_teacher() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.teachers t where lower(t.email) = lower(coalesce(auth.jwt() ->> 'email', '')));
$$;

create or replace function public.check_code(p_code text) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select join_code from public.class_secret where id = 1), '') in ('', coalesce(trim(p_code), ''));
$$;

-- ===== RLS =====
alter table public.settings enable row level security;
alter table public.class_secret enable row level security;
alter table public.teachers enable row level security;
alter table public.students enable row level security;
alter table public.problems enable row level security;

drop policy if exists settings_read on public.settings;
create policy settings_read on public.settings for select using (true);
drop policy if exists settings_write on public.settings;
create policy settings_write on public.settings for update using (public.is_teacher()) with check (public.is_teacher());

drop policy if exists secret_read on public.class_secret;
create policy secret_read on public.class_secret for select using (public.is_teacher());
drop policy if exists secret_write on public.class_secret;
create policy secret_write on public.class_secret for update using (public.is_teacher()) with check (public.is_teacher());

drop policy if exists students_read on public.students;
create policy students_read on public.students for select using (true);
drop policy if exists students_delete on public.students;
create policy students_delete on public.students for delete using (public.is_teacher());

drop policy if exists problems_read on public.problems;
create policy problems_read on public.problems for select using (true);
drop policy if exists problems_insert on public.problems;
create policy problems_insert on public.problems for insert with check (public.is_teacher());
drop policy if exists problems_update on public.problems;
create policy problems_update on public.problems for update using (public.is_teacher()) with check (public.is_teacher());
drop policy if exists problems_delete on public.problems;
create policy problems_delete on public.problems for delete using (public.is_teacher());
-- teachers 테이블에는 정책이 없으므로 브라우저에서는 읽거나 쓸 수 없습니다.

-- ===== 학생용 함수 (학생은 테이블에 직접 쓰지 못하고 이 함수로만 기록합니다) =====
create or replace function public.student_login(p_sid text, p_code text) returns public.students
language plpgsql security definer set search_path = public as $$
declare s public.students;
begin
  if p_sid !~ '^[0-9]{4,10}$' then raise exception 'bad_sid'; end if;
  if not public.check_code(p_code) then raise exception 'bad_code'; end if;
  insert into public.students (sid) values (p_sid) on conflict (sid) do nothing;
  select * into s from public.students where sid = p_sid;
  return s;
end $$;

create or replace function public.student_set_profile(p_sid text, p_code text, p_nick text, p_mon text) returns public.students
language plpgsql security definer set search_path = public as $$
declare s public.students; v_owned text[];
begin
  if not public.check_code(p_code) then raise exception 'bad_code'; end if;
  select * into s from public.students where sid = p_sid for update;
  if not found then raise exception 'no_student'; end if;
  v_owned := s.owned;
  if s.mon is null then
    if p_mon not in ('loop','stack','bit','bug') then raise exception 'bad_mon'; end if;
  elsif not (p_mon = any(v_owned)) then
    raise exception 'bad_mon';
  end if;
  if not (p_mon = any(v_owned)) then v_owned := array_append(v_owned, p_mon); end if;
  update public.students set nick = left(coalesce(trim(p_nick), ''), 10), mon = p_mon, owned = v_owned, updated_at = now()
    where sid = p_sid returning * into s;
  return s;
end $$;

-- 경기 결과 정산: 점수 계산은 서버에서 합니다.
create or replace function public.student_finish_match(
  p_sid text, p_code text, p_opp_name text, p_opp_rating int, p_score numeric, p_how text, p_me_hp int, p_opp_hp int
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  s public.students; v_k int; v_e numeric; v_delta int; v_before int; v_after int; v_res text;
  v_hist jsonb; v_owned text[]; v_new text[] := '{}';
begin
  if not public.check_code(p_code) then raise exception 'bad_code'; end if;
  if p_score not in (0, 0.5, 1) then raise exception 'bad_score'; end if;
  if p_opp_rating < 0 or p_opp_rating > 3000 then raise exception 'bad_opp'; end if;
  select * into s from public.students where sid = p_sid for update;
  if not found then raise exception 'no_student'; end if;

  v_k := case when s.wins + s.draws + s.losses < 10 then 40 else 32 end;
  v_e := 1 / (1 + power(10::numeric, (p_opp_rating - s.rating)::numeric / 400));
  v_delta := round(v_k * (p_score - v_e));
  if p_score = 1 then v_delta := greatest(v_delta, 6) + case when p_how = 'KO' then 4 else 0 end; end if;
  if p_score = 0 then v_delta := least(v_delta, -6); end if;
  v_before := s.rating;
  v_after := greatest(0, s.rating + v_delta);
  v_res := case when p_score = 1 then '승' when p_score = 0 then '패' else '무' end;

  v_hist := jsonb_build_array(jsonb_build_object(
    'opp', left(p_opp_name, 20), 'res', v_res, 'how', left(p_how, 20),
    'me', p_me_hp, 'op', p_opp_hp, 'delta', v_after - v_before, 'at', now())) || s.history;
  if jsonb_array_length(v_hist) > 20 then
    select jsonb_agg(e order by i) into v_hist from jsonb_array_elements(v_hist) with ordinality t(e, i) where i <= 20;
  end if;

  update public.students set
    rating = v_after,
    wins = wins + (p_score = 1)::int,
    draws = draws + (p_score = 0.5)::int,
    losses = losses + (p_score = 0)::int,
    history = v_hist,
    updated_at = now()
  where sid = p_sid returning * into s;

  v_owned := s.owned;
  if s.wins >= 1 and not ('sort' = any(v_owned)) then v_owned := array_append(v_owned, 'sort'); v_new := array_append(v_new, 'sort'); end if;
  if s.wins >= 3 and not ('recur' = any(v_owned)) then v_owned := array_append(v_owned, 'recur'); v_new := array_append(v_new, 'recur'); end if;
  if array_length(v_new, 1) > 0 then
    update public.students set owned = v_owned where sid = p_sid returning * into s;
  end if;

  return jsonb_build_object('student', to_jsonb(s), 'before', v_before, 'after', v_after, 'new_mons', to_jsonb(v_new));
end $$;

create or replace function public.am_i_teacher() returns boolean
language sql stable security definer set search_path = public as $$ select public.is_teacher(); $$;

revoke all on function public.student_login(text, text) from public;
revoke all on function public.student_set_profile(text, text, text, text) from public;
revoke all on function public.student_finish_match(text, text, text, int, numeric, text, int, int) from public;
grant execute on function public.student_login(text, text) to anon, authenticated;
grant execute on function public.student_set_profile(text, text, text, text) to anon, authenticated;
grant execute on function public.student_finish_match(text, text, text, int, numeric, text, int, int) to anon, authenticated;
grant execute on function public.am_i_teacher() to anon, authenticated;
grant execute on function public.is_teacher() to anon, authenticated;
revoke all on function public.check_code(text) from public;
revoke all on function public.check_code(text) from anon, authenticated;
