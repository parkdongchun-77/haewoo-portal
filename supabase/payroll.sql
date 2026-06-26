-- 실제 출퇴근 기반 월별 급여 집계 RPC (정규/OT/야간 분리). Supabase SQL Editor에 붙여넣어 실행.

-- 해당 날짜에 그 조가 야간(N) 근무인지 (2026-06-22 월요일 시작 주간회전, 일요일 휴무)
create or replace function haewoo_is_night(p_team text, p_date date) returns boolean
language sql immutable as $$
  select case
    when extract(dow from p_date)=0 then false
    when p_team in ('G1','G2','G3') then
      (array['M','A','N'])[ ((case p_team when 'G1' then 0 when 'G2' then 1 else 2 end)
        + (((floor((p_date - date '2026-06-22')/7)::int % 3)+3)%3)) % 3 + 1 ] = 'N'
    else false end;
$$;

-- 월별 직원 근무시간 집계 (분 단위): 총·정규(≤8h)·OT(>8h)·야간(스케줄 N일)
create or replace function haewoo_payroll_month(p_username text, p_passcode text, p_month text)
returns json language plpgsql security definer set search_path=public,extensions as $$
declare d0 date; d1 date;
begin
  if not haewoo_admin_ok(p_username,p_passcode) then return json_build_object('ok',false,'message','권한 없음'); end if;
  d0 := to_date(p_month||'-01','YYYY-MM-DD');
  d1 := (d0 + interval '1 month')::date;
  return json_build_object('ok',true,'month',p_month,'rows',(
    select coalesce(json_agg(r order by r.emp_no),'[]'::json) from (
      select e.emp_no, e.full_name, e.team, e.role,
        coalesce(count(p.wd),0) as work_days,
        coalesce(sum(p.work_min),0)::int as total_min,
        coalesce(sum(least(p.work_min,480)),0)::int as reg_min,
        coalesce(sum(greatest(p.work_min-480,0)),0)::int as ot_min,
        coalesce(sum(case when haewoo_is_night(e.team,p.wd) then p.work_min else 0 end),0)::int as night_min
      from haewoo_employee e
      left join (
        select a.employee_id, a.work_date as wd,
          (extract(epoch from (max(a.ts) filter (where a.kind='out')
                             - min(a.ts) filter (where a.kind='in')))/60)::int as work_min
        from haewoo_attendance a
        where a.work_date >= d0 and a.work_date < d1
        group by a.employee_id, a.work_date
        having min(a.ts) filter (where a.kind='in') is not null
           and max(a.ts) filter (where a.kind='out') is not null
      ) p on p.employee_id = e.id
      where e.active
      group by e.emp_no, e.full_name, e.team, e.role
    ) r ));
end;$$;
