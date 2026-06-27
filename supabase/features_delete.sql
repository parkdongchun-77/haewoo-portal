-- 직원 삭제(목록 제거) + 본인 출퇴근 기록 함께 보관 DB로 이전 후 원본 삭제
-- Supabase SQL Editor에 붙여넣어 Run. (FK: 출퇴근→직원 이라 기록도 함께 처리)

create table if not exists haewoo_employee_archive(
  id uuid, emp_no int, full_name text, team text, role text, gender text, phone text, email text,
  qr_token text, active boolean, created_at timestamptz,
  archived_at timestamptz default now(), archived_by text
);

create table if not exists haewoo_attendance_archive(
  id uuid, employee_id uuid, emp_no int, kind text, ts timestamptz, work_date date,
  lat double precision, lng double precision, distance_m numeric, source text,
  archived_at timestamptz default now()
);

-- 직원 + 출퇴근 기록을 보관 테이블로 복사한 뒤 원본에서 삭제
create or replace function haewoo_employee_delete(p_username text,p_passcode text,p_emp_no int)
returns json language plpgsql security definer set search_path=public,extensions as $$
declare e haewoo_employee;
begin
  if not haewoo_admin_ok(p_username,p_passcode) then return json_build_object('ok',false,'message','권한 없음'); end if;
  select * into e from haewoo_employee where emp_no=p_emp_no limit 1;
  if not found then return json_build_object('ok',false,'message','대상 직원이 없습니다.'); end if;

  insert into haewoo_attendance_archive(id,employee_id,emp_no,kind,ts,work_date,lat,lng,distance_m,source)
    select a.id,a.employee_id,e.emp_no,a.kind,a.ts,a.work_date,a.lat,a.lng,a.distance_m,a.source
    from haewoo_attendance a where a.employee_id=e.id;
  delete from haewoo_attendance where employee_id=e.id;

  insert into haewoo_employee_archive(id,emp_no,full_name,team,role,gender,phone,email,qr_token,active,created_at,archived_by)
    values(e.id,e.emp_no,e.full_name,e.team,e.role,e.gender,e.phone,e.email,e.qr_token,e.active,e.created_at,p_username);
  delete from haewoo_employee where id=e.id;

  return json_build_object('ok',true);
end;$$;

-- 보관된 직원 조회 (나중에 열람용)
create or replace function haewoo_employee_archive_all(p_username text,p_passcode text)
returns json language plpgsql security definer set search_path=public,extensions as $$
begin
  if not haewoo_admin_ok(p_username,p_passcode) then return json_build_object('ok',false,'message','권한 없음'); end if;
  return json_build_object('ok',true,'rows',(
    select coalesce(json_agg(json_build_object('emp_no',emp_no,'full_name',full_name,'team',team,'role',role,'email',email,'archived_at',archived_at,'archived_by',archived_by) order by archived_at desc),'[]'::json)
    from haewoo_employee_archive));
end;$$;
