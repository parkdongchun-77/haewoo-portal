-- 근태 고도화(B): 교대시간 헬퍼 + 공휴일 + 직원관리 + 강화 급여집계(휴일·지각·조퇴·연OT)
-- Supabase SQL Editor에 전체 붙여넣어 Run. (이전 payroll.sql 내용을 포함·갱신함)

-- 교대 코드 (M주간/A오후/N야간, 일요일 null=휴무). 지원조는 주간(M) Mon-Sat.
create or replace function haewoo_shift_code(p_team text, p_date date) returns text
language sql immutable as $$
  select case
    when extract(dow from p_date)=0 then null
    when p_team='지원' then 'M'
    when p_team in ('G1','G2','G3') then
      (array['M','A','N'])[ ((case p_team when 'G1' then 0 when 'G2' then 1 else 2 end)
        + (((floor((p_date - date '2026-06-22')/7)::int % 3)+3)%3)) % 3 + 1 ]
    else null end;
$$;

create or replace function haewoo_is_night(p_team text, p_date date) returns boolean
language sql immutable as $$ select haewoo_shift_code(p_team,p_date)='N'; $$;

create or replace function haewoo_shift_start(p_team text, p_date date) returns timestamptz
language sql immutable as $$
  select case haewoo_shift_code(p_team,p_date)
    when 'M' then (p_date::text||' 06:00')::timestamp at time zone 'Asia/Ho_Chi_Minh'
    when 'A' then (p_date::text||' 14:00')::timestamp at time zone 'Asia/Ho_Chi_Minh'
    when 'N' then (p_date::text||' 22:00')::timestamp at time zone 'Asia/Ho_Chi_Minh'
    else null end;
$$;
create or replace function haewoo_shift_end(p_team text, p_date date) returns timestamptz
language sql immutable as $$
  select case haewoo_shift_code(p_team,p_date)
    when 'M' then (p_date::text||' 14:00')::timestamp at time zone 'Asia/Ho_Chi_Minh'
    when 'A' then (p_date::text||' 22:00')::timestamp at time zone 'Asia/Ho_Chi_Minh'
    when 'N' then ((p_date+1)::text||' 06:00')::timestamp at time zone 'Asia/Ho_Chi_Minh'
    else null end;
$$;

-- 공휴일 (베트남 2026, 음력 Tết은 근사치 — 필요시 수정)
create table if not exists haewoo_holiday(d date primary key, name text);
alter table haewoo_holiday enable row level security;
drop policy if exists holiday_read on haewoo_holiday;
create policy holiday_read on haewoo_holiday for select to anon using (true);
insert into haewoo_holiday(d,name) values
('2026-01-01','Tết Dương lịch (신정)'),
('2026-02-16','Tết Nguyên đán'),('2026-02-17','Tết Nguyên đán (Mùng 1)'),('2026-02-18','Tết Nguyên đán'),('2026-02-19','Tết Nguyên đán'),('2026-02-20','Tết Nguyên đán'),
('2026-04-26','Giỗ Tổ Hùng Vương'),
('2026-04-30','Ngày Giải phóng (통일절)'),
('2026-05-01','Quốc tế Lao động (노동절)'),
('2026-09-02','Quốc khánh (건국절)')
on conflict (d) do nothing;

-- 직원 관리: 추가/수정(upsert), 활성/비활성, 전체목록(비활성 포함)
create or replace function haewoo_employee_upsert(p_username text,p_passcode text,p_emp_no int,p_full_name text,p_team text,p_role text,p_gender text)
returns json language plpgsql security definer set search_path=public,extensions as $$
begin
  if not haewoo_admin_ok(p_username,p_passcode) then return json_build_object('ok',false,'message','권한 없음'); end if;
  if coalesce(trim(p_full_name),'')='' then return json_build_object('ok',false,'message','이름은 필수입니다.'); end if;
  insert into haewoo_employee(emp_no,full_name,team,role,gender)
    values(p_emp_no,p_full_name,p_team,p_role,p_gender)
  on conflict (emp_no) do update set full_name=excluded.full_name,team=excluded.team,role=excluded.role,gender=excluded.gender;
  return json_build_object('ok',true);
end;$$;

create or replace function haewoo_employee_set_active(p_username text,p_passcode text,p_emp_no int,p_active boolean)
returns json language plpgsql security definer set search_path=public,extensions as $$
begin
  if not haewoo_admin_ok(p_username,p_passcode) then return json_build_object('ok',false,'message','권한 없음'); end if;
  update haewoo_employee set active=p_active where emp_no=p_emp_no;
  return json_build_object('ok',true);
end;$$;

create or replace function haewoo_employee_all(p_username text,p_passcode text)
returns json language plpgsql security definer set search_path=public,extensions as $$
begin
  if not haewoo_admin_ok(p_username,p_passcode) then return json_build_object('ok',false,'message','권한 없음'); end if;
  return json_build_object('ok',true,'rows',(
    select coalesce(json_agg(json_build_object('emp_no',emp_no,'full_name',full_name,'team',team,'role',role,'gender',gender,'active',active,'phone',phone) order by emp_no),'[]'::json)
    from haewoo_employee));
end;$$;

-- 강화 급여집계: 정규/OT/야간 + 휴일근무분 + 지각/조퇴(분) + 연누적 OT(한도 경고용)
create or replace function haewoo_payroll_month(p_username text, p_passcode text, p_month text)
returns json language plpgsql security definer set search_path=public,extensions as $$
declare d0 date; d1 date; y0 date;
begin
  if not haewoo_admin_ok(p_username,p_passcode) then return json_build_object('ok',false,'message','권한 없음'); end if;
  d0 := to_date(p_month||'-01','YYYY-MM-DD'); d1 := (d0 + interval '1 month')::date; y0 := date_trunc('year',d0)::date;
  return json_build_object('ok',true,'month',p_month,'rows',(
    select coalesce(json_agg(r order by r.emp_no),'[]'::json) from (
      select e.emp_no, e.full_name, e.team, e.role,
        coalesce(count(p.wd),0) as work_days,
        coalesce(sum(p.work_min),0)::int as total_min,
        coalesce(sum(least(p.work_min,480)),0)::int as reg_min,
        coalesce(sum(greatest(p.work_min-480,0)),0)::int as ot_min,
        coalesce(sum(case when haewoo_is_night(e.team,p.wd) then p.work_min else 0 end),0)::int as night_min,
        coalesce(sum(case when h.d is not null then p.work_min else 0 end),0)::int as holiday_min,
        coalesce(sum(p.late_min),0)::int as late_min,
        coalesce(sum(p.early_min),0)::int as early_min,
        coalesce((select sum(greatest(yp.work_min-480,0))::int from (
            select a.work_date,
              (extract(epoch from (max(a.ts) filter(where a.kind='out') - min(a.ts) filter(where a.kind='in')))/60)::int work_min
            from haewoo_attendance a where a.employee_id=e.id and a.work_date>=y0 and a.work_date<d1
            group by a.work_date
            having min(a.ts) filter(where a.kind='in') is not null and max(a.ts) filter(where a.kind='out') is not null
          ) yp),0) as ytd_ot_min
      from haewoo_employee e
      left join (
        select a.employee_id, a.work_date as wd,
          (extract(epoch from (max(a.ts) filter(where a.kind='out') - min(a.ts) filter(where a.kind='in')))/60)::int as work_min,
          greatest(0, extract(epoch from (min(a.ts) filter(where a.kind='in') - haewoo_shift_start(e2.team,a.work_date)))/60)::int as late_min,
          greatest(0, extract(epoch from (haewoo_shift_end(e2.team,a.work_date) - max(a.ts) filter(where a.kind='out')))/60)::int as early_min
        from haewoo_attendance a join haewoo_employee e2 on e2.id=a.employee_id
        where a.work_date>=d0 and a.work_date<d1
        group by a.employee_id, a.work_date, e2.team
        having min(a.ts) filter(where a.kind='in') is not null and max(a.ts) filter(where a.kind='out') is not null
      ) p on p.employee_id = e.id
      left join haewoo_holiday h on h.d = p.wd
      where e.active
      group by e.emp_no, e.full_name, e.team, e.role, e.id
    ) r ));
end;$$;
