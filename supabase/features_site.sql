-- 사업장(하노이/박닌) 분리: 직원 site, 사업장별 기준위치/방식(박닌=GPS25m, 하노이=QR)
-- Supabase SQL Editor에 붙여넣어 Run.

-- 1) 직원 사업장 (기존 전원 박닌)
alter table haewoo_employee add column if not exists site text not null default '박닌';

-- 2) 사업장 설정 (method: gps=좌표+반경, qr=QR스캔·거리체크 없음)
create table if not exists haewoo_site_location(
  site text primary key,
  method text not null default 'gps',
  name text,
  lat double precision, lng double precision, radius_m int default 25,
  updated_at timestamptz default now()
);
insert into haewoo_site_location(site,method,name,lat,lng,radius_m)
  select '박닌','gps', coalesce((select name from haewoo_work_location where id=1),'박닌 사업장'),
         (select lat from haewoo_work_location where id=1),
         (select lng from haewoo_work_location where id=1),
         coalesce((select radius_m from haewoo_work_location where id=1),25)
  on conflict (site) do nothing;
insert into haewoo_site_location(site,method,name,radius_m)
  values('하노이','gps','하노이 사업장',25)
  on conflict (site) do nothing;

-- 3) 사업장 설정 조회/저장
create or replace function haewoo_site_locations(p_username text,p_passcode text)
returns json language plpgsql security definer set search_path=public,extensions as $$
begin
  if not haewoo_admin_ok(p_username,p_passcode) then return json_build_object('ok',false,'message','권한 없음'); end if;
  return json_build_object('ok',true,'rows',(
    select coalesce(json_agg(json_build_object('site',site,'method',method,'name',name,'lat',lat,'lng',lng,'radius_m',radius_m) order by site),'[]'::json)
    from haewoo_site_location));
end;$$;

create or replace function haewoo_set_site_location(p_username text,p_passcode text,p_site text,p_method text default null,p_lat double precision default null,p_lng double precision default null,p_radius int default null,p_name text default null)
returns json language plpgsql security definer set search_path=public,extensions as $$
begin
  if not haewoo_admin_ok(p_username,p_passcode) then return json_build_object('ok',false,'message','권한 없음'); end if;
  insert into haewoo_site_location(site,method,name,lat,lng,radius_m)
    values(p_site,coalesce(p_method,'gps'),p_name,p_lat,p_lng,coalesce(p_radius,25))
  on conflict (site) do update set
    method=coalesce(p_method,haewoo_site_location.method),
    name=coalesce(p_name,haewoo_site_location.name),
    lat=coalesce(p_lat,haewoo_site_location.lat),
    lng=coalesce(p_lng,haewoo_site_location.lng),
    radius_m=coalesce(p_radius,haewoo_site_location.radius_m),
    updated_at=now();
  return json_build_object('ok',true);
end;$$;

-- 4) checkin: 직원 사업장 방식에 따라 (gps=25m, qr=거리체크 생략)
create or replace function haewoo_checkin(p_token text,p_kind text,p_lat double precision,p_lng double precision,p_phone text default null)
returns json language plpgsql security definer set search_path=public,extensions as $$
declare e haewoo_employee; sl haewoo_site_location; d double precision;
begin
  if p_kind not in ('in','out') then return json_build_object('ok',false,'message','잘못된 요청'); end if;
  select * into e from haewoo_employee where qr_token=p_token and active;
  if not found then return json_build_object('ok',false,'message','유효하지 않은 QR입니다.'); end if;
  select * into sl from haewoo_site_location where site=e.site;
  if not found then return json_build_object('ok',false,'message','사업장 설정이 없습니다.'); end if;
  if p_phone is not null and (e.phone is null or e.phone='') then update haewoo_employee set phone=p_phone where id=e.id; end if;
  if sl.method='gps' then
    if sl.lat is null then return json_build_object('ok',false,'message','기준 위치가 설정되지 않았습니다.'); end if;
    d := haewoo_dist_m(p_lat,p_lng,sl.lat,sl.lng);
    if d > sl.radius_m then return json_build_object('ok',false,'message','회사 반경 '||sl.radius_m||'m 밖입니다 (현재 약 '||round(d)||'m).','distance_m',round(d)); end if;
    insert into haewoo_attendance(employee_id,kind,lat,lng,distance_m,source) values(e.id,p_kind,p_lat,p_lng,round(d),'qr');
    return json_build_object('ok',true,'kind',p_kind,'distance_m',round(d),'ts',now(),'full_name',e.full_name);
  else
    insert into haewoo_attendance(employee_id,kind,lat,lng,distance_m,source) values(e.id,p_kind,p_lat,p_lng,null,'qr');
    return json_build_object('ok',true,'kind',p_kind,'ts',now(),'full_name',e.full_name);
  end if;
end;$$;

-- 5) 대시보드 본인 출퇴근: 사업장 방식 분기(규칙: 출근1회·퇴근은 출근후·여러번)
create or replace function haewoo_self_punch(p_username text,p_passcode text,p_kind text,p_lat double precision,p_lng double precision)
returns json language plpgsql security definer set search_path=public,extensions as $$
declare a haewoo_admin; e haewoo_employee; sl haewoo_site_location; d double precision; today date; has_in boolean;
begin
  select * into a from haewoo_admin where username=p_username;
  if not found or a.pass_hash <> crypt(p_passcode,a.pass_hash) then return json_build_object('ok',false,'message','권한 없음'); end if;
  if a.emp_no is null then return json_build_object('ok',false,'message','이 계정에 연결된 직원이 없습니다.'); end if;
  select * into e from haewoo_employee where emp_no=a.emp_no and active limit 1;
  if not found then return json_build_object('ok',false,'message','연결된 직원을 찾을 수 없습니다.'); end if;
  if p_kind not in ('in','out') then return json_build_object('ok',false,'message','잘못된 요청'); end if;

  today := (now() at time zone 'Asia/Ho_Chi_Minh')::date;
  has_in := exists(select 1 from haewoo_attendance where employee_id=e.id and kind='in' and work_date=today);
  if p_kind='in' and has_in then return json_build_object('ok',false,'message','이미 출근 처리되었습니다 (수정 불가).'); end if;
  if p_kind='out' and not has_in then return json_build_object('ok',false,'message','먼저 출근을 눌러 주세요.'); end if;

  select * into sl from haewoo_site_location where site=e.site;
  if not found then return json_build_object('ok',false,'message','사업장 설정이 없습니다.'); end if;
  if sl.method='gps' then
    if sl.lat is null then return json_build_object('ok',false,'message','기준 위치가 설정되지 않았습니다.'); end if;
    d := haewoo_dist_m(p_lat,p_lng,sl.lat,sl.lng);
    if d > sl.radius_m then return json_build_object('ok',false,'message','회사 반경 '||sl.radius_m||'m 밖입니다 (현재 약 '||round(d)||'m).','distance_m',round(d)); end if;
    insert into haewoo_attendance(employee_id,kind,lat,lng,distance_m,source) values(e.id,p_kind,p_lat,p_lng,round(d),'dashboard');
    return json_build_object('ok',true,'kind',p_kind,'distance_m',round(d),'ts',now());
  else
    insert into haewoo_attendance(employee_id,kind,lat,lng,distance_m,source) values(e.id,p_kind,p_lat,p_lng,null,'dashboard');
    return json_build_object('ok',true,'kind',p_kind,'ts',now());
  end if;
end;$$;

-- 6) 조회 RPC에 site 추가
create or replace function haewoo_roster(p_username text,p_passcode text,p_date date default null)
returns json language plpgsql security definer set search_path=public,extensions as $$
declare d date;
begin
  if not haewoo_admin_ok(p_username,p_passcode) then return json_build_object('ok',false,'message','권한 없음'); end if;
  d := coalesce(p_date,(now() at time zone 'Asia/Ho_Chi_Minh')::date);
  return json_build_object('ok',true,'date',d,'rows',(
    select coalesce(json_agg(r order by r.emp_no),'[]'::json) from (
      select e.emp_no,e.full_name,e.team,e.role,e.phone,e.site,
        (select ts from haewoo_attendance a where a.employee_id=e.id and a.kind='in' and a.work_date=d order by ts asc limit 1) as in_ts,
        (select ts from haewoo_attendance a where a.employee_id=e.id and a.kind='out' and a.work_date=d order by ts desc limit 1) as out_ts
      from haewoo_employee e where e.active) r));
end;$$;

create or replace function haewoo_employee_all(p_username text,p_passcode text)
returns json language plpgsql security definer set search_path=public,extensions as $$
begin
  if not haewoo_admin_ok(p_username,p_passcode) then return json_build_object('ok',false,'message','권한 없음'); end if;
  return json_build_object('ok',true,'rows',(
    select coalesce(json_agg(json_build_object('emp_no',emp_no,'full_name',full_name,'team',team,'role',role,'gender',gender,'email',email,'site',site,'active',active,'phone',phone) order by emp_no),'[]'::json)
    from haewoo_employee));
end;$$;

create or replace function haewoo_qr_list(p_username text,p_passcode text)
returns json language plpgsql security definer set search_path=public,extensions as $$
begin
  if not haewoo_admin_ok(p_username,p_passcode) then return json_build_object('ok',false,'message','권한 없음'); end if;
  return json_build_object('ok',true,'rows',(
    select coalesce(json_agg(json_build_object('emp_no',emp_no,'full_name',full_name,'team',team,'role',role,'site',site,'token',qr_token) order by emp_no),'[]'::json)
    from haewoo_employee where active));
end;$$;

create or replace function haewoo_get_employee(p_token text)
returns json language plpgsql security definer set search_path=public,extensions as $$
declare e haewoo_employee; last_row haewoo_attendance; sl haewoo_site_location;
begin
  select * into e from haewoo_employee where qr_token=p_token and active;
  if not found then return json_build_object('ok',false,'message','유효하지 않은 QR입니다.'); end if;
  select * into last_row from haewoo_attendance where employee_id=e.id order by ts desc limit 1;
  select * into sl from haewoo_site_location where site=e.site;
  return json_build_object('ok',true,'emp_no',e.emp_no,'full_name',e.full_name,'team',e.team,'role',e.role,'phone',e.phone,'site',e.site,'method',coalesce(sl.method,'gps'),'last_kind',last_row.kind,'last_ts',last_row.ts);
end;$$;

-- 7) 직원 등록/수정에 site 추가
create or replace function haewoo_employee_upsert(p_username text,p_passcode text,p_emp_no int,p_full_name text,p_team text,p_role text,p_gender text,p_email text default null,p_site text default '박닌')
returns json language plpgsql security definer set search_path=public,extensions as $$
begin
  if not haewoo_admin_ok(p_username,p_passcode) then return json_build_object('ok',false,'message','권한 없음'); end if;
  if coalesce(trim(p_full_name),'')='' then return json_build_object('ok',false,'message','이름은 필수입니다.'); end if;
  insert into haewoo_employee(emp_no,full_name,team,role,gender,email,site)
    values(p_emp_no,p_full_name,p_team,p_role,p_gender,nullif(trim(p_email),''),coalesce(nullif(trim(p_site),''),'박닌'))
  on conflict (emp_no) do update set full_name=excluded.full_name,team=excluded.team,role=excluded.role,gender=excluded.gender,email=excluded.email,site=excluded.site;
  return json_build_object('ok',true);
end;$$;

-- 8) 급여 RPC에 site 추가 (사업장 필터용)
create or replace function haewoo_payroll_month(p_username text, p_passcode text, p_month text)
returns json language plpgsql security definer set search_path=public,extensions as $$
declare d0 date; d1 date; y0 date;
begin
  if not haewoo_admin_ok(p_username,p_passcode) then return json_build_object('ok',false,'message','권한 없음'); end if;
  d0 := to_date(p_month||'-01','YYYY-MM-DD'); d1 := (d0 + interval '1 month')::date; y0 := date_trunc('year',d0)::date;
  return json_build_object('ok',true,'month',p_month,'rows',(
    select coalesce(json_agg(r order by r.emp_no),'[]'::json) from (
      select e.emp_no, e.full_name, e.team, e.role, e.site,
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
      group by e.emp_no, e.full_name, e.team, e.role, e.site, e.id
    ) r ));
end;$$;
