-- 출퇴근 이력 기간 조회: 직원·일자별 출근(첫 in)/퇴근(마지막 out) 1행으로 집계
-- Supabase SQL Editor에 붙여넣어 Run.

create or replace function haewoo_attendance_range(p_username text,p_passcode text,p_from date,p_to date)
returns json language plpgsql security definer set search_path=public,extensions as $$
begin
  if not haewoo_admin_ok(p_username,p_passcode) then return json_build_object('ok',false,'message','권한 없음'); end if;
  return json_build_object('ok',true,'rows',(
    select coalesce(json_agg(r order by r.work_date desc, r.emp_no),'[]'::json) from (
      select e.emp_no, e.full_name, e.team, e.site, a.work_date,
        min(a.ts) filter(where a.kind='in')  as in_ts,
        max(a.ts) filter(where a.kind='out') as out_ts
      from haewoo_attendance a join haewoo_employee e on e.id=a.employee_id
      where a.work_date>=p_from and a.work_date<=p_to
      group by e.emp_no, e.full_name, e.team, e.site, a.work_date
    ) r));
end;$$;
