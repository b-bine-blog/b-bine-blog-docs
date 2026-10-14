# 001 회원 기능 조사 (Phase 0 Research)

**날짜**: 2026-10-07 | **명세**: [spec.md](spec.md) | **계획**: [plan.md](plan.md)

명세의 확인 필요 항목은 D-97로 모두 정해졌다. 여기서는 7장에 정해진 기술을 어떻게 쓸지, 문서가 정하지 않은 구현 세부(버전, 라이브러리)를 무엇으로 할지 정한다.
규칙 값(분·횟수)은 명세·결정을 그대로 따르고 여기서 새로 정하지 않는다.

---

## R-01 언어·프레임워크 버전

- **결정**: Java 21, Spring Boot 3.5.x, Gradle(Groovy DSL) 단일 모듈.
- **이유**: 7장은 Spring Boot만 정했고 버전은 없다. Java 21은 현재 LTS이고 Spring Boot 3.x의 권장 버전이다. 단일 모듈은 1차 서버 1대(4.3)와 "단순하게 시작"(헌장 VI)에 맞다.
- **검토한 다른 안**: Java 17(LTS지만 가상 스레드 등 새 기능이 없음), Maven(팀 선호가 문서에 없어 Spring Initializr 기본인 Gradle로 둠), 멀티 모듈(기능이 늘어도 1차 규모에서는 이득이 작음).
- **바꾸려면**: 팀 개발 환경이 다르면 `build.gradle`의 툴체인만 바꾸면 된다. 다른 설계에 영향이 없다.

## R-02 DB 스키마 관리

- **결정**: 스키마의 원천은 Crowfoot 문서 654이고, 바꿀 때는 Crowfoot의 plan_migration → 사용자 승인 → apply_migration으로 반영한다. 애플리케이션은 `spring.jpa.hibernate.ddl-auto=validate`로 엔티티와 스키마가 맞는지만 확인한다. 테스트용 스키마는 Crowfoot export_ddl 결과를 `docs/04-design/schema.sql`로 저장해 Testcontainers MySQL에 넣는다.
- **이유**: ERD와 운영 DB(cf_u33_d1)가 이미 Crowfoot에서 관리되고 있어 Flyway를 따로 두면 원천이 둘이 된다.
- **검토한 다른 안**: Flyway(마이그레이션 이력이 코드에 남지만 Crowfoot과 이중 관리), `ddl-auto=update`(운영 DB를 엔티티가 몰래 바꿀 수 있어 제외).

## R-03 로그인 토큰(JWT)과 쿠키

- **결정**:
  - Access Token: JWT(HS256, jjwt 0.12), 15분(D-97). 내용은 회원 번호(`sub`)와 만료 시각만 담는다(FR-027, 헌장 II). 쿠키 `AT`.
  - Refresh Token: 32바이트 무작위 값. DB에는 SHA-256 해시만 저장(`refresh_tokens.token_hash`). 쿠키 `RT`, 경로 `/`. (처음에는 `/api/auth`로 정했으나, R-04의 활동 필터가 `/api/auth` 밖의 요청에서도 그 기기의 RT를 알아야 해서 `/`로 바꿈. HttpOnly라 스크립트는 읽지 못한다. 2026-10-08 구현 중)
  - 쿠키는 모두 `HttpOnly; Secure; SameSite=Lax; Path=/`.
  - "로그인 유지" 미체크: 쿠키에 Max-Age를 주지 않아(세션 쿠키) 브라우저를 닫으면 사라진다. `refresh_tokens.expires_at`은 로그인 + 14일로 두되, 갱신 때 `last_active_at + 30분`이 지났으면 거부한다.
  - "로그인 유지" 체크: 쿠키 Max-Age 14일, `expires_at` = 로그인 시각 + 14일 고정(D-97). 갱신해도 늘지 않는다.
  - Refresh Token은 갱신할 때마다 새 값으로 바꾸고 이전 값은 폐기한다(재사용 감지 시 그 회원의 모든 토큰 폐기).
- **이유**: SEC-04, D-53, D-61, D-82. 토큰에 역할을 담지 않아 블로그별 역할은 매 요청 DB에서 확인한다.
- **검토한 다른 안**: Access Token에 역할 포함(정지·위임이 15분 늦게 반영돼 헌장 II 위반), Refresh Token 원문 저장(DB 유출 시 바로 로그인 가능).

## R-04 30분 무활동 판단

- **결정**: 공통 `api.js`가 사용자가 직접 한 행동의 요청에만 `X-User-Activity: 1` 헤더를 붙인다. 알림 폴링(D-72)은 붙이지 않는다. 서버 필터는 이 헤더가 있는 요청에서 그 기기의 `refresh_tokens.last_active_at`을 갱신하되, DB 부담을 줄이려고 1분에 한 번만 쓴다. 글쓰기 화면은 입력이 있으면 5분마다 `POST /api/auth/extend`를 보낸다(D-97). 만료 5분 전 안내 창은 화면이 마지막 활동 시각으로 계산한다.
- **이유**: D-62가 "직접 한 행동만 활동으로 센다"로 정했다. 서버가 요청 종류를 경로만으로 구별하기 어려워 화면이 표시하게 한다.
- **검토한 다른 안**: 모든 요청을 활동으로 셈(D-62 위반), 폴링 경로만 제외 목록으로 관리(새 자동 요청이 생길 때마다 서버 목록을 고쳐야 함).

## R-05 로그인 실패 횟수와 잠금 (ERD 변경 필요)

- **결정**: 실패 횟수와 잠금은 회원이 아니라 **입력한 이메일(소문자) 기준**으로 센다. 새 테이블 `login_failures(email, fail_count, locked_until, last_failed_at)`를 둔다. 가입되지 않은 이메일로 실패해도 똑같이 세어 3번째부터 사람 확인, 5번째에 5분 잠금 안내를 보인다.
- **이유**: D-97 1번이 "없는 이메일로 5번 실패해도 같은 잠금 안내"를 정했다. 지금 ERD의 `users.login_fail_count`, `users.locked_until`로는 없는 이메일의 횟수를 저장할 곳이 없다. 메모리에 두면 SCL-01(서버에 상태를 두지 않음) 위반이다.
- **ERD 변경**: `login_failures` 추가. `users.login_fail_count`, `users.locked_until`은 쓰지 않게 되며, 지우는 것은 삭제 문장이라 사용자 승인 후 따로 한다. 같은 마이그레이션에서 `email_verifications.fail_count`를 `NOT NULL`로 고친다(내보낸 DDL에서 빠진 것).
- **검토한 다른 안**: users 컬럼 유지(없는 이메일은 잠금 안내가 안 나와 가입 여부가 드러남, D-28 위반), 없는 이메일만 메모리(서버를 늘리면 서버마다 횟수가 달라짐).

## R-06 IP별 요청 제한

- **결정**: `RateLimiter` 인터페이스 + 1차 메모리 구현(고정 창, `ConcurrentHashMap`). 로그인 10분 20번(D-97), 이메일 찾기 10분 5번(USR-08). 값은 `auth.rate-limit.login=${AUTH_RATE_LIMIT_LOGIN:20}`처럼 설정값으로 둔다. 클라이언트 IP는 `X-Forwarded-For`를 믿지 않고, 프록시를 둘 때 `server.forward-headers-strategy`로 정한다.
- **이유**: SCL-01이 IP 제한만 1차에 메모리로 허용했고, 이중화 때 Redis 구현으로 바꾼다(4.3). 인터페이스로 분리하면 구현만 바꾼다.
- **검토한 다른 안**: Bucket4j(기능이 많지만 1차에는 고정 창으로 충분), DB 저장(요청마다 쓰기가 생겨 무거움).

## R-07 사람 확인 (Cloudflare Turnstile)

- **결정**: 로그인 응답에 `captchaRequired: true`를 주면 화면이 Turnstile 위젯을 띄운다. 다음 로그인 요청에 `captchaToken`을 담고, 서버가 `https://challenges.cloudflare.com/turnstile/v0/siteverify`로 확인한다. 키는 환경변수 `TURNSTILE_SITE_KEY`, `TURNSTILE_SECRET_KEY`. 테스트와 로컬은 Cloudflare가 제공하는 항상 통과 테스트 키를 쓴다.
- **이유**: SEC-13, D-79, D-97(계정 기준 3회).
- **검토한 다른 안**: 화면에서만 확인(서버가 검증하지 않으면 우회됨).

## R-08 인증번호와 메일

- **결정**: `SecureRandom`으로 6자리 숫자, bcrypt가 아닌 SHA-256 + 서버 비밀값(HMAC)으로 해시해 저장(6자리라 bcrypt 비용이 의미 없고 조회가 잦음). 메일은 `spring-boot-starter-mail`(JavaMailSender) + Gmail SMTP(D-69). 계정은 환경변수 `MAIL_USERNAME`, `MAIL_PASSWORD`(앱 비밀번호). 발송은 `@Async`로 응답과 분리해, 가입 여부에 따라 응답 시간이 달라지지 않게 한다(D-28).
- **이유**: D-10, 3.1 팀 결정 1~5.
- **검토한 다른 안**: 동기 발송(메일을 보내는 경우만 느려져 응답 시간으로 가입 여부가 드러남).

## R-09 비밀번호 해시

- **결정**: Spring Security `BCryptPasswordEncoder`(강도 10). 비밀번호 규칙은 정규식으로 서버에서 검사한다: 8~15자, 영문·숫자·특수문자(ASCII 32종) 각 1자 이상, 이 밖의 문자 불가(D-97).
- **이유**: SEC-01, SEC-02, D-81.

## R-10 닉네임 중복과 예약어

- **결정**: 닉네임은 입력 그대로 저장하고, 중복 확인은 `LOWER(nickname)` 비교로 한다. DB의 UNIQUE는 MySQL 8 기본 정렬(`utf8mb4_0900_ai_ci`, 대소문자 무시)이라 `Abc`와 `abc`를 이미 같은 값으로 막는다. 배포된 DB의 정렬 규칙을 구현 첫 작업에서 확인한다. 예약어는 소문자로 바꾼 닉네임에 예약어가 **포함**되면 막는다(D-97). 예약어 목록은 설정값(`member.nickname.reserved`)으로 둔다.
- **이유**: 6.5, D-97. 탈퇴 후 30일 동안은 `users.nickname`을 지우지 않으므로 UNIQUE가 그대로 그 닉네임을 막는다(D-97 18번).
- **주의**: `_ai_`(악센트 무시) 정렬이라 일부 한글 자모 조합이 같은 값으로 볼 수 있다. 정렬 확인 때 함께 본다.
- **확인 결과 (T005, 2026-10-07)**: `docs/04-design/schema.sql`을 MySQL 8.0.46(기본 설정)에 넣고 `SHOW FULL COLUMNS FROM users`로 본 결과, `users.nickname`의 정렬 규칙은 `utf8mb4_0900_ai_ci`로 대소문자를 무시한다. `Abc`를 넣은 뒤 `abc`를 넣으면 `uk_users_nickname` 중복 오류(1062)가 난다. 한글은 `'가'='각'`, `'한글'='한굴'`, `'ㄱ'='가'`가 모두 다른 값으로 나와 닉네임 중복에 문제가 없다. Crowfoot DDL은 정렬 규칙을 따로 적지 않아 서버 기본값을 따른다. 공유 개발 DB `cf_u33_d1`은 접속 비밀번호가 Crowfoot 화면에만 있어 직접 확인하지 못했다. 매니지드 MySQL 8 기본값이면 같은 결과다.

## R-11 프로필 사진 업로드

- **결정**: `FileStorage` 인터페이스 + `LocalDiskFileStorage`(D-75). 확장자, MIME, 파일 앞부분 시그니처(매직 넘버)를 모두 확인한다. EXIF 제거는 jpg·png·gif를 ImageIO로 다시 저장해 메타데이터를 버리고, webp는 RIFF 청크에서 `EXIF`·`XMP ` 청크만 빼서 저장한다. 저장 이름은 UUID, 원래 이름은 `images.original_name`에만 둔다.
- **이유**: FR-043, 6.3, SEC-08, D-75.
- **검토한 다른 안**: 외부 라이브러리(metadata-extractor는 읽기만, Apache Commons Imaging은 webp 쓰기 미지원).

## R-12 CSRF와 화면

- **결정**: Spring Security `CookieCsrfTokenRepository.withHttpOnlyFalse()`, 공통 `api.js`가 `XSRF-TOKEN` 쿠키를 읽어 `X-XSRF-TOKEN` 헤더로 보낸다(SEC-10). 화면은 `src/main/resources/static`의 정적 HTML + JS(D-66). 사용자 입력은 `textContent`로만 넣는다(D-64).

## R-13 04:00 배치

- **결정**: 만료된 Refresh Token 삭제(D-83)와 탈퇴 30일 뒤 개인정보 삭제(4.5)는 `@Scheduled(cron = "0 0 4 * * *", zone = "Asia/Seoul")` + ShedLock(SCL-03)으로 돈다. 001에서는 이 두 가지만 만들고, 폐쇄 처리 등은 002에서 같은 배치에 더한다. ShedLock 테이블은 Crowfoot ERD 밖에 두고 ShedLock이 요구하는 스키마로 따로 만든다.

## R-14 테스트

- **결정**: JUnit 5 + Spring Boot Test, DB가 걸리는 테스트는 Testcontainers MySQL 8.0(R-02의 schema.sql), 메일은 GreenMail, 시간은 `Clock` 빈을 주입해 고정한다(10분·30분·14일 경계 테스트용). API 계약 테스트는 MockMvc.
- **이유**: 성공 기준 SC-001~SC-011이 경계값과 응답 비교라 시간 고정과 실제 MySQL(정렬·UNIQUE·FULLTEXT)이 필요하다.
