# 소셜 로그인 설정 가이드 (Google · Facebook · Kakao · Zalo)

login.html은 완성되어 있고, 각 제공자의 **앱 키 등록**만 하면 바로 동작합니다. (앱 등록은 보안상 직접 하셔야 합니다.)

프로젝트: Supabase `haewoo-portal`
- API URL: `https://kusfsjkuwnbrtccjjfkm.supabase.co`
- 공통 OAuth 콜백(구글·페북·카카오용): `https://kusfsjkuwnbrtccjjfkm.supabase.co/auth/v1/callback`

## 0. 공통 — 허용 redirect URL 등록
Supabase 대시보드 → Authentication → URL Configuration
- Site URL: 배포 도메인(예: `https://haewoo-vina.com`). 테스트 중이면 `http://localhost:8002`.
- Redirect URLs에 추가: `http://localhost:8002/login.html`, 배포 후 `https://<도메인>/login.html`.

## 1. Google
1. Google Cloud Console → OAuth 동의화면 + 사용자 인증 정보 → OAuth 클라이언트 ID(웹).
2. 승인된 리디렉션 URI에 위 **공통 콜백** 입력.
3. 발급된 Client ID / Secret → Supabase → Authentication → Providers → **Google** 에 입력 후 Enable.

## 2. Facebook
1. developers.facebook.com → 앱 생성 → Facebook 로그인 추가.
2. Valid OAuth Redirect URIs에 **공통 콜백** 입력.
3. App ID / App Secret → Supabase → Providers → **Facebook** 입력 후 Enable.

## 3. Kakao
1. developers.kakao.com → 애플리케이션 → 카카오 로그인 활성화.
2. Redirect URI에 **공통 콜백** 입력. 동의항목에서 닉네임/이메일 설정.
3. REST API 키(= Client ID) / Client Secret → Supabase → Providers → **Kakao** 입력 후 Enable.

## 4. Zalo (Edge Function으로 연동 — 이미 배포됨)
함수: `zalo-oauth` (배포 완료, ACTIVE)
- 로그인 시작: `https://kusfsjkuwnbrtccjjfkm.functions.supabase.co/zalo-oauth/login`
- 콜백(앱에 등록): `https://kusfsjkuwnbrtccjjfkm.functions.supabase.co/zalo-oauth/callback`

설정 순서
1. developers.zalo.me → 앱 생성 → Login 권한. Callback URL에 위 **콜백** 입력.
2. 앱의 App ID / App Secret 확보.
3. Supabase 대시보드 → Edge Functions → **Secrets** 에 추가:
   - `ZALO_APP_ID` = 앱 ID
   - `ZALO_APP_SECRET` = 앱 시크릿
   (`SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`는 자동 주입되므로 추가 불필요.)
4. Zalo는 합성 이메일 `zalo_<id>@haewoo-vina.zalo`로 Supabase 사용자를 생성/연결해 세션을 발급합니다.

## 동작 방식
- 홈페이지·포털의 **로그인** → `login.html`.
- 구글/페북/카카오: Supabase OAuth(`signInWithOAuth`). 로그인 후 `?next=`로 이동.
- Zalo: 위 Edge Function이 OAuth를 처리하고 매직링크로 Supabase 세션 발급.
- 로그인 세션은 브라우저에 저장되며 `login.html`에서 프로필·로그아웃 확인 가능.

## 참고
- 키 등록 전에는 해당 버튼이 "제공자 설정 필요" 안내를 표시합니다(정상).
- 운영 도메인 등록 후에는 localhost 대신 실제 도메인 redirect URL을 추가하세요.
