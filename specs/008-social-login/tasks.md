# 작업 목록: 008 소셜 로그인

근거: [spec.md](spec.md), [plan.md](plan.md), [data-model.md](data-model.md), D-125.

## 1단계 준비

- [X] T001 `spring-boot-starter-oauth2-client` 추가 (build.gradle)
- [X] T002 설정값 `oauth.*`(앱 키, request/signup/link-ttl) — application.yml, .env.example, OAuthProperties (D-68)
- [X] T003 표 `social_accounts`, `social_pendings`, `users.password_hash` NULL 허용 — docs/04-design/schema.sql, Crowfoot REQ-062, 실제 DB

## 2단계 기반

- [X] T004 키가 있는 서비스만 등록 (OAuthClientConfig, SocialClients) — FR-014
- [X] T005 인가 요청을 서명한 쿠키에 보관(세션 없음) (CookieAuthorizationRequestRepository)
- [X] T006 로그인 유지·연결 모드 전달, 구글 PKCE (SocialAuthorizationRequestResolver)
- [X] T007 소셜 토큰을 저장하지 않음 (NoStoreAuthorizedClientRepository) — FR-008
- [X] T008 서비스별 프로필 읽기, 확인된 이메일만 믿음 (SocialProfile)
- [X] T009 저장소 (SocialAccountStore, SocialPendingStore)

## 3단계 US1·US2 가입과 로그인

- [X] T010 돌아온 뒤 처리와 이동 (SocialLoginService.onCallback, SocialLoginHandlers) — FR-002, FR-003
- [X] T011 대기 API: 보기, 이메일 인증, 가입 (SocialController) — FR-004, FR-005, FR-016
- [X] T012 로그인·가입 화면 버튼과 실패 안내 (social-buttons.js, login.html, signup.html)
- [X] T013 마무리 화면 (social.html, social.js)

## 4단계 US3 같은 이메일 연결

- [X] T014 비밀번호 확인 뒤 연결, 잠금·사람 확인은 이메일 로그인과 같음 (SocialLoginService.link) — FR-006, FR-007

## 5단계 US4 연결 관리

- [X] T015 내 정보 연결·끊기, 마지막 로그인 방법 보호 (MemberSocialController, me-social.js) — FR-010
- [X] T016 비밀번호 없는 회원: 비밀번호 만들기, 비밀번호 없이 탈퇴, 탈퇴 때 연결 삭제 — FR-009, FR-012
- [X] T017 만료된 대기 정보 04:00 정리 (DailyCleanupJob)

## 6단계 확인

- [X] T018 API 계약 [contracts/social-login-api.yaml](contracts/social-login-api.yaml), OpenApiConformanceTest에 등록
- [X] T019 통합 테스트 SocialLoginIntegrationTest
- [ ] T020 운영 키 등록(구글·카카오·네이버 개발자 화면, GitHub Secrets)과 배포 뒤 실제 로그인 확인 — 사용자
