-- Haewoo 포털 초기 스키마. 프로필/역할, 근태(위치 기준점·기록), 수책 데이터 테이블 + RLS
-- Supabase SQL Editor 또는 `supabase db push`로 적용한다.

-- =========================================================
-- 1) 프로필 + 역할 (auth.users 연동)
-- =========================================================
create table if not exists public.profiles (
  id uuid primary key references auth.users on delete cascade,
  email text,
  full_name text,
  role text not null default 'employee',   -- employee | manager | admin
  created_at timestamptz default now()
);
alter table public.profiles enable row level security;

create policy "profiles self or manager read" on public.profiles
  for select using (
    auth.uid() = id
    or exists (select 1 from public.profiles p where p.id = auth.uid() and p.role in ('admin','manager'))
  );
create policy "profiles self update" on public.profiles
  for update using (auth.uid() = id);

-- 가입 시 프로필 자동 생성
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email, full_name)
  values (new.id, new.email, coalesce(new.raw_user_meta_data->>'full_name', ''));
  return new;
end; $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users for each row execute function public.handle_new_user();

-- =========================================================
-- 2) 근태 — 위치 기준점(V2 창고) + 출퇴근 기록
-- =========================================================
create table if not exists public.work_location (
  id bigint generated always as identity primary key,
  name text not null default 'Samsung Display Vietnam - V2 Warehouse',
  lat double precision not null,
  lng double precision not null,
  radius_m double precision not null default 25,  -- GPS 정확도 고려 25m
  updated_by uuid references auth.users,
  updated_at timestamptz default now()
);
alter table public.work_location enable row level security;

create policy "work_location read (authenticated)" on public.work_location
  for select using (auth.role() = 'authenticated');
create policy "work_location admin manage" on public.work_location
  for all using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.role in ('admin','manager')))
  with check (exists (select 1 from public.profiles p where p.id = auth.uid() and p.role in ('admin','manager')));

create table if not exists public.attendance (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users on delete cascade,
  kind text not null check (kind in ('in','out')),   -- 출근 in / 퇴근 out
  lat double precision,
  lng double precision,
  distance_m double precision,                        -- 기준점까지 거리(m)
  within boolean,                                     -- 반경 이내 여부
  created_at timestamptz default now()
);
alter table public.attendance enable row level security;

create policy "attendance self or manager read" on public.attendance
  for select using (
    auth.uid() = user_id
    or exists (select 1 from public.profiles p where p.id = auth.uid() and p.role in ('admin','manager'))
  );
create policy "attendance self insert" on public.attendance
  for insert with check (auth.uid() = user_id);

-- =========================================================
-- 3) 수책(Liquidation) 데이터 — ECUS 템플릿 기반
-- =========================================================
create table if not exists public.sucbaek_matching (
  id bigint generated always as identity primary key,
  internal_code text, custom_code text, type text,
  internal_unit text, custom_unit text, unit_rate double precision default 1
);
create table if not exists public.sucbaek_bom (
  id bigint generated always as identity primary key,
  product_code text, material_code text, usage_norm double precision,
  loss_rate double precision, hs_code text
);
create table if not exists public.sucbaek_stock (
  id bigint generated always as identity primary key,
  category text, item_code text, base_date text, qty double precision, unit text, type text
);
create table if not exists public.sucbaek_destroy (
  id bigint generated always as identity primary key,
  item_code text, type text, qty double precision
);
create table if not exists public.sucbaek_customs (
  id bigint generated always as identity primary key,
  item_code text, direction text, qty double precision
);

alter table public.sucbaek_matching enable row level security;
alter table public.sucbaek_bom      enable row level security;
alter table public.sucbaek_stock    enable row level security;
alter table public.sucbaek_destroy  enable row level security;
alter table public.sucbaek_customs  enable row level security;

-- 1차: 인증 사용자면 읽기·쓰기 허용(추후 회사/역할 단위로 강화)
do $$
declare t text;
begin
  foreach t in array array['sucbaek_matching','sucbaek_bom','sucbaek_stock','sucbaek_destroy','sucbaek_customs']
  loop
    execute format('create policy "%1$s rw" on public.%1$s for all using (auth.role()=''authenticated'') with check (auth.role()=''authenticated'');', t);
  end loop;
end $$;
