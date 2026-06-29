-- 하노이 사업장 직원 12명 시드 (사무·관리직, team=지원, 사번 3001~3012)
-- Supabase SQL Editor에 붙여넣어 Run. (idempotent)

insert into haewoo_employee(emp_no,full_name,team,role,phone,site) values
(3001,'Byun Young Sub','지원','General Director','037.357.3751','하노이'),
(3002,'Choi Young Eun','지원','Support Manager','033.451.7747','하노이'),
(3003,'Phuong Mai','지원','Interpreter','039.827.5705','하노이'),
(3004,'Nguyen Thi Hien','지원','Operation Manager','038.993.2766','하노이'),
(3005,'Linh Nguyen','지원','Operation Staff','037.204.6573','하노이'),
(3006,'Le Thi Nhung','지원','HR/GA Team Leader','036.888.5301','하노이'),
(3007,'Nguyen Thi Huyen','지원','HR/GA Staff','034.262.3435','하노이'),
(3008,'Le Thi Bich Ngoc','지원','Accounting Team Leader','097.402.5593','하노이'),
(3009,'Thanh Thao','지원','Accounting Staff','097.937.9704','하노이'),
(3010,'Kim Young Seok','지원','W/H Operation Manager','035.286.0038','하노이'),
(3011,'Giang Linh','지원','W/H HR/EHS','038.682.4400','하노이'),
(3012,'Vu Van Hoc','지원','V2 Logistics Team Leader','098.485.7082','하노이')
on conflict (emp_no) do update set
  full_name=excluded.full_name, team=excluded.team, role=excluded.role,
  phone=excluded.phone, site=excluded.site;

select emp_no, full_name, team, role, phone, site
from haewoo_employee where site='하노이' order by emp_no;
