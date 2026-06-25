-- 근태 교대 모델 확장. 직원/조, 교대 스케줄, 출퇴근 상태, 연장근로(베트남 노동법) 집계 기반
-- 베트남 노동법: 연장근로 한도 월 40시간 · 연 200시간(수출가공 등 예외 승인 시 연 300시간)

-- 직원 (auth.users와 선택적 연결. 사번/조/직무)
create table if not exists public.employees (
  id bigint generated always as identity primary key,
  emp_no text unique not null,                 -- 사번 (예: W001)
  full_name text not null,
  team text,                                   -- 조: A / B / C
  position text,
  user_id uuid references auth.users on delete set null,
  active boolean not null default true,
  created_at timestamptz default now()
);

-- 교대 패턴 정의(주간/야간/휴무 시간)
create table if not exists public.shift_type (
  code text primary key,                       -- DAY / NIGHT / OFF
  name text not null,                          -- 주간 / 야간 / 휴무
  start_time time,
  end_time time,
  hours numeric default 12,
  night_hours numeric default 0               -- 야간 가산 시간(22:00~06:00)
);
insert into public.shift_type(code,name,start_time,end_time,hours,night_hours) values
  ('DAY','주간','08:00','20:00',12,0),
  ('NIGHT','야간','20:00','08:00',12,8),
  ('OFF','휴무',null,null,0,0)
on conflict (code) do nothing;

-- 일자별 조 교대 스케줄(교대표). 3조 2교대 12일 주기
create table if not exists public.shift_schedule (
  id bigint generated always as identity primary key,
  work_date date not null,
  team text not null,                          -- A / B / C
  shift_code text not null references public.shift_type(code),
  unique (work_date, team)
);

-- 출퇴근 기록 확장(위치 + 교대 + 상태)
alter table public.attendance add column if not exists employee_id bigint references public.employees(id) on delete cascade;
alter table public.attendance add column if not exists work_date date;
alter table public.attendance add column if not exists shift_code text references public.shift_type(code);
alter table public.attendance add column if not exists status text;      -- 정상 / 지각 / 결근 / 휴무
alter table public.attendance add column if not exists work_minutes integer; -- 근무시간(분)

-- 월별 연장근로 집계 뷰(노동법 한도 점검용)
create or replace view public.v_overtime_month as
select e.id as employee_id, e.emp_no, e.full_name, e.team,
       date_trunc('month', a.created_at)::date as month,
       round(greatest(sum(coalesce(a.work_minutes,0))/60.0 - 0, 0)::numeric, 1) as total_hours
from public.employees e
left join public.attendance a on a.employee_id = e.id and a.kind='out'
group by e.id, e.emp_no, e.full_name, e.team, date_trunc('month', a.created_at);

-- RLS
alter table public.employees enable row level security;
alter table public.shift_type enable row level security;
alter table public.shift_schedule enable row level security;

create policy "employees read auth" on public.employees for select using (auth.role()='authenticated');
create policy "employees admin manage" on public.employees for all
  using (exists(select 1 from public.profiles p where p.id=auth.uid() and p.role in('admin','manager')))
  with check (exists(select 1 from public.profiles p where p.id=auth.uid() and p.role in('admin','manager')));
create policy "shift_type read auth" on public.shift_type for select using (auth.role()='authenticated');
create policy "shift_schedule read auth" on public.shift_schedule for select using (auth.role()='authenticated');
create policy "shift_schedule admin manage" on public.shift_schedule for all
  using (exists(select 1 from public.profiles p where p.id=auth.uid() and p.role in('admin','manager')))
  with check (exists(select 1 from public.profiles p where p.id=auth.uid() and p.role in('admin','manager')));
