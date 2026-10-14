# 구현 계획 (Implementation Plan): 회원 가입·로그인·계정 관리

**브랜치**: `001-member-auth` | **날짜**: 2026-10-07 | **명세**: [spec.md](spec.md)

**입력**: `specs/001-member-auth/spec.md` (확인 필요 항목 0개, D-97까지 반영)

## 요약 (Summary)

이메일을 아이디로 쓰는 3단계 가입(인증번호 → 비밀번호 → 이름·닉네임·전화번호와 동의), JWT + HttpOnly 쿠키 로그인과 "로그인 유지", 비밀번호 찾기·재설정, 이메일 찾기, 내 정보 수정, 탈퇴를 만든다.
Spring Boot 단일 애플리케이션이 REST API와 정적 HTML + JS 화면을 함께 내려준다. 데이터는 이미 배포된 Crowfoot ERD의 회원 테이블을 쓰고, 로그인 실패를 이메일 기준으로 세기 위한 `login_failures` 테이블 하나를 더한다(research R-05).

## 기술 맥락 (Technical Context)

**언어/버전**: Java 21 (research R-01)

**주요 의존성**: Spring Boot 3.5.x(Web, Security, Data JPA, Validation, Mail), jjwt 0.12, ShedLock, MySQL Connector/J (R-01, R-03, R-13)

**저장소**: MySQL 8 — Crowfoot 문서 654에서 관리, 개발 DB `cf_u33_d1`. 프로필 사진은 `FileStorage` → 서버 디스크(D-75)

**테스트**: JUnit 5, Spring Boot Test, MockMvc, Testcontainers MySQL 8.0, GreenMail, 고정 `Clock` (R-14)

**대상 플랫폼**: Linux 서버 1대(1차), PC·모바일 브라우저(반응형)

**프로젝트 종류**: 웹 서비스(REST API + 정적 화면, 단일 Spring Boot 앱)

**성능 목표**: 계정 화면 API 응답 1초 목표, 2초 이내. 5초 넘으면 화면이 중단·안내(4.2, SC-010)

**제약**: 서버에 상태를 두지 않음(IP 요청 제한만 메모리, SCL-01). 숫자 규칙은 모두 설정값(D-68). 가입 여부가 응답 내용·시간으로 드러나지 않게(D-28, R-08)

**규모/범위**: API 18개, 화면 8개(가입, 로그인, 비밀번호 찾기, 이메일 찾기, 내 정보, 비밀번호 변경, 탈퇴, 공통 상단 메뉴), 테이블 7개 사용 + 1개 추가

## 헌장 확인 (Constitution Check)

*Phase 0 전 확인, Phase 1 설계 후 다시 확인함.*

| 원칙 | 이 계획에서 지키는 방법 | 결과 |
|---|---|---|
| I. 보안 우선 | bcrypt(R-09), JWT + HttpOnly·Secure 쿠키, localStorage 미사용, RT는 DB 해시 저장·로그아웃/비밀번호 변경 때 폐기(R-03), CSRF 쿠키 + `X-XSRF-TOKEN`(R-12), 보안 헤더 설정, 프로필 업로드 확장자·MIME·시그니처·EXIF 제거·UUID 이름(R-11), 가입·재설정·로그인 실패 응답이 가입 여부를 드러내지 않음(R-05, R-08) | 통과 |
| II. 블로그별 역할 서버 확인 | 토큰에는 회원 번호만(R-03). 탈퇴 조건의 블로그장 여부는 요청마다 `blog_members`에서 조회(data-model). 이 기능에는 블로그 관리 동작이 없음 | 통과 |
| III. 개인정보 서버에서 가림 | 이메일 찾기 결과를 서버가 가려서 응답, 원문 미포함(FR-036). 내 정보는 본인에게만 원문. 탈퇴 30일 뒤 개인정보 삭제 배치(R-13). 인증번호·임시 토큰은 쓰거나 만료되면 바로 삭제 | 통과 |
| IV. 서버에 상태를 두지 않음 | 인증번호·RT·로그인 실패 횟수·임시 토큰 모두 DB(login_failures 추가로 없는 이메일도 DB). IP 제한만 메모리, `RateLimiter` 인터페이스로 분리(R-06). `FileStorage` 인터페이스(R-11). 04:00 배치에 ShedLock(R-13). 제한값 설정 파일 + 환경변수 | 통과 |
| V. 명세와 결정이 먼저 | 모든 API·규칙이 FR 번호와 D-번호로 연결(contracts). 문서에 없던 값은 D-97로 사용자 확인 후 사용. 버전·라이브러리 선택은 규칙이 아니라 구현 세부로 research에 기록 | 통과 |
| VI. 단순하게 시작 | 단일 모듈, 메모리 고정 창 요청 제한, Flyway 없이 Crowfoot을 스키마 원천으로(R-02), 서버 디스크 저장 | 통과 |

**설계 후 다시 확인**: data-model과 contracts에서 새로 생긴 위반 없음. 단, `login_failures` 추가는 ERD 변경이라 Crowfoot plan_migration 결과를 사용자에게 보여 승인을 받은 뒤 반영한다(헌장 V, Crowfoot 규칙). `users.login_fail_count`, `users.locked_until` 삭제는 삭제 문장이라 별도 승인.

## 프로젝트 구조 (Project Structure)

### 문서 (이 기능)

```text
specs/001-member-auth/
├── spec.md              # 명세 (D-97 반영)
├── clarify-questions.md # 확인 질문과 근거
├── plan.md              # 이 파일
├── research.md          # Phase 0
├── data-model.md        # Phase 1
├── quickstart.md        # Phase 1
├── contracts/
│   └── member-auth-api.yaml
└── tasks.md             # Phase 2 (/speckit-tasks에서 만듦)
```

### 소스 코드 (저장소 루트)

```text
build.gradle
settings.gradle
.env.example
docs/04-design/schema.sql                 # Crowfoot export_ddl 결과 (테스트 스키마)

src/main/java/com/mainblog/
├── MainBlogApplication.java
├── common/
│   ├── config/          # SecurityConfig(CSRF, 보안 헤더, 쿠키), ClockConfig, AsyncConfig, SchedulingConfig(ShedLock)
│   ├── error/           # ErrorResponse, GlobalExceptionHandler, ErrorCode
│   ├── ratelimit/       # RateLimiter, InMemoryRateLimiter, RateLimitFilter
│   ├── storage/         # FileStorage, LocalDiskFileStorage, ImageSanitizer
│   ├── mail/            # MailSender 래퍼(비동기), 메일 템플릿
│   └── masking/         # EmailMasker (4.4)
├── auth/
│   ├── api/             # AuthController(가입·로그인·로그아웃·refresh·extend·session), PasswordResetController, FindEmailController
│   ├── application/     # SignupService, LoginService, TokenService, PasswordResetService, FindEmailService, CaptchaVerifier
│   ├── domain/          # EmailVerification, RefreshToken, LoginFailure, PasswordResetCode, PasswordResetToken (+ Repository)
│   └── security/        # JwtProvider, JwtAuthenticationFilter, ActivityTrackingFilter, AuthCookies, CodeHasher
├── member/
│   ├── api/             # MemberController(me, nickname-availability, password, profile-image, withdrawal)
│   ├── application/     # MemberService, WithdrawalService, NicknamePolicy, PasswordPolicy
│   └── domain/          # User, UserAgreement, ProfileImage(images), UserRepository …
└── batch/
    └── DailyCleanupJob.java   # 04:00 만료 RT·login_failures 삭제, 탈퇴 30일 개인정보 삭제

src/main/resources/
├── application.yml      # 설정값 (data-model.md "설정값" 표)
└── static/
    ├── js/api.js        # fetch 래퍼: X-XSRF-TOKEN, X-User-Activity, 401 시 refresh 1회 재시도
    ├── js/session.js    # 상단 메뉴 로그인 상태, 30분 만료 5분 전 안내 창
    ├── signup.html, login.html, find-password.html, find-email.html
    └── me/index.html, me/password.html, me/withdraw.html

src/test/java/com/mainblog/
├── auth/  member/       # 서비스 단위 테스트(고정 Clock), 통합 테스트(Testcontainers + GreenMail)
└── contract/            # MockMvc로 contracts/member-auth-api.yaml 응답 형식 확인
```

**구조 결정**: 단일 Spring Boot 애플리케이션을 저장소 루트에 둔다. 화면은 정적 HTML + JS라(D-66) 별도 프론트엔드 프로젝트 없이 `static/`에 둔다. 패키지는 기능(auth, member) 단위로 나누고, 002부터는 `blog`, `board` 등을 같은 방식으로 더한다.

## 구현 전에 할 일

1. **ERD 변경 승인**: `login_failures` 추가와 `email_verifications.fail_count` NOT NULL을 Crowfoot에 반영하고 plan_migration 결과를 사용자에게 보여 승인을 받는다(R-05).
2. **DB 정렬 확인**: `cf_u33_d1`의 `users.nickname` 정렬 규칙이 대소문자 무시인지 확인한다(R-10).
3. **schema.sql 저장**: Crowfoot export_ddl 결과를 `docs/04-design/schema.sql`로 저장해 테스트가 쓰게 한다(R-02).

## 복잡도 기록 (Complexity Tracking)

헌장 위반 없음.
