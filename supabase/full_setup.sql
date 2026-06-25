-- 해우비나 포털 전체 백엔드 설치 (근태 + 해우봇 + 견적). Supabase SQL Editor에 붙여넣어 실행.
create extension if not exists pgcrypto with schema extensions;

-- ========== 근태 ==========
create table if not exists haewoo_work_location(
  id int primary key default 1 check (id=1),
  name text not null default 'V2 Warehouse (Samsung Display Vietnam)',
  lat double precision not null,
  lng double precision not null,
  radius_m int not null default 25,
  updated_at timestamptz default now()
);

create table if not exists haewoo_employee(
  id uuid primary key default gen_random_uuid(),
  emp_no int unique,
  full_name text not null,
  team text not null,
  role text not null,
  gender text,
  phone text,
  qr_token text unique not null default encode(extensions.gen_random_bytes(9),'hex'),
  active boolean not null default true,
  created_at timestamptz default now()
);

create table if not exists haewoo_attendance(
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references haewoo_employee(id),
  kind text not null check (kind in ('in','out')),
  ts timestamptz not null default now(),
  work_date date not null default (now() at time zone 'Asia/Ho_Chi_Minh')::date,
  lat double precision, lng double precision,
  distance_m numeric,
  source text default 'qr'
);
create index if not exists idx_att_date on haewoo_attendance(work_date);
create index if not exists idx_att_emp on haewoo_attendance(employee_id, ts);

create table if not exists haewoo_shift(
  code text primary key, name text not null, start_time time not null, end_time time not null, sort int
);

create table if not exists haewoo_admin(
  username text primary key, pass_hash text not null, name text, level text not null default 'manager'
);

-- ========== 해우봇 ==========
create table if not exists haewoo_bot_chat(
  id uuid primary key default gen_random_uuid(),
  session_id text, role text not null check (role in ('user','bot')),
  message text not null, matched_topic text, lang text, created_at timestamptz not null default now()
);
create index if not exists idx_bot_created on haewoo_bot_chat(created_at);

create table if not exists haewoo_bot_faq(
  topic text not null, lang text not null, answer text not null, primary key (topic, lang)
);

-- ========== 견적 ==========
create table if not exists haewoo_quote(
  id uuid primary key default gen_random_uuid(),
  company text, name text, phone text, email text,
  origin text, destination text, message text,
  lang text, status text not null default 'new', created_at timestamptz not null default now()
);
create index if not exists idx_quote_created on haewoo_quote(created_at);

-- ========== RLS ==========
alter table haewoo_employee enable row level security;
alter table haewoo_attendance enable row level security;
alter table haewoo_work_location enable row level security;
alter table haewoo_admin enable row level security;
alter table haewoo_shift enable row level security;
alter table haewoo_bot_chat enable row level security;
alter table haewoo_bot_faq enable row level security;
alter table haewoo_quote enable row level security;
drop policy if exists shift_read on haewoo_shift;
create policy shift_read on haewoo_shift for select to anon using (true);

-- ========== RPC: 근태 ==========
create or replace function haewoo_dist_m(lat1 double precision,lng1 double precision,lat2 double precision,lng2 double precision)
returns double precision language sql immutable as $$
  select 2*6371000*asin(sqrt(power(sin(radians(lat2-lat1)/2),2)+cos(radians(lat1))*cos(radians(lat2))*power(sin(radians(lng2-lng1)/2),2)));
$$;

create or replace function haewoo_get_employee(p_token text)
returns json language plpgsql security definer set search_path=public,extensions as $$
declare e haewoo_employee; last_row haewoo_attendance;
begin
  select * into e from haewoo_employee where qr_token=p_token and active;
  if not found then return json_build_object('ok',false,'message','유효하지 않은 QR입니다.'); end if;
  select * into last_row from haewoo_attendance where employee_id=e.id order by ts desc limit 1;
  return json_build_object('ok',true,'emp_no',e.emp_no,'full_name',e.full_name,'team',e.team,'role',e.role,'phone',e.phone,'last_kind',last_row.kind,'last_ts',last_row.ts);
end;$$;

create or replace function haewoo_checkin(p_token text,p_kind text,p_lat double precision,p_lng double precision,p_phone text default null)
returns json language plpgsql security definer set search_path=public,extensions as $$
declare e haewoo_employee; loc haewoo_work_location; d double precision;
begin
  if p_kind not in ('in','out') then return json_build_object('ok',false,'message','잘못된 요청'); end if;
  select * into e from haewoo_employee where qr_token=p_token and active;
  if not found then return json_build_object('ok',false,'message','유효하지 않은 QR입니다.'); end if;
  select * into loc from haewoo_work_location where id=1;
  if not found then return json_build_object('ok',false,'message','기준 위치가 설정되지 않았습니다.'); end if;
  d := haewoo_dist_m(p_lat,p_lng,loc.lat,loc.lng);
  if d > loc.radius_m then
    return json_build_object('ok',false,'message','회사 반경 '||loc.radius_m||'m 밖입니다 (현재 약 '||round(d)||'m).','distance_m',round(d));
  end if;
  if p_phone is not null and (e.phone is null or e.phone='') then update haewoo_employee set phone=p_phone where id=e.id; end if;
  insert into haewoo_attendance(employee_id,kind,lat,lng,distance_m) values(e.id,p_kind,p_lat,p_lng,round(d));
  return json_build_object('ok',true,'kind',p_kind,'distance_m',round(d),'ts',now(),'full_name',e.full_name);
end;$$;

create or replace function haewoo_admin_ok(p_username text,p_passcode text) returns boolean
language sql security definer set search_path=public,extensions as $$
  select exists(select 1 from haewoo_admin where username=p_username and pass_hash=crypt(p_passcode,pass_hash));
$$;

create or replace function haewoo_admin_login(p_username text,p_passcode text)
returns json language plpgsql security definer set search_path=public,extensions as $$
declare a haewoo_admin;
begin
  select * into a from haewoo_admin where username=p_username;
  if not found or a.pass_hash <> crypt(p_passcode,a.pass_hash) then return json_build_object('ok',false,'message','아이디 또는 비밀번호가 올바르지 않습니다.'); end if;
  return json_build_object('ok',true,'username',a.username,'name',a.name,'level',a.level);
end;$$;

create or replace function haewoo_roster(p_username text,p_passcode text,p_date date default null)
returns json language plpgsql security definer set search_path=public,extensions as $$
declare d date;
begin
  if not haewoo_admin_ok(p_username,p_passcode) then return json_build_object('ok',false,'message','권한 없음'); end if;
  d := coalesce(p_date,(now() at time zone 'Asia/Ho_Chi_Minh')::date);
  return json_build_object('ok',true,'date',d,'rows',(
    select coalesce(json_agg(r order by r.emp_no),'[]'::json) from (
      select e.emp_no,e.full_name,e.team,e.role,e.phone,
        (select ts from haewoo_attendance a where a.employee_id=e.id and a.kind='in' and a.work_date=d order by ts asc limit 1) as in_ts,
        (select ts from haewoo_attendance a where a.employee_id=e.id and a.kind='out' and a.work_date=d order by ts desc limit 1) as out_ts
      from haewoo_employee e where e.active) r));
end;$$;

create or replace function haewoo_attendance_log(p_username text,p_passcode text,p_date date default null)
returns json language plpgsql security definer set search_path=public,extensions as $$
declare d date;
begin
  if not haewoo_admin_ok(p_username,p_passcode) then return json_build_object('ok',false,'message','권한 없음'); end if;
  d := coalesce(p_date,(now() at time zone 'Asia/Ho_Chi_Minh')::date);
  return json_build_object('ok',true,'rows',(
    select coalesce(json_agg(json_build_object('emp_no',e.emp_no,'full_name',e.full_name,'team',e.team,'kind',a.kind,'ts',a.ts,'distance_m',a.distance_m) order by a.ts desc),'[]'::json)
    from haewoo_attendance a join haewoo_employee e on e.id=a.employee_id where a.work_date=d));
end;$$;

create or replace function haewoo_set_location(p_username text,p_passcode text,p_lat double precision,p_lng double precision,p_radius int default null,p_name text default null)
returns json language plpgsql security definer set search_path=public,extensions as $$
begin
  if not haewoo_admin_ok(p_username,p_passcode) then return json_build_object('ok',false,'message','권한 없음'); end if;
  insert into haewoo_work_location(id,name,lat,lng,radius_m) values(1,coalesce(p_name,'V2 Warehouse'),p_lat,p_lng,coalesce(p_radius,25))
  on conflict (id) do update set lat=excluded.lat,lng=excluded.lng,radius_m=coalesce(p_radius,haewoo_work_location.radius_m),name=coalesce(p_name,haewoo_work_location.name),updated_at=now();
  return json_build_object('ok',true);
end;$$;

create or replace function haewoo_qr_list(p_username text,p_passcode text)
returns json language plpgsql security definer set search_path=public,extensions as $$
begin
  if not haewoo_admin_ok(p_username,p_passcode) then return json_build_object('ok',false,'message','권한 없음'); end if;
  return json_build_object('ok',true,'rows',(
    select coalesce(json_agg(json_build_object('emp_no',emp_no,'full_name',full_name,'team',team,'role',role,'token',qr_token) order by emp_no),'[]'::json)
    from haewoo_employee where active));
end;$$;

-- ========== RPC: 해우봇 ==========
create or replace function haewoo_bot_ask(p_session text, p_message text, p_lang text default 'ko')
returns json language plpgsql security definer set search_path=public,extensions as $$
declare v_topic text; ans text; m text; lng text;
begin
  if p_message is null or length(trim(p_message))=0 then return json_build_object('ok',false); end if;
  lng := coalesce(nullif(p_lang,''),'ko'); m := lower(p_message);
  insert into haewoo_bot_chat(session_id,role,message,lang) values(p_session,'user',p_message,lng);
  if m ~ '(견적|báo giá|bao gia|quote|quotation|가격|cước|cuoc)' then v_topic:='quote';
  elsif m ~ '(운송|배송|vận chuyển|van chuyen|shipping|freight|해상|항공|sea|air)' then v_topic:='shipping';
  elsif m ~ '(통관|hải quan|hai quan|customs|edi|신고|khai báo)' then v_topic:='customs';
  elsif m ~ '(창고|kho|warehouse|보관|3pl|재고)' then v_topic:='warehouse';
  elsif m ~ '(연락|전화|이메일|liên hệ|lien he|contact|phone|email|hotline)' then v_topic:='contact';
  elsif m ~ '(위치|주소|địa chỉ|dia chi|location|address|어디|ở đâu|o dau)' then v_topic:='location';
  elsif m ~ '(채용|tuyển|tuyen|hiring|career|구인|việc làm)' then v_topic:='hiring';
  elsif m ~ '(안녕|xin chào|xin chao|hello|^hi$|chào)' then v_topic:='greeting';
  else v_topic:='other'; end if;
  select answer into ans from haewoo_bot_faq where topic=v_topic and lang=lng;
  if ans is null then select answer into ans from haewoo_bot_faq where topic=v_topic and lang='ko'; end if;
  if ans is null then select answer into ans from haewoo_bot_faq where topic='other' and lang=lng; end if;
  if ans is null then select answer into ans from haewoo_bot_faq where topic='other' and lang='ko'; end if;
  insert into haewoo_bot_chat(session_id,role,message,matched_topic,lang) values(p_session,'bot',ans,v_topic,lng);
  return json_build_object('ok',true,'topic',v_topic,'answer',ans);
end;$$;

create or replace function haewoo_bot_log(p_username text,p_passcode text,p_limit int default 100)
returns json language plpgsql security definer set search_path=public,extensions as $$
begin
  if not haewoo_admin_ok(p_username,p_passcode) then return json_build_object('ok',false,'message','권한 없음'); end if;
  return json_build_object('ok',true,
    'topics',(select coalesce(json_agg(json_build_object('topic',topic,'cnt',cnt) order by cnt desc),'[]'::json) from (select matched_topic as topic,count(*) cnt from haewoo_bot_chat where role='user' group by 1) t),
    'recent',(select coalesce(json_agg(json_build_object('ts',created_at,'msg',message,'topic',matched_topic,'lang',lang) order by created_at desc),'[]'::json) from (select * from haewoo_bot_chat where role='user' order by created_at desc limit p_limit) r));
end;$$;

-- ========== RPC: 견적 ==========
create or replace function haewoo_quote_submit(p_company text,p_name text,p_phone text,p_email text,p_origin text,p_dest text,p_message text,p_lang text default 'ko')
returns json language plpgsql security definer set search_path=public,extensions as $$
begin
  if coalesce(trim(p_company),'')='' or coalesce(trim(p_name),'')='' then return json_build_object('ok',false,'message','필수 항목 누락'); end if;
  insert into haewoo_quote(company,name,phone,email,origin,destination,message,lang)
  values(p_company,p_name,p_phone,p_email,p_origin,p_dest,p_message,coalesce(nullif(p_lang,''),'ko'));
  return json_build_object('ok',true);
end;$$;

create or replace function haewoo_quote_list(p_username text,p_passcode text,p_limit int default 200)
returns json language plpgsql security definer set search_path=public,extensions as $$
begin
  if not haewoo_admin_ok(p_username,p_passcode) then return json_build_object('ok',false,'message','권한 없음'); end if;
  return json_build_object('ok',true,'rows',(
    select coalesce(json_agg(json_build_object('ts',created_at,'company',company,'name',name,'phone',phone,'email',email,'origin',origin,'destination',destination,'message',message,'lang',lang,'status',status) order by created_at desc),'[]'::json)
    from (select * from haewoo_quote order by created_at desc limit p_limit) q));
end;$$;

-- ========== 시드 ==========
insert into haewoo_work_location(id,name,lat,lng,radius_m) values
(1,'V2 Warehouse (Samsung Display Vietnam, Bac Ninh)',21.2086,105.9758,25) on conflict (id) do nothing;

insert into haewoo_shift(code,name,start_time,end_time,sort) values
('M','주간조 (06:00–14:00)','06:00','14:00',1),
('A','오후조 (14:00–22:00)','14:00','22:00',2),
('N','야간조 (22:00–06:00)','22:00','06:00',3) on conflict (code) do nothing;

insert into haewoo_admin(username,pass_hash,name,level) values
('karmadc', extensions.crypt('cnsl8582!1', extensions.gen_salt('bf')), '관리자', 'admin') on conflict (username) do nothing;

insert into haewoo_employee(emp_no,full_name,team,role,gender) values
(1,'Vũ Văn Học','지원','Manager','M'),(2,'Nguyễn Thị Giang Linh','지원','HR','F'),
(3,'Đặng Hữu Hiệu','G1','Leader','M'),(4,'Nguyễn Thị Trinh','G1','System','F'),(5,'Đỗ Đức Anh','G1','System','M'),(6,'Thái Hữu Minh','G1','System','M'),(7,'Lê Bá Tỵ','G1','System','M'),(8,'Nguyễn Anh Tuấn','G1','Forklift','M'),(9,'Trương Văn Ngọc','G1','Forklift','M'),(10,'Lưu Đình Kiên','G1','Forklift','M'),(11,'Bế Văn Dũng','G1','Forklift','M'),(12,'Hoàng Đắc Dũng','G1','InOut','M'),(13,'Ngô Quang Ước','G1','InOut','M'),(14,'Nguyễn Giản Sơn','G1','InOut','M'),(15,'Nguyễn Quang Sơn','G1','InOut','M'),
(16,'Lương Văn Trường','G2','Leader','M'),(17,'Nguyễn Thị Tân','G2','System','M'),(18,'Trần Văn Tiến','G2','System','M'),(19,'Vy Văn Dương','G2','System','M'),(20,'Vũ Trí Đức','G2','System','M'),(21,'Nguyễn Văn Việt','G2','Forklift','M'),(22,'Hoàng Văn Nguyên','G2','Forklift','M'),(23,'Ngô Thế Lập','G2','Forklift','M'),(24,'Nguyễn Văn Học','G2','Forklift','M'),(25,'Đỗ Thị Thu Huyền','G2','InOut','M'),(26,'Hoàng Đức Xuyên','G2','InOut','M'),(27,'Nguyễn Văn Hựu','G2','InOut','F'),(28,'Bàn Thị Phương','G2','InOut','M'),
(29,'Nguyên Thị Thảo','G3','Leader','F'),(30,'Bạc Văn Cường','G3','System','M'),(31,'Nguyễn Thị Sáng','G3','System','F'),(32,'Hoàng Minh Quang','G3','System','M'),(33,'Nguyễn Đình Trường','G3','System','M'),(34,'Lò Văn Trần','G3','Forklift','M'),(35,'Nguyễn Công Nam','G3','Forklift','M'),(36,'Nguyễn Văn Linh','G3','Forklift','M'),(37,'Ngô Văn Biên','G3','Forklift','M'),(38,'Hà Thế Khoa','G3','InOut','M'),(39,'Nguyễn Văn Tài','G3','InOut','M'),(40,'Nguyễn Văn Khắc','G3','InOut','M'),(41,'Giáp Văn Hanh','G3','InOut','M')
on conflict (emp_no) do nothing;

insert into haewoo_bot_faq(topic,lang,answer) values
('greeting','ko','안녕하세요! 해우비나 해우봇입니다. 견적·운송·통관·창고 무엇이든 물어보세요.'),
('greeting','vi','Xin chào! Tôi là Haewoo Bot. Hãy hỏi tôi về báo giá, vận chuyển, hải quan hoặc kho bãi.'),
('greeting','en','Hello! I am Haewoo Bot. Ask me about quotes, shipping, customs, or warehousing.'),
('quote','ko','견적은 홈페이지 하단 ''견적 요청'' 폼에 회사명·연락처·출발지·도착지를 남겨주시면 담당자가 빠르게 연락드립니다. 전화 (+84).24.6688.0608 · linh1.nguyen@haewoo-vina.com'),
('quote','vi','Vui lòng để lại tên công ty, liên hệ, điểm đi/đến tại mục ''Yêu cầu báo giá'' cuối trang. ĐT (+84).24.6688.0608 · linh1.nguyen@haewoo-vina.com'),
('quote','en','Please leave your company, contact, origin and destination in the ''Get a Quote'' form at the bottom. Tel (+84).24.6688.0608 · linh1.nguyen@haewoo-vina.com'),
('shipping','ko','해상·항공 수출입, 복합운송, 국경간 운송을 제공합니다. 출발지·도착지·화물 정보를 알려주시면 최적 루트와 리드타임을 안내드립니다.'),
('shipping','vi','Chúng tôi cung cấp vận tải biển·hàng không, đa phương thức và xuyên biên giới. Cho biết điểm đi/đến và thông tin hàng để được tư vấn.'),
('shipping','en','We offer sea & air freight, intermodal and cross-border transport. Share origin, destination and cargo details for the best route and lead time.'),
('customs','ko','수입·수출·AMA(수정)·TIA(임시) 통관과 EDI 신고를 대행합니다. 인보이스·패킹리스트만 주시면 EDI 생성부터 세관 등록까지 지원합니다.'),
('customs','vi','Chúng tôi làm thủ tục hải quan nhập·xuất·AMA·TIA và khai báo EDI. Chỉ cần invoice·packing list.'),
('customs','en','We handle import/export/AMA/TIA customs and EDI declarations. Just send the invoice & packing list.'),
('warehouse','ko','3PL 보관·재고·피킹·배송과 창고 운영(WMS)을 제공합니다. 보관 품목과 물량을 알려주시면 안내드립니다.'),
('warehouse','vi','Chúng tôi cung cấp 3PL lưu kho·tồn kho·soạn hàng·giao hàng và vận hành kho (WMS).'),
('warehouse','en','We provide 3PL storage, inventory, picking, delivery and warehouse operations (WMS).'),
('contact','ko','전화 (+84).24.6688.0608 · 이메일 linh1.nguyen@haewoo-vina.com · 베트남 하노이 꺼우저이 19 Duy Tan, TTC Tower 4층.'),
('contact','vi','ĐT (+84).24.6688.0608 · Email linh1.nguyen@haewoo-vina.com · Tầng 4 TTC Tower, 19 Duy Tân, Cầu Giấy, Hà Nội.'),
('contact','en','Tel (+84).24.6688.0608 · Email linh1.nguyen@haewoo-vina.com · 4F TTC Tower, 19 Duy Tan, Cau Giay, Hanoi.'),
('location','ko','본사는 베트남 하노이 꺼우저이 19 Duy Tan, TTC Tower 4층입니다. 박닌 V2 창고 등 현장도 운영합니다.'),
('location','vi','Trụ sở tại Tầng 4 TTC Tower, 19 Duy Tân, Cầu Giấy, Hà Nội. Chúng tôi cũng vận hành kho V2 tại Bắc Ninh.'),
('location','en','Head office: 4F TTC Tower, 19 Duy Tan, Cau Giay, Hanoi. We also operate the V2 warehouse in Bac Ninh.'),
('hiring','ko','채용 문의는 HR로 연락 주세요. linh1.nguyen@haewoo-vina.com'),
('hiring','vi','Liên hệ tuyển dụng qua HR: linh1.nguyen@haewoo-vina.com'),
('hiring','en','For hiring inquiries, contact HR: linh1.nguyen@haewoo-vina.com'),
('other','ko','문의 감사합니다. 자세한 사항은 ''견적 요청'' 폼이나 전화 (+84).24.6688.0608로 연락 주세요. 질문은 저장되어 더 나은 답변에 활용됩니다.'),
('other','vi','Cảm ơn câu hỏi của bạn. Vui lòng dùng mục ''Yêu cầu báo giá'' hoặc gọi (+84).24.6688.0608.'),
('other','en','Thanks for your question. Please use the ''Get a Quote'' form or call (+84).24.6688.0608.')
on conflict (topic,lang) do update set answer=excluded.answer;

select 'done' as status, (select count(*) from haewoo_employee) as employees, (select count(*) from haewoo_bot_faq) as faq;
