# 소셜 로그인 설정 가이드 (현재 상태 + 남은 단계)

운영 Supabase 프로젝트: **haewoo-portal** (ref `fnvtdvpfuevzukfndpek`, karma_77@naver.com / 헤우포털 조직)
- 공통 OAuth 콜백(구글·카카오·페북용): `https://fnvtdvpfuevzukfndpek.supabase.co/auth/v1/callback`
- 사이트 주소: `https://parkdongchun-77.github.io/haewoo-portal/`
- Supabase Auth → URL Configuration: Site URL + redirect 허용 `https://parkdongchun-77.github.io/haewoo-portal/**` **설정 완료**

## ✅ Google — 완료·검증됨 (라이브 동작)
- Google Cloud(moa-hagwon) OAuth 클라이언트 "Haewoo Vina Web" 생성, 콜백 등록.
- Supabase Google provider 활성화 + Client ID/Secret 입력 완료.
- 참고: Google **OAuth 동의 화면이 "테스트" 모드**. 일반 사용자도 쓰려면 Google Cloud → 대상(OAuth 동의 화면) → **앱 게시(프로덕션 전환)** 또는 테스트 사용자 추가.

## ⏳ Kakao — 앱은 생성됨, 키 입력만 남음
Kakao 앱 **"Haewoo Vina" (ID 1496475)** 이미 생성 완료. 남은 단계:
1. developers.kakao.com → 내 애플리케이션 → Haewoo Vina → **앱 키**에서 **REST API 키** 복사. (= Supabase Client ID)
2. **카카오 로그인** 메뉴 → 활성화 설정 **ON**.
3. 같은 화면 **Redirect URI 등록**: `https://fnvtdvpfuevzukfndpek.supabase.co/auth/v1/callback`
4. **카카오 로그인 → 보안** → **Client Secret 코드 생성** + 활성화 상태 **사용함**. (= Supabase Client Secret)
5. **동의항목** → 닉네임/프로필 사진(필수 권장), 카카오계정(이메일) 선택.
6. Supabase 대시보드 → Authentication → Sign In/Providers → **Kakao** 열기 → 활성화 → **Client ID = REST API 키**, **Client Secret = 4번 코드** 입력 → 저장.

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
