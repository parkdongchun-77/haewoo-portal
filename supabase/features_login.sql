-- 소셜 로그인 ↔ 직원 매칭(관리자 사전 입력 이메일) + 개발자 karmadc = Master
-- Supabase SQL Editor에 붙여넣어 Run. (비밀번호 없음 — 안전)

alter table haewoo_employee add column if not exists email text;
create index if not exists idx_emp_email on haewoo_employee((lower(email)));

-- 소셜 로그인 이메일 → 직원 자동 매칭 (개인 QR 토큰 반환)
create or replace function haewoo_employee_by_email(p_email text)
returns json language plpgsql security definer set search_path=public,extensions as $$
declare e haewoo_employee;
begin
  if coalesce(trim(p_email),'')='' then return json_build_object('ok',false); end if;
  select * into e from haewoo_employee where lower(email)=lower(trim(p_email)) and active limit 1;
  if not found then return json_build_object('ok',false,'message','등록되지 않은 계정입니다. 관리자에게 등록을 요청하세요.'); end if;
  return json_build_object('ok',true,'emp_no',e.emp_no,'full_name',e.full_name,'team',e.team,'role',e.role,'token',e.qr_token);
end;$$;

-- 직원 등록/수정에 email 추가 (관리자가 사전 입력)
create or replace function haewoo_employee_upsert(p_username text,p_passcode text,p_emp_no int,p_full_name text,p_team text,p_role text,p_gender text,p_email text default null)
returns json language plpgsql security definer set search_path=public,extensions as $$
begin
  if not haewoo_admin_ok(p_username,p_passcode) then return json_build_object('ok',false,'message','권한 없음'); end if;
  if coalesce(trim(p_full_name),'')='' then return json_build_object('ok',false,'message','이름은 필수입니다.'); end if;
  insert into haewoo_employee(emp_no,full_name,team,role,gender,email)
    values(p_emp_no,p_full_name,p_team,p_role,p_gender,nullif(trim(p_email),''))
  on conflict (emp_no) do update set full_name=excluded.full_name,team=excluded.team,role=excluded.role,gender=excluded.gender,email=excluded.email;
  return json_build_object('ok',true);
end;$$;

create or replace function haewoo_employee_all(p_username text,p_passcode text)
returns json language plpgsql security definer set search_path=public,extensions as $$
begin
  if not haewoo_admin_ok(p_username,p_passcode) then return json_build_object('ok',false,'message','권한 없음'); end if;
  return json_build_object('ok',true,'rows',(
    select coalesce(json_agg(json_build_object('emp_no',emp_no,'full_name',full_name,'team',team,'role',role,'gender',gender,'email',email,'active',active,'phone',phone) order by emp_no),'[]'::json)
    from haewoo_employee));
end;$$;

-- 개발자 karmadc → Master(전체 권한). 이미 존재(full_setup.sql)하므로 레벨만 승격.
update haewoo_admin set level='master', name='개발자 (Master)' where username='karmadc';
