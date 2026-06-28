-- 대시보드에서 본인 출퇴근(오늘 현황 본인 행 버튼) + 계정↔직원 연결
-- 규칙: 출근 1회(수정불가), 퇴근은 출근 후에만·여러번(마지막값), 고정좌표 25m
-- Supabase SQL Editor에 붙여넣어 Run.

alter table haewoo_admin add column if not exists emp_no int;
update haewoo_admin set emp_no=12407769 where username='karmadc';

-- 로그인 RPC가 연결된 emp_no도 반환
create or replace function haewoo_admin_login(p_username text,p_passcode text)
returns json language plpgsql security definer set search_path=public,extensions as $$
declare a haewoo_admin;
begin
  select * into a from haewoo_admin where username=p_username;
  if not found or a.pass_hash <> crypt(p_passcode,a.pass_hash) then return json_build_object('ok',false,'message','아이디 또는 비밀번호가 올바르지 않습니다.'); end if;
  return json_build_object('ok',true,'username',a.username,'name',a.name,'level',a.level,'emp_no',a.emp_no);
end;$$;

-- 본인 출퇴근. 계정의 emp_no로 직원을 찾아 규칙 적용 후 기록
create or replace function haewoo_self_punch(p_username text,p_passcode text,p_kind text,p_lat double precision,p_lng double precision)
returns json language plpgsql security definer set search_path=public,extensions as $$
declare a haewoo_admin; e haewoo_employee; loc haewoo_work_location; d double precision; today date; has_in boolean;
begin
  select * into a from haewoo_admin where username=p_username;
  if not found or a.pass_hash <> crypt(p_passcode,a.pass_hash) then return json_build_object('ok',false,'message','권한 없음'); end if;
  if a.emp_no is null then return json_build_object('ok',false,'message','이 계정에 연결된 직원이 없습니다.'); end if;
  select * into e from haewoo_employee where emp_no=a.emp_no and active limit 1;
  if not found then return json_build_object('ok',false,'message','연결된 직원을 찾을 수 없습니다.'); end if;
  if p_kind not in ('in','out') then return json_build_object('ok',false,'message','잘못된 요청'); end if;

  today := (now() at time zone 'Asia/Ho_Chi_Minh')::date;
  has_in := exists(select 1 from haewoo_attendance where employee_id=e.id and kind='in' and work_date=today);

  -- 출근은 하루 한 번(수정 불가), 퇴근은 출근 후에만
  if p_kind='in' and has_in then return json_build_object('ok',false,'message','이미 출근 처리되었습니다 (수정 불가).'); end if;
  if p_kind='out' and not has_in then return json_build_object('ok',false,'message','먼저 출근을 눌러 주세요.'); end if;

  select * into loc from haewoo_work_location where id=1;
  if not found then return json_build_object('ok',false,'message','기준 위치가 설정되지 않았습니다.'); end if;
  d := haewoo_dist_m(p_lat,p_lng,loc.lat,loc.lng);
  if d > loc.radius_m then
    return json_build_object('ok',false,'message','회사 반경 '||loc.radius_m||'m 밖입니다 (현재 약 '||round(d)||'m).','distance_m',round(d));
  end if;

  insert into haewoo_attendance(employee_id,kind,lat,lng,distance_m,source) values(e.id,p_kind,p_lat,p_lng,round(d),'dashboard');
  return json_build_object('ok',true,'kind',p_kind,'distance_m',round(d),'ts',now());
end;$$;
