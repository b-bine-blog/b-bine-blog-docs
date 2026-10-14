---
description: "001 회원 가입·로그인·계정 관리 구현 작업 목록"
---

# 작업 목록 (Tasks): 회원 가입·로그인·계정 관리

**입력**: `specs/001-member-auth/`의 설계 문서

**선행 문서**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md), [data-model.md](data-model.md), [contracts/member-auth-api.yaml](contracts/member-auth-api.yaml), [quickstart.md](quickstart.md)

**테스트**: 명세의 성공 기준(SC-001~SC-011)이 경계값·응답 비교로 정해져 있어 스토리마다 테스트 작업을 둔다. 테스트를 먼저 쓰고 실패를 확인한 뒤 구현한다.

**구성**: 사용자 스토리별로 묶어 스토리 하나씩 따로 만들고 확인할 수 있게 했다.

## 형식: `[ID] [P?] [Story] 설명`

- **[P]**: 동시에 해도 되는 작업(다른 파일, 끝나지 않은 작업에 의존하지 않음)
- **[Story]**: 이 작업이 속한 사용자 스토리(US1~US6)
- 경로 약속: 소스 `src/main/java/com/mainblog/`, 테스트 `src/test/java/com/mainblog/`, 화면 `src/main/resources/static/`. 아래 경로는 모두 저장소 루트 기준 전체 경로로 적었다.
- 커밋 메시지에 작업 ID와 요구사항 ID를 적는다. 예: `T031 로그인 잠금 (SEC-03, D-97)`

---

## 1단계: 준비 (Setup)

**목적**: 프로젝트를 만들고 기본 설정을 둔다.

- [X] T001 Spring Boot 3.5.x / Java 21 Gradle 단일 모듈 프로젝트를 만든다: `settings.gradle`(rootProject.name = 'mainblog'), `build.gradle`(spring-boot-starter-web, -security, -data-jpa, -validation, -mail, mysql-connector-j, jjwt-api/impl/jackson 0.12.x, shedlock-spring, shedlock-provider-jdbc-template; 테스트: spring-boot-starter-test, spring-security-test, testcontainers mysql/junit-jupiter, greenmail-junit5), `gradlew` 래퍼, `src/main/java/com/mainblog/MainBlogApplication.java` (research R-01)
- [X] T002 [P] `.gitignore`에 `build/`, `.gradle/`, `.env`, `uploads/`를 추가하고 `.env.example`에 quickstart.md "준비"의 환경변수 목록(DB_URL, DB_USERNAME, DB_PASSWORD, JWT_SECRET, CODE_HASH_SECRET, MAIL_HOST, MAIL_PORT, MAIL_USERNAME, MAIL_PASSWORD, TURNSTILE_SITE_KEY, TURNSTILE_SECRET_KEY, FILE_STORAGE_ROOT)을 값 없이 적는다
- [X] T003 [P] Crowfoot 문서 654를 export_ddl로 내보내 `docs/04-design/schema.sql`로 저장하고(login_failures 포함 35개 테이블), 맨 위에 "원천은 Crowfoot 문서 654, 손으로 고치지 않음" 주석을 단다. ShedLock용 `shedlock` 테이블 DDL을 `src/test/resources/shedlock.sql`과 `docs/04-design/shedlock.sql`에 따로 둔다 (research R-02, R-13)
- [X] T004 `src/main/resources/application.yml`을 만든다: datasource(환경변수), `spring.jpa.hibernate.ddl-auto=validate`, `spring.jpa.open-in-view=false`, `spring.jackson.time-zone=Asia/Seoul`, 메일(Gmail SMTP 587 STARTTLS, 환경변수), multipart 최대 3MB, 그리고 data-model.md "설정값" 표의 17개 키를 기본값과 함께 `${ENV:기본값}` 형식으로 적는다(예: `auth.rate-limit.login: ${AUTH_RATE_LIMIT_LOGIN:20}`) (D-68)
- [X] T005 [P] 개발 DB(cf_u33_d1)의 `users.nickname` 정렬 규칙을 확인해(`SHOW FULL COLUMNS FROM users`) 대소문자를 무시하는지 결과를 `specs/001-member-auth/research.md` R-10 아래에 적는다. 대소문자를 구분하면 사용자에게 알리고 멈춘다 (R-10)

---

## 2단계: 기반 (Foundational)

**목적**: 모든 스토리가 쓰는 공통 부품. 이 단계가 끝나야 스토리 작업을 시작한다.

**⚠️ 중요**: 이 단계를 끝내기 전에는 어떤 사용자 스토리도 시작하지 않는다.

- [X] T006 [P] 설정 바인딩 클래스 `src/main/java/com/mainblog/common/config/AuthProperties.java`, `src/main/java/com/mainblog/common/config/MemberProperties.java`를 `@ConfigurationProperties`로 만들고 T004의 키(`auth.*`, `member.*`)를 `Duration`·`int`·`DataSize`로 받는다
- [X] T007 [P] `src/main/java/com/mainblog/common/config/ClockConfig.java`에 `Clock` 빈(Asia/Seoul)을 둔다. 시간을 쓰는 모든 코드는 `LocalDateTime.now(clock)`을 쓴다 (R-14)
- [X] T008 [P] 오류 응답을 만든다: `src/main/java/com/mainblog/common/error/ErrorCode.java`(VALIDATION_FAILED, CODE_MISMATCH, CODE_INVALID, EMAIL_NOT_VERIFIED, NICKNAME_DUPLICATE, SIGNUP_UNAVAILABLE, INVALID_CREDENTIALS, LOCKED, CAPTCHA_REQUIRED, CAPTCHA_FAILED, RATE_LIMITED, UNAUTHENTICATED, TOKEN_EXPIRED, CURRENT_PASSWORD_MISMATCH, PASSWORD_MISMATCH, OWNS_BLOGS, FILE_TOO_LARGE, FILE_TYPE_NOT_ALLOWED와 각 HTTP 상태), `ErrorResponse.java`(code, message, fieldErrors), `BusinessException.java`, `GlobalExceptionHandler.java`(`@RestControllerAdvice`, Bean Validation 오류 → 400 VALIDATION_FAILED) — 형식은 contracts의 `Error` 스키마
- [X] T009 `src/main/java/com/mainblog/common/config/SecurityConfig.java`: CSRF는 `CookieCsrfTokenRepository.withHttpOnlyFalse()`(SEC-10, R-12), 세션 STATELESS, 보안 헤더 X-Frame-Options DENY·nosniff·CSP `default-src 'self'; script-src 'self' https://challenges.cloudflare.com; frame-src https://challenges.cloudflare.com`·HSTS·Referrer-Policy `strict-origin-when-cross-origin`(SEC-12), 인가 규칙은 `/api/auth/**`·`GET /api/members/nickname-availability`·정적 파일 permitAll, `/api/members/me/**` authenticated, `BCryptPasswordEncoder(10)` 빈(SEC-01, R-09)
- [X] T010 [P] 회원 엔티티 `src/main/java/com/mainblog/member/domain/User.java`와 `UserRepository.java`: users 테이블 매핑(`login_fail_count`, `locked_until`은 매핑하지 않음 — data-model "쓰지 않음"), `role` USER/ADMIN, `status` ACTIVE/WITHDRAWN enum, 조회 메서드 `findByEmail`, `existsByNicknameIgnoreCase`, `findAllByNameAndPhoneAndStatus`
- [X] T011 [P] `src/main/java/com/mainblog/member/domain/UserAgreement.java`, `UserAgreementRepository.java`: `(user_id, agreement_type)` UNIQUE, agreement_type TERMS/PRIVACY
- [X] T012 [P] `src/main/java/com/mainblog/auth/domain/RefreshToken.java`, `RefreshTokenRepository.java`: token_hash UNIQUE, remember_me, last_active_at, expires_at, revoked. 메서드 `findByTokenHash`, `revokeAllByUserId(userId)`, `revokeAllByUserIdExcept(userId, tokenId)`, `deleteExpiredOrRevoked(now)`
- [X] T013 [P] `src/main/java/com/mainblog/auth/domain/LoginFailure.java`, `LoginFailureRepository.java`: email UNIQUE, fail_count NOT NULL DEFAULT 0, locked_until NULL, last_failed_at NOT NULL. 메서드 `findByEmail`, `deleteByEmail`, `deleteByLastFailedAtBefore` (research R-05)
- [X] T014 [P] `src/main/java/com/mainblog/auth/security/CodeHasher.java`: 6자리 숫자 생성(`SecureRandom`), HMAC-SHA256(`CODE_HASH_SECRET`) 해시, 상수 시간 비교. 무작위 토큰(32바이트 Base64URL)과 SHA-256 해시도 여기서 만든다 (R-03, R-08)
- [X] T015 [P] `src/main/java/com/mainblog/member/application/PasswordPolicy.java`: 8~15자, 영문·숫자·특수문자(ASCII 33~47, 58~64, 91~96, 123~126) 각 1자 이상, 이 밖의 문자 불가, 대소문자 구분 (FR-008, D-97)
- [X] T016 [P] `src/main/java/com/mainblog/member/application/NicknamePolicy.java`: 2~12자 한글·영문·숫자, 예약어 "관리자", "admin", "운영자", "탈퇴한 회원"을 설정값 `member.nickname.reserved`에서 읽어 소문자로 바꾼 닉네임에 **포함**되면 거부, 중복은 `existsByNicknameIgnoreCase` (FR-010, FR-011, D-97)
- [X] T017 [P] `src/main/java/com/mainblog/member/application/MemberInputNormalizer.java`: 이메일 trim·소문자, 전화번호 숫자만 남기고 `^010\d{8}$` 검사, 이름 앞뒤 공백 제거 후 2~20자 `^[가-힣a-zA-Z ]+$` 검사 (FR-002, FR-012, FR-013, D-97)
- [X] T018 [P] 메일 발송 `src/main/java/com/mainblog/common/mail/AuthMailSender.java`(`@Async`, JavaMailSender)와 `src/main/java/com/mainblog/common/config/AsyncConfig.java`. 메일 3종: 가입 인증번호, "이미 가입된 이메일입니다" 안내, 재설정 인증번호. 본문은 텍스트, 인증번호 외 개인정보 없음 (D-10, D-69, R-08)
- [X] T019 [P] IP 요청 제한 `src/main/java/com/mainblog/common/ratelimit/RateLimiter.java`(인터페이스 `tryAcquire(key, limit, window)`), `InMemoryRateLimiter.java`(고정 창, ConcurrentHashMap, 오래된 키 정리), `ClientIpResolver.java`(`request.getRemoteAddr()`만 사용, X-Forwarded-For 직접 신뢰 안 함) (SCL-01, R-06)
- [X] T020 [P] 공통 화면 스크립트 `src/main/resources/static/js/api.js`: fetch 래퍼, `XSRF-TOKEN` 쿠키를 `X-XSRF-TOKEN` 헤더로, 옵션 `{activity: true}`이면 `X-User-Activity: 1`, 401이면 `POST /api/auth/refresh` 한 번 시도 후 원래 요청 재시도, 5초 넘으면 중단하고 "다시 시도해 주세요" 안내(4.2). 화면에 값 넣는 헬퍼는 `textContent`만 쓴다 (SEC-10, D-64, R-04)
- [X] T021 [P] 공통 화면 틀 `src/main/resources/static/css/base.css`, `src/main/resources/static/js/layout.js`(상단 메뉴, 모든 화면 아래 개인정보 처리방침 링크, FR-017), `src/main/resources/static/privacy.html`(자리 표시 문서, 법률 검토 전)
- [X] T022 테스트 기반 `src/test/java/com/mainblog/support/IntegrationTestBase.java`: Testcontainers MySQL 8.0에 `docs/04-design/schema.sql`과 `src/test/resources/shedlock.sql`을 넣고, GreenMail SMTP, 고정 `MutableClock`(테스트에서 시간 이동)을 `@TestConfiguration`으로 등록. `src/test/resources/application-test.yml`에 Turnstile 테스트 키 `1x0000000000000000000000000000000AA`(통과)를 둔다 (R-14)
- [X] T023 기반 확인 테스트 `src/test/java/com/mainblog/support/SchemaValidationTest.java`: 컨텍스트가 `ddl-auto=validate`로 뜨는지, 보안 헤더 5종과 `XSRF-TOKEN` 쿠키가 응답에 있는지 확인

**확인 지점**: 앱이 뜨고 엔티티가 DB와 맞는다. 이제 스토리 작업을 시작할 수 있다.

---

## 3단계: 사용자 스토리 1 - 이메일 인증으로 회원가입 (P1) 🎯 MVP

**목표**: 비회원이 ① 인증번호 → ② 비밀번호 → ③ 이름·닉네임·전화번호와 동의로 가입한다. 가입 여부는 화면에서 알 수 없다.

**독립 테스트**: 빈 회원 목록에서 새 이메일로 3단계를 끝까지 진행해 계정이 생기는지, 각 단계 규칙이 지켜지는지 확인한다(로그인 없이 DB 결과로 검증).

### US1 테스트 (먼저 쓰고 실패 확인)

- [X] T024 [P] [US1] `src/test/java/com/mainblog/member/application/PasswordPolicyTest.java`, `NicknamePolicyTest.java`, `MemberInputNormalizerTest.java`: 인수 시나리오 6·7·8의 값(`abcd1234`, `Ab1!`, 16자, 1자·13자 닉네임, `Admin`, `admin1`, `ABC`가 있을 때 `abc`, `010-1234-5678` → `01012345678`, `0212345678` 거부, 이름 `김` 거부)
- [X] T025 [P] [US1] `src/test/java/com/mainblog/auth/SignupIntegrationTest.java`: 인수 시나리오 1~5, 9~11과 SC-001(가입된·안 된 이메일 응답 본문·상태·헤더 동일), SC-002(10분 경과, 5번째 오류, 재발송 후 이전 번호), FR-007(인증 후 31분이면 403 EMAIL_NOT_VERIFIED), SC-009(같은 닉네임 동시 가입 2건 → 1건만 생성)
- [X] T026 [P] [US1] `src/test/java/com/mainblog/contract/SignupContractTest.java`: `POST /api/auth/signup/email-code`, `/verify`, `GET /api/members/nickname-availability`, `POST /api/auth/signup`의 상태 코드와 본문 필드가 contracts와 같은지

### US1 구현

- [X] T027 [P] [US1] `src/main/java/com/mainblog/auth/domain/EmailVerification.java`, `EmailVerificationRepository.java`: email UNIQUE(소문자), code_hash, sent_at, expires_at(= sent_at + 10분), fail_count NOT NULL(5면 무효), verified_at(+30분 안에만 가입 완료). 메서드 `findByEmail`, `deleteByEmail`
- [X] T028 [US1] `src/main/java/com/mainblog/auth/application/SignupService.java` — 발송: 이메일 정규화 → 가입된 ACTIVE 이메일이면 안내 메일만, 아니면 행을 새 번호로 덮어쓰고(이전 번호 무효) 인증번호 메일. sent_at + 1분 안이면 메일 없이 조용히 끝냄. 어느 경우든 같은 결과를 돌려준다 (FR-003, FR-005, FR-006, D-28)
- [X] T029 [US1] `SignupService` — 확인: 만료·5회 초과·행 없음이면 CODE_INVALID(행 삭제), 틀리면 fail_count+1 후 CODE_MISMATCH(남은 횟수), 맞으면 verified_at 저장 후 `verifiedUntil` 반환 (FR-004, FR-007)
- [X] T030 [US1] `SignupService` — 가입 완료: verified_at + 30분 확인(아니면 EMAIL_NOT_VERIFIED), PasswordPolicy·NicknamePolicy·MemberInputNormalizer 적용, agreeTerms·agreePrivacy 둘 다 true, 한 트랜잭션에서 users 저장(role USER, status ACTIVE, bcrypt) + user_agreements 2건(agreed_at = now) + email_verifications 행 삭제. UNIQUE 위반(`DataIntegrityViolationException`)은 닉네임이면 NICKNAME_DUPLICATE, 이메일이면 SIGNUP_UNAVAILABLE (FR-001, FR-002, FR-007~FR-014, SC-009)
- [X] T031 [US1] `src/main/java/com/mainblog/auth/api/SignupController.java`: `POST /api/auth/signup/email-code`(202), `POST /api/auth/signup/email-code/verify`(200/400), `POST /api/auth/signup`(201/400/403/409). `src/main/java/com/mainblog/member/api/NicknameController.java`: `GET /api/members/nickname-availability`(available, reason) — 요청·응답 DTO는 같은 패키지의 record로
- [X] T032 [US1] 가입 화면 `src/main/resources/static/signup.html`, `src/main/resources/static/js/signup.js`: 3단계 한 화면 흐름, 다시 보내기 버튼 60초 비활성, 닉네임 중복 확인, [필수] 이용약관·[필수] 개인정보 수집·이용 체크박스(만 14세 체크 없음, D-91), 서버 오류 코드별 안내 문구

**확인 지점**: 가입이 혼자서 동작한다. T025 통과.

---

## 4단계: 사용자 스토리 2 - 로그인·로그아웃과 로그인 유지 (P1)

**목표**: 이메일·비밀번호 로그인, 3회 사람 확인, 5회 5분 잠금, "로그인 유지"(미체크 30분 무활동·브라우저 닫으면 로그아웃, 체크 14일 고정), 로그아웃.

**독립 테스트**: 테스트 픽스처로 만든 계정으로 로그인·로그아웃, 실패 횟수별 동작, 유지 여부별 만료를 확인한다(가입 기능 없이).

### US2 테스트

- [X] T033 [P] [US2] `src/test/java/com/mainblog/auth/LoginIntegrationTest.java`: 인수 시나리오 1~4, 9, 10과 SC-003(3회 후 captchaToken 없으면 400 CAPTCHA_REQUIRED, 5회 후 5분 안 423, 5분 뒤 성공), D-97(없는 이메일 5회도 같은 응답·같은 문구 "이메일 또는 비밀번호가 맞지 않습니다"), 성공 시 login_failures 행 삭제, 같은 IP 21번째 429
- [X] T034 [P] [US2] `src/test/java/com/mainblog/auth/SessionLifetimeIntegrationTest.java`: 인수 시나리오 5~8과 SC-004·SC-005(미체크: 활동 없이 31분 뒤 refresh 401, `X-User-Activity` 없는 요청만 있으면 31분 뒤 401, 활동 헤더가 있으면 연장 / 체크: 13일째 성공·14일+1분 401, 갱신해도 expires_at 그대로 / 로그아웃 전 RT로 refresh 401 / 회전 전 RT 재사용 시 그 회원 RT 모두 폐기), 미체크 로그인 쿠키에 Max-Age 없음
- [X] T035 [P] [US2] `src/test/java/com/mainblog/contract/LoginContractTest.java`: `/api/auth/login`, `/refresh`, `/extend`, `/logout`, `/session` 상태 코드·본문·Set-Cookie 속성(HttpOnly, Secure, SameSite=Lax)

### US2 구현

- [X] T036 [P] [US2] `src/main/java/com/mainblog/auth/security/JwtProvider.java`: HS256(`JWT_SECRET`), claim은 `sub`(회원 번호)와 `exp`만, 유효 15분(`auth.access-token-ttl`) (FR-026, FR-027, D-97)
- [X] T037 [P] [US2] `src/main/java/com/mainblog/auth/security/AuthCookies.java`: `AT`(Path=/), `RT`(Path=/, research R-03) 쿠키 만들기·지우기, 모두 HttpOnly·Secure·SameSite=Lax, rememberMe=false면 Max-Age 없음, true면 14일 (R-03)
- [X] T038 [P] [US2] `src/main/java/com/mainblog/auth/application/CaptchaVerifier.java`: Turnstile siteverify를 `RestClient`로 호출(secret, response, remoteip), 실패·네트워크 오류는 CAPTCHA_FAILED (SEC-13, D-79, R-07)
- [X] T039 [US2] `src/main/java/com/mainblog/auth/application/TokenService.java`: 로그인 시 RT 발급(만료 = now + 14일 고정, last_active_at = now), 갱신 시 유효 조건 `revoked = false AND expires_at > now AND (remember_me OR last_active_at + 30분 > now)` 확인 후 새 RT로 회전(expires_at·remember_me 물려받음, 이전 행 revoked), 폐기된 RT가 다시 오면 그 회원 RT 전부 폐기, 활동 갱신(1분에 한 번만 저장), 로그아웃 폐기 (FR-023, FR-024, FR-026, FR-029, R-03, R-04)
- [X] T040 [US2] `src/main/java/com/mainblog/auth/application/LoginService.java`: IP 제한(10분 20번) → 이메일 정규화 → login_failures 조회: 잠금 중이면 LOCKED(retryAfterSeconds), 잠금 시간이 지났으면 행 삭제 후 진행, fail_count ≥ 3이면 captchaToken 필수·검증 → 회원 조회(ACTIVE만)와 bcrypt 비교(없는 이메일도 더미 해시와 비교해 응답 시간을 맞춤) → 실패면 fail_count+1(5면 locked_until = now + 5분), INVALID_CREDENTIALS 또는 LOCKED에 captchaRequired 포함 → 성공이면 login_failures 행 삭제, TokenService로 발급. 블로그 정지 여부는 보지 않음 (FR-018, FR-020~FR-022, FR-028, D-28, D-97)
- [X] T041 [US2] `src/main/java/com/mainblog/auth/security/JwtAuthenticationFilter.java`: `AT` 쿠키 검증 후 회원 번호를 principal로 넣는다. DB에서 회원이 ACTIVE인지 확인(탈퇴 즉시 차단). 역할은 넣지 않는다(헌장 II). `ActivityTrackingFilter.java`: `X-User-Activity: 1` 요청이면 RT 쿠키로 그 기기의 last_active_at 갱신. 두 필터를 SecurityConfig에 등록
- [X] T042 [US2] `src/main/java/com/mainblog/auth/api/AuthController.java`: `POST /api/auth/login`, `POST /api/auth/refresh`, `POST /api/auth/extend`, `POST /api/auth/logout`, `GET /api/auth/session`(memberId, nickname, profileImageUrl, admin) — contracts 그대로
- [X] T043 [US2] 로그인 화면 `src/main/resources/static/login.html`, `src/main/resources/static/js/login.js`: "로그인 유지" 체크박스, captchaRequired면 Turnstile 위젯 표시(site key는 `src/main/java/com/mainblog/auth/api/PublicConfigController.java`의 `GET /api/public-config`가 `{turnstileSiteKey}`만 돌려주고, SecurityConfig에서 permitAll), 잠금 안내, 성공 시 이전 페이지로
- [X] T044 [US2] `src/main/resources/static/js/session.js`: 상단 메뉴 로그인 상태(`/api/auth/session`), 로그아웃 버튼, 유지 미체크 로그인에서 마지막 활동 25분 뒤 "로그인을 연장할까요?" 창 → 확인 시 `/api/auth/extend`. 글쓰기 화면용 `startEditorKeepAlive()`: 입력이 있으면 5분마다 extend (FR-019, FR-025, D-62, D-97)

**확인 지점**: US1·US2만으로 가입 → 로그인 → 로그아웃이 된다. MVP 완성.

---

## 5단계: 사용자 스토리 3 - 회원탈퇴와 재가입 (P2)

**목표**: 비밀번호를 다시 확인하고 탈퇴. 블로그장(폐쇄 예정 포함)이면 막는다. 같은 이메일로 바로 재가입, 닉네임은 30일 동안 막힘.

**독립 테스트**: 블로그장이 아닌 계정, 운영 중 블로그가 있는 계정, 폐쇄 예정 블로그가 있는 계정으로 탈퇴 여부와 재가입을 확인한다. (로그인이 필요하므로 US2 뒤)

### US3 테스트

- [X] T045 [P] [US3] `src/test/java/com/mainblog/member/WithdrawalIntegrationTest.java`: 인수 시나리오 1~6과 SC-008(blog_members role=OWNER 행이 있으면 409 OWNS_BLOGS, blogs.status=CLOSING이어도 409, 탈퇴 직후 같은 이메일 재가입 성공, 이전 닉네임으로 가입 시도는 30일 동안 NICKNAME_DUPLICATE), 탈퇴 후 기존 RT로 refresh 401
- [X] T046 [P] [US3] `src/test/java/com/mainblog/batch/DailyCleanupJobTest.java`: 탈퇴 30일 지난 회원의 withdrawn_email·name·nickname·phone·bio가 NULL, 프로필 이미지 deleted_at 설정, 29일째는 그대로 / 만료·폐기 RT 삭제 / last_failed_at 1일 지난 login_failures 삭제

### US3 구현

- [X] T047 [P] [US3] `src/main/java/com/mainblog/member/domain/OwnedBlogQuery.java`: `blog_members`(role = OWNER)와 `blogs`(status ACTIVE·CLOSING)를 조인해 blogId, name, address, status, closeScheduledAt을 읽는 읽기 전용 쿼리(JdbcTemplate). 블로그 엔티티는 002에서 만든다
- [X] T048 [US3] `src/main/java/com/mainblog/member/application/WithdrawalService.java`: 비밀번호 확인(PASSWORD_MISMATCH) → OwnedBlogQuery가 비어 있지 않으면 OWNS_BLOGS → users.status = WITHDRAWN, withdrawn_at = now, withdrawn_email = email, email = NULL(닉네임은 그대로) → RT 전부 폐기 (FR-045~FR-048, D-15, D-18, D-97)
- [X] T049 [US3] `src/main/java/com/mainblog/member/api/WithdrawalController.java`: `GET /api/members/me/withdrawal`(canWithdraw, ownedBlogs), `POST /api/members/me/withdrawal`(204 + 쿠키 삭제)
- [X] T050 [US3] `src/main/java/com/mainblog/batch/DailyCleanupJob.java`와 `src/main/java/com/mainblog/common/config/SchedulingConfig.java`: `@Scheduled(cron = "0 0 4 * * *", zone = "Asia/Seoul")` + `@SchedulerLock(name = "dailyCleanup")`, ShedLock JdbcTemplateLockProvider. 작업: 탈퇴 30일 지난 개인정보 삭제, 만료·폐기 RT 삭제(D-83), 1일 지난 login_failures 삭제 (4.5, SCL-03, R-13)
- [X] T051 [US3] 탈퇴 화면 `src/main/resources/static/me/withdraw.html`, `src/main/resources/static/js/withdraw.js`: 운영 중 블로그 목록(폐쇄 예정이면 예정 시각)과 "위임하거나 폐쇄한 뒤 탈퇴할 수 있습니다" 안내, 비밀번호 입력, 탈퇴 후 메인으로

**확인 지점**: 탈퇴·재가입이 따로 동작한다.

---

## 6단계: 사용자 스토리 4 - 비밀번호 찾기·재설정 (P2)

**목표**: 이메일로 6자리 인증번호(30분, 1회용, 5번 무효)를 받아 같은 화면에서 새 비밀번호를 정한다. 모든 기기 로그아웃, 잠금 해제.

**독립 테스트**: 테스트 계정으로 재설정 흐름을 끝까지 진행해 규칙, 다른 기기 로그아웃, 잠금 해제를 확인한다.

### US4 테스트

- [X] T052 [P] [US4] `src/test/java/com/mainblog/auth/PasswordResetIntegrationTest.java`: 인수 시나리오 1~6과 SC-001(가입·미가입 이메일 응답 동일, 미가입·탈퇴 이메일은 메일 0통), SC-002(30분 경과, 5번째 오류, 사용한 번호 재사용, 1분 안 재요청은 메일 없음), SC-004(재설정 후 기존 RT 전부 401), 잠긴 계정의 login_failures 행 삭제

### US4 구현

- [X] T053 [P] [US4] `src/main/java/com/mainblog/auth/domain/PasswordResetCode.java`, `PasswordResetCodeRepository.java`: user_id, code_hash, sent_at(다시 보내기 1분), expires_at(sent_at + 30분), fail_count(5면 무효), used(1회용). 회원당 1건, 새로 보내면 이전 행 삭제
- [X] T054 [US4] `src/main/java/com/mainblog/auth/application/PasswordResetService.java`: 발송(ACTIVE 회원만 메일, 1분 안이면 조용히 끝냄, 응답 동일), 확인(맞는지만, 틀리면 fail_count+1), 저장(코드 다시 확인 → PasswordPolicy·두 값 일치 → bcrypt 저장 → 코드 행 삭제 → RT 전부 폐기 → login_failures에서 그 이메일 행 삭제). 대상 회원을 email 또는 userId로 받는 내부 메서드를 둬 US6에서 다시 쓴다 (FR-030~FR-033, D-25, D-97)
- [X] T055 [US4] `src/main/java/com/mainblog/auth/api/PasswordResetController.java`: `POST /api/auth/password-reset/code`(202), `/verify`(200/400), `POST /api/auth/password-reset`(204/400)
- [X] T056 [US4] 화면 `src/main/resources/static/find-password.html`, `src/main/resources/static/js/find-password.js`: 이메일 입력 → "입력한 이메일로 안내를 보냈습니다" → 인증번호 → 새 비밀번호 두 번, 다시 보내기 60초 비활성. `resetToken` 쿼리 파라미터가 있으면 이메일 칸 없이 시작(US6에서 씀)

**확인 지점**: 비밀번호 재설정이 따로 동작한다.

---

## 7단계: 사용자 스토리 5 - 내 정보 보기와 회원정보 수정 (P3)

**목표**: 본인 정보를 가리지 않고 보고, 닉네임·프로필 사진·전화번호·비밀번호를 바꾼다. 이메일·이름은 못 바꾼다.

**독립 테스트**: 로그인해 내 정보 표시와 항목별 수정을 확인하고, 다른 회원 정보 수정이 거부되는지 본다. (US2 뒤)

### US5 테스트

- [X] T057 [P] [US5] `src/test/java/com/mainblog/member/MyInfoIntegrationTest.java`: 인수 시나리오 1~4, 6(내 정보 원문 표시·비밀번호 필드 없음, email·name 필드를 보내면 400, 닉네임 규칙·중복, 비밀번호 변경 시 현재 기기 RT는 새로 발급되어 refresh 성공·다른 기기 RT는 401)
- [X] T058 [P] [US5] `src/test/java/com/mainblog/common/storage/ProfileImageUploadTest.java`: 인수 시나리오 5(3MB 초과·svg·확장자만 jpg인 png 파일 거부, jpg는 EXIF GPS 태그가 지워진 채 저장, webp는 EXIF 청크 제거, 저장 이름 UUID)

### US5 구현

- [X] T059 [P] [US5] `src/main/java/com/mainblog/common/storage/FileStorage.java`(인터페이스 save/delete/url), `LocalDiskFileStorage.java`(`FILE_STORAGE_ROOT`, UUID 이름) (D-75, SCL-02)
- [X] T060 [P] [US5] `src/main/java/com/mainblog/common/storage/ImageValidator.java`: 확장자 jpg·jpeg·png·gif·webp, MIME, 매직 넘버(FFD8FF / 89504E47 / GIF8 / RIFF....WEBP)가 모두 맞아야 통과, 3MB 이하. `ImageSanitizer.java`: jpg·png·gif는 ImageIO로 다시 써서 메타데이터 제거, webp는 RIFF에서 `EXIF`·`XMP ` 청크 제거 (FR-043, 6.3, SEC-08, R-11)
- [X] T061 [P] [US5] `src/main/java/com/mainblog/member/domain/ProfileImage.java`(images 테이블, owner_type = PROFILE, owner_id = users.id, uploader_id = users.id, stored_name UUID UNIQUE, content_type, size_bytes, deleted_at), `ProfileImageRepository.java`
- [X] T062 [US5] `src/main/java/com/mainblog/member/application/MemberService.java`: 내 정보 조회(원문), 닉네임·전화번호 수정(NicknamePolicy, MemberInputNormalizer 재사용), 비밀번호 변경(현재 비밀번호 확인 → PasswordPolicy → 저장 → 다른 기기 RT 폐기 `revokeAllByUserIdExcept` → 이 기기 RT 회전 후 새 쿠키), 프로필 사진 교체(이전 행 deleted_at)·삭제 (FR-040~FR-044, D-97)
- [X] T063 [US5] `src/main/java/com/mainblog/member/api/MemberController.java`: `GET /api/members/me`, `PATCH /api/members/me`(알 수 없는 필드 거부), `PUT /api/members/me/password`, `PUT`·`DELETE /api/members/me/profile-image`. 모든 요청은 principal의 회원 번호만 쓰고 경로·본문의 회원 번호를 받지 않는다(인수 시나리오 6)
- [X] T064 [US5] 화면 `src/main/resources/static/me/index.html`, `src/main/resources/static/js/me.js`(정보 표시·닉네임·전화번호·사진 수정), `src/main/resources/static/me/password.html`, `src/main/resources/static/js/me-password.js`

**확인 지점**: 내 정보 수정이 따로 동작한다.

---

## 8단계: 사용자 스토리 6 - 이메일 찾기에서 비밀번호 재설정까지 (P3)

**목표**: 이름+전화번호로 가린 이메일과 가입일을 보고, 그 자리에서 재설정으로 이어 간다.

**독립 테스트**: 같은 이름·전화번호 계정 2개(1개 탈퇴)로 결과, 가린 형식, 임시 토큰 만료, IP 제한을 확인한다. (재설정 절차는 US4 재사용)

### US6 테스트

- [X] T065 [P] [US6] `src/test/java/com/mainblog/common/masking/EmailMaskerTest.java`: `abcdef@gmail.com` → `ab***@gmail.com`, `ab@x.com` → `a***@x.com`, `a@x.com` → `a***@x.com` (FR-036, 4.4)
- [X] T066 [P] [US6] `src/test/java/com/mainblog/auth/FindEmailIntegrationTest.java`: 인수 시나리오 1~7과 SC-006(응답 JSON 문자열 어디에도 원문 이메일 없음), SC-007(같은 IP 6번째 429), 10분 지난 resetToken 410, 다른 계정의 토큰으로 바꿔도 그 토큰의 계정에만 메일

### US6 구현

- [X] T067 [P] [US6] `src/main/java/com/mainblog/common/masking/EmailMasker.java`: @ 앞 처음 2글자 + `***`, @ 앞이 2글자 이하면 첫 글자 + `***` (FR-036)
- [X] T068 [P] [US6] `src/main/java/com/mainblog/auth/domain/PasswordResetToken.java`, `PasswordResetTokenRepository.java`: token_hash UNIQUE, expires_at = 발급 + 10분, 쓰이거나 만료되면 삭제 (FR-038)
- [X] T069 [US6] `src/main/java/com/mainblog/auth/application/FindEmailService.java`: IP 제한(10분 5번) → 이름 trim·전화번호 숫자만 → status ACTIVE만 조회 → 계정마다 resetToken 발급 → maskedEmail·joinedOn(가입일)·resetToken. 재설정 코드 발송은 토큰 확인 후 PasswordResetService의 userId 메서드 호출 (FR-034~FR-039, D-23, D-26)
- [X] T070 [US6] `src/main/java/com/mainblog/auth/api/FindEmailController.java`: `POST /api/auth/find-email`(200/429), `POST /api/auth/find-email/reset-code`(202/410). PasswordResetController의 verify·저장이 `resetToken`도 받도록 요청 DTO와 서비스 분기를 더한다
- [X] T071 [US6] 화면 `src/main/resources/static/find-email.html`, `src/main/resources/static/js/find-email.js`: 결과 목록(가린 이메일, "2026.10.02 가입"), 없으면 "일치하는 회원 정보가 없습니다", 계정 옆 [비밀번호 재설정] → `find-password.html?resetToken=…`

**확인 지점**: 6개 스토리가 모두 따로 동작한다.

---

## 9단계: 마무리 (Polish)

- [X] T072 [P] `src/test/java/com/mainblog/contract/OpenApiConformanceTest.java`: `specs/001-member-auth/contracts/member-auth-api.yaml`의 18개 경로가 모두 매핑돼 있는지 Spring의 RequestMappingHandlerMapping과 대조
- [X] T073 [P] `src/test/java/com/mainblog/perf/AuthResponseTimeTest.java`: 로그인·가입 발송·비밀번호 찾기·이메일 찾기 응답이 2초 이내(SC-010), 가입된·안 된 이메일의 발송 응답 시간 차이가 측정 오차 범위 안(R-08, D-28)
- [X] T074 quickstart.md의 확인 시나리오 20개를 로컬에서 실행하고, 결과(통과·실패와 이유)를 `specs/001-member-auth/quickstart.md` 아래 "확인 결과" 절에 날짜와 함께 적는다
- [X] T075 [P] `README.md`(저장소 루트)에 실행 방법(JDK 21, `.env` 준비, `./gradlew bootRun`, 테스트)과 문서 위치를 짧게 적는다
- [X] T076 `/security-review`를 돌려 지적 사항을 고친다: 쿠키 속성, CSRF 예외 경로 없음, 로그·오류 메시지에 이메일·전화번호·인증번호·토큰 원문이 없는지(헌장 I, III)

---

## 의존 관계와 실행 순서

### 단계 의존

- **1단계 준비**: 바로 시작
- **2단계 기반**: 1단계 뒤. 모든 스토리를 막는다
- **US1(가입)**, **US2(로그인)**: 2단계 뒤 동시에 가능
- **US4(재설정)**: 2단계 뒤 가능(RefreshToken·LoginFailure가 2단계에 있어 US2 없이도 테스트 가능)
- **US3(탈퇴)**, **US5(내 정보)**: 인증 필터(T041)가 필요해 US2 뒤
- **US6(이메일 찾기)**: 재설정 절차를 다시 써서 US4 뒤
- **9단계 마무리**: 원하는 스토리가 끝난 뒤

### 스토리 안 순서

테스트(실패 확인) → 엔티티 → 서비스 → 컨트롤러 → 화면

### 동시에 할 수 있는 것

- 1단계: T002, T003, T005
- 2단계: T006~T008, T010~T021 (T009는 T008 뒤, T022는 T003 뒤, T023은 T009·T022 뒤)
- US1과 US2와 US4를 서로 다른 사람이 동시에
- 스토리 안의 [P] 테스트와 [P] 엔티티

### 예: US2를 동시에 시작

```text
T033 LoginIntegrationTest
T034 SessionLifetimeIntegrationTest
T035 LoginContractTest
T036 JwtProvider
T037 AuthCookies
T038 CaptchaVerifier
```

### 예: US5를 동시에 시작

```text
T057 MyInfoIntegrationTest
T058 ProfileImageUploadTest
T059 FileStorage
T060 ImageValidator / ImageSanitizer
T061 ProfileImage
```

---

## 구현 전략

### MVP (US1 + US2)

1. 1단계 준비, 2단계 기반
2. US1 가입 → T025 통과 확인
3. US2 로그인 → T033·T034 통과 확인
4. 여기서 멈추고 가입 → 로그인 → 로그아웃을 화면으로 확인(quickstart 1~11번)

### 하나씩 더하기

MVP → US4 재설정 → US3 탈퇴 → US5 내 정보 → US6 이메일 찾기. 스토리마다 테스트 통과 후 커밋하고 PR에 올린다.

### 참고

- 숫자 규칙은 모두 `application.yml` 설정값으로만 읽는다. 코드에 10분·30분·5회 같은 값을 쓰지 않는다(D-68)
- 엔티티를 바꾸고 싶으면 먼저 Crowfoot 문서를 고치고 plan_migration을 사용자에게 보여 승인을 받는다. `ddl-auto`로 DB를 바꾸지 않는다(R-02)
- `idx_login_failures_last_failed_at` 인덱스는 사용자 결정으로 DB에 없다. 배치 삭제 쿼리는 인덱스 없이 동작하게 둔다
