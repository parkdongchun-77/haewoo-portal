# 소셜 로그인 설정 가이드 (현재 상태 + 남은 단계)

운영 Supabase 프로젝트: **haewoo-portal** (ref `fnvtdvpfuevzukfndpek`, karma_77@naver.com / 헤우포털 조직)
- 공통 OAuth 콜백(구글·카카오·페북용): `https://fnvtdvpfuevzukfndpek.supabase.co/auth/v1/callback`
- 사이트 주소: `https://parkdongchun-77.github.io/haewoo-portal/`
- Supabase Auth → URL Configuration: Site URL + redirect 허용 `https://parkdongchun-77.github.io/haewoo-portal/**` **설정 완료**

## ✅ Google — 완료·검증됨 (라이브 동작)
- Google Cloud(moa-hagwon) OAuth 클라이언트 "Haewoo Vina Web" 생성, 콜백 등록.
- Supabase Google provider 활성화 + Client ID/Secret 입력 완료.
- 참고: Google **OAuth 동의 화면이 "테스트" 모드**. 일반 사용자도 쓰려면 Google Cloud → 대상(OAuth 동의 화면) → **앱 게시(프로덕션 전환)** 또는 테스트 사용자 추가.

## ⛔ Kakao — 거의 완료, 단 "비즈 앱 전환" 필요 (사용자 본인인증)
Kakao 앱 **"Haewoo Vina" (ID 1496475)** 생성 + 설정 대부분 완료:
- REST API 키 `618b7cb65795b7d9ae7dc76d87e469e3` → Supabase Kakao Client ID 입력 완료
- Client Secret `0vXasePJtgGabVAwT7hrDXIqv8cblzrD` → Supabase 입력 완료
- 카카오 로그인 활성화 ON, Redirect URI `.../auth/v1/callback` 등록 완료
- 동의항목 닉네임(profile_nickname) 필수 동의 설정 완료
- Supabase Kakao provider 활성화 + 이메일없는사용자 허용 ON 완료

**막힌 부분(KOE205)**: Supabase는 카카오에 항상 `account_email` scope를 요청하는데(클라이언트로 제거 불가), **개인(비즈 아님) 앱은 account_email이 "권한 없음"**이라 거부됨.
**해결**: Kakao 앱을 **비즈 앱으로 전환**해야 함 → developers.kakao.com → 앱 → 비즈니스 → "비즈 앱 전환". 사업자번호 없으면 **본인인증 + 카카오비즈니스 약관 동의**로 개인 비즈 앱 전환 가능(사용자 직접). 전환 후 동의항목에서 **카카오계정(이메일)**을 "선택 동의", **프로필 사진**을 "선택 동의"로 설정하면 카카오 로그인 동작.

## ⏳ Facebook — 키만 등록하면 됨 (Google과 동일 패턴)
1. developers.facebook.com → 앱 생성 → Facebook 로그인 추가.
2. Valid OAuth Redirect URIs에 위 **공통 콜백** 입력.
3. App ID / App Secret → Supabase → Providers → **Facebook** 입력 후 활성화.

## ⏳ Zalo — Edge Function 재배포 필요
- 기존 Zalo Edge Function은 이전(karmadc) 프로젝트에 배포돼 있어, 신규 프로젝트(fnvtdvpfuevzukfndpek)에 **다시 배포** 필요.
- 이후 developers.zalo.me 앱 생성 → 콜백 `https://fnvtdvpfuevzukfndpek.functions.supabase.co/zalo-oauth/callback` → Edge Function secrets `ZALO_APP_ID`, `ZALO_APP_SECRET` 설정.

## 동작 방식
- 홈페이지·포털의 **로그인** → `login.html`.
- 구글/페북/카카오: Supabase OAuth(`signInWithOAuth`). Zalo: Edge Function 매직링크.
- 키 등록 전 버튼은 "제공자 설정 필요" 안내 표시(정상).
