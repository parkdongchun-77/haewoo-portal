# Haewoo 포털 — 요구사항·자료 정리

## A. 인력 운영 자료 분석 (업로드 엑셀 2종)

### A-1. HAEWOO Operation Preparation Checklist-3.xlsx
독립 창고(V2 Site) 운영 준비 체크리스트. Week 25(2026.06.15~06.21), 월말 독립 운영 대비.
- 시트: Checklist / 1.조직도 / 1-2.인력명단 / 2.지게차 자격증 / 2-2.산업안전교육
- 체크리스트
  - ① 교대조 운영 체계 구축 — 인력 명단 확정·공유 (deadline 06-19)
  - ② 운영 자격증 제공 — 지게차 12명 자격증 + 전사원 산업안전교육 이수증·ATVSLĐ Group 3 (06-20)
  - ③ 창고 운영 역량 1차 평가 — In/Out·System·Forklift 그룹별 직무수행 평가 (06-21)
- 조직 (V2 W/H)
  - W/H Operation Manager: KIM YOUNG SEOK
  - V2 Logistics Team Leader: Vũ Văn Học / HR: Nguyễn Thị Giang Linh
  - 그룹: G1(Leader Đặng Hữu Hiệu) / G2(Leader Lương Văn Trường) / G3(Leader Nguyên Thị Thảo)
- 인력 39명 (지원 인력 별도). 그룹 균등 13명씩.
  | 구분 | Total | G1 | G2 | G3 |
  |---|---|---|---|---|
  | TTL | 39 | 13 | 13 | 13 |
  | Leader | 3 | 1 | 1 | 1 |
  | System | 12 | 4 | 4 | 4 |
  | Forklift(F/L) | 12 | 4 | 4 | 4 |
  | In/Out(I/O) | 12 | 4 | 4 | 4 |
- 지게차 자격증 보유 12명(그룹별 4명), 산업안전교육 36명 이수(06/19).

### A-2. (26-06-02) SDV WH Additional Manpower Assignment Plan.xlsx
- 야간조 추가 4명 (Leader 1, Forklift 2, System 1) — 숙련 주간 OP를 야간으로 배치(Running Change 인수인계).
- 주간조 추가 2명 (In/Out).
- 6월 교대 캘린더: G1/G2/G3(각 13명) 회전. 패턴은 Day / "Day2 & N"(주간2+야간) / Off. 일일 투입 7~16명.

> 결론: 현재 SDV WH는 **G1·G2·G3 3개 그룹(각 13명)** 이 **Day/Night** 로 회전. 사용자는 이를 **3 Shift(3교대) 체제**로 재구성 요청.

---

## B. EDI System 프로세스 (사용자 정의 스펙 — 기록)

1. 고객사가 인보이스·패킹리스트를 제공(Excel/PDF/캡쳐/사진).
2. EDI System이 분석(파싱, API 연동).
3. Ecuss System 접속(ID/Pass 입력), 불필요한 창 제거.
4. Ecuss의 카테고리에 분석 데이터 자동 입력. 자동입력할 데이터가 없으면 **수동 입력 항목으로 표시**해 담당자가 확인·입력.
5. EDI System 창에 "자동입력 완료" 메시지 → **OK 클릭 시 베트남 세관 시스템에 등록**.

> 절대 제약 유지: 세관 등록(전송)은 사람이 OK(승인)한 뒤에만. 현재는 Ecuss 실연동 스펙 도착 시 어댑터 교체.

---

## C. 근태 시스템 (신규 요구) — 3 Shift + QR + GPS

- **3 Shift(3교대)** 로 운영. 조: G1/G2/G3(엑셀 로스터 사용). 역할: Leader/System/Forklift/In-Out.
- **QR 출퇴근**: 근무자는 본인 휴대폰에서 본인 QR(개인 링크)을 클릭 → **출근/퇴근 버튼만** 누름.
- **GPS 25m**: V2 창고 기준점 반경 25m 이내에서만 인정.
- **저장 데이터**: 본인 이름·전화 연동 + 출/퇴근 구분 + 년·월·일·시간. 누적해서 DB 구축.
- **권한**: 근무자=QR 출퇴근만. 관리자·중간관리자=전체 데이터 조회(대시보드).
- 백엔드: Supabase (profiles/employees/attendance/work_location 스키마 — migrations 참조).

---

## D. 해우봇 (신규 요구) — 안내 챗봇

- 홈페이지에서 견적·기타 문의에 즉시 응답하는 챗봇.
- 질문·답변을 **누적 저장**해 "사람들이 자주 궁금해하는 것" DB 구축.
- 백엔드: Supabase(테이블 bot_chat) + 답변 로직(FAQ 룰 → 추후 LLM 연동).

---

## E. 미해결 / 확인 필요
- 3 Shift 시간대 정의(예: 06–14 / 14–22 / 22–06).
- Supabase 실제 생성·연결 시점(현재는 코드·스키마만 준비).
- 직원 QR 발급 방식(개인 고유 링크 자동 생성 + 최초 1회 이름·전화 등록).
