# 001 회원 기능 확인 가이드 (Quickstart)

구현이 끝난 뒤 이 기능이 명세대로 동작하는지 손으로, 그리고 테스트로 확인하는 방법이다.
API 형식은 [contracts/member-auth-api.yaml](contracts/member-auth-api.yaml), 테이블 규칙은 [data-model.md](data-model.md)를 본다.

## 준비

| 항목 | 값 |
|---|---|
| JDK | 21 |
| DB | 로컬: Docker MySQL 8.0에 `docs/04-design/schema.sql`. 공유 개발 DB: Crowfoot 매니지드 MySQL `cf_u33_d1`(접속 정보는 Crowfoot 화면의 데이터베이스 탭) |
| 메일 | 로컬은 GreenMail(SMTP 3025, 웹 없음) 또는 MailHog. 실제 발송은 Gmail 앱 비밀번호 |
| Turnstile | 로컬·테스트는 Cloudflare 테스트 키(항상 통과 / 항상 실패) |

환경변수(`.env.example`로 제공):

```text
DB_URL, DB_USERNAME, DB_PASSWORD
JWT_SECRET                      # 32바이트 이상
CODE_HASH_SECRET                # 인증번호 HMAC 키
MAIL_HOST, MAIL_PORT, MAIL_USERNAME, MAIL_PASSWORD
TURNSTILE_SITE_KEY, TURNSTILE_SECRET_KEY
FILE_STORAGE_ROOT               # 프로필 사진 저장 폴더
```

## 실행

```bash
./gradlew test                 # 단위·통합 테스트 (Testcontainers MySQL, GreenMail)
./gradlew bootRun              # http://localhost:8080
```

`ddl-auto=validate`라 엔티티와 DB가 다르면 시작에 실패한다. 실패하면 Crowfoot 문서와 DB가 같은지 먼저 본다(research R-02).

## 확인 시나리오

각 시나리오는 명세의 사용자 스토리 인수 시나리오와 성공 기준(SC)에 대응한다. 시간 경계는 테스트에서 `Clock`을 고정해 확인한다.

| # | 확인할 것 | 방법 | 기대 결과 | 근거 |
|---|---|---|---|---|
| 1 | 가입 여부가 드러나지 않음 | 새 이메일과 가입된 이메일(`minji@example.com`)로 `POST /api/auth/signup/email-code` | 둘 다 202, 본문·헤더 같음. 메일함에는 인증번호 / "이미 가입" 안내 | SC-001 |
| 2 | 인증번호 경계 | 10분 경과, 5번째 오류, 재발송 뒤 이전 번호 | 모두 400 CODE_INVALID | SC-002 |
| 3 | 인증 뒤 30분 | 인증 후 31분에 `POST /api/auth/signup` | 403 EMAIL_NOT_VERIFIED | FR-007 |
| 4 | 입력 규칙 | 비밀번호 `abcd1234`, 닉네임 `Admin1`·`abc`(이미 `ABC` 있음), 전화 `0212345678`, 이름 `김` | 모두 400 또는 409 | SC-011 |
| 5 | 동시 가입 | 같은 닉네임으로 가입 요청 2개 동시 전송 | 계정 1개만 생김 | SC-009 |
| 6 | 로그인 실패 | 같은 이메일 3번 실패 → 4번째 captchaToken 없이 | 400 CAPTCHA_REQUIRED | SC-003 |
| 7 | 잠금 | 5번 실패 → 올바른 비밀번호 | 423 LOCKED. 5분 뒤 성공 | SC-003 |
| 8 | 없는 이메일 | 없는 이메일로 5번 실패 | 6·7번과 같은 응답 | D-97 |
| 9 | 30분 무활동 | 유지 미체크 로그인 → 폴링만 31분 → `POST /api/auth/refresh` | 401 | SC-005 |
| 10 | 14일 고정 | 유지 체크 로그인 → 13일째 refresh 성공 → 14일 1분 뒤 401 | | SC-005, D-97 |
| 11 | 로그아웃 뒤 RT | 로그아웃 전 RT 값을 복사해 refresh | 401 | SC-004 |
| 12 | 비밀번호 변경 | 기기 A·B 로그인 → A에서 변경 | A는 계속 로그인, B의 refresh는 401 | FR-044, D-97 |
| 13 | 재설정 | 잠긴 계정에서 재설정 | 모든 기기 로그아웃, 잠금 풀림 | FR-033 |
| 14 | 재설정 메일 | 없는 이메일로 재설정 요청 | 202, 메일 없음 | FR-030, D-97 |
| 15 | 이메일 찾기 | 샘플 회원 `김민지`·`010-0000-0002` | `mi***@example.com`, 응답 어디에도 원문 없음 | SC-006 |
| 16 | 이메일 찾기 제한 | 같은 IP 6번째 | 429 | SC-007 |
| 17 | 탈퇴 막기 | 블로그장 `minji@example.com`(개발 일지)으로 탈퇴 | 409 OWNS_BLOGS, 블로그 목록 표시 | SC-008 |
| 18 | 탈퇴·재가입 | 블로그장이 아닌 회원 탈퇴 → 같은 이메일로 바로 가입 | 가입 성공, 이전 닉네임은 30일 동안 쓸 수 없음 | SC-008, D-97 |
| 19 | 프로필 사진 | 3MB 초과, svg, 확장자만 jpg인 파일 | 모두 400. 정상 jpg는 EXIF 없이 저장 | FR-043 |
| 20 | 응답 시간 | 위 API 각각 | 1초 목표, 2초 이내 | SC-010 |

샘플 데이터: Crowfoot DB에 회원 5명(1 관리자, 2 민지·블로그장, 3 준호, 4 소라, 5 태양)이 있다. 비밀번호 해시는 가짜 값이라 로그인 시나리오는 가입으로 만든 계정이나 테스트 픽스처를 쓴다.

## 확인 결과

### 2026-10-08 (T074)

**자동 테스트**: `./gradlew test` 전체 통과(19개 테스트 클래스). 시간 경계는 `MutableClock`으로 고정해 확인했다.

| # | 결과 | 확인한 테스트 |
|---|---|---|
| 1 | 통과 | `SignupIntegrationTest` 시나리오1, 시나리오2_SC001 |
| 2 | 통과 | `SignupIntegrationTest` 시나리오3·4·5_SC002 |
| 3 | 통과 | `SignupIntegrationTest` FR007_인증_뒤_31분이면_403 |
| 4 | 통과 | `SignupIntegrationTest` 중복_닉네임·예약어_비밀번호, `NicknamePolicyTest`, `PasswordPolicyTest`, `MemberInputNormalizerTest` |
| 5 | 통과 | `SignupIntegrationTest` SC009_같은_닉네임으로_동시에_가입하면_하나만_생긴다 |
| 6 | 통과 | `LoginIntegrationTest` 시나리오3_SC003 |
| 7 | 통과 | `LoginIntegrationTest` 시나리오4_SC003 |
| 8 | 통과 | `LoginIntegrationTest` D97_없는_이메일도_같은_응답과_같은_잠금_안내 |
| 9 | 통과 | `SessionLifetimeIntegrationTest` 시나리오5·6 |
| 10 | 통과 | `SessionLifetimeIntegrationTest` 시나리오8_SC004 |
| 11 | 통과 | `SessionLifetimeIntegrationTest` 시나리오9 |
| 12 | 통과 | `MyInfoIntegrationTest` 시나리오4 |
| 13 | 통과 | `PasswordResetIntegrationTest` 시나리오6_SC004 |
| 14 | 통과 | `PasswordResetIntegrationTest` 시나리오1_SC001 |
| 15 | 통과(픽스처) | `FindEmailIntegrationTest` 시나리오1·4, `EmailMaskerTest`. Crowfoot 샘플 회원 대신 테스트 픽스처로 같은 형식을 확인 |
| 16 | 통과 | `FindEmailIntegrationTest` 시나리오7_SC007 |
| 17 | 통과(픽스처) | `WithdrawalIntegrationTest` 시나리오3·4_SC008. 샘플 블로그장 대신 테스트에서 만든 블로그로 확인 |
| 18 | 통과 | `WithdrawalIntegrationTest` 시나리오5_SC008 |
| 19 | 통과 | `ProfileImageUploadTest` 전체(jpg EXIF GPS 제거, webp EXIF 청크 제거, 3MB 초과·svg·확장자 위장 거부) |
| 20 | 통과 | `AuthResponseTimeTest`(2초 이내, 가입된·안 된 이메일 응답 시간 차이 150ms 이내) |

계약 대조: `OpenApiConformanceTest`가 계약의 18개 경로·메서드가 모두 매핑돼 있고, 계약 밖 API는 `GET /api/public-config`뿐임을 확인했다.

**로컬 실행(손으로)**: Docker MySQL 8.0에 `docs/04-design/schema.sql`을 넣고 `./gradlew bootRun`으로 띄워 확인했다.

- 시작 성공(`ddl-auto=validate` 통과).
- 화면 10개(`/`, 로그인, 가입, 이메일 찾기, 비밀번호 찾기, 내 정보, 비밀번호 변경, 탈퇴, 개인정보 처리방침, `api.js`) 모두 200.
- `X-XSRF-TOKEN` 없이 보낸 POST는 403, 붙이면 처리된다.
- 가입 발송·재설정 발송 202, 없는 이메일 로그인 401, 이메일 찾기 200(빈 목록), 모두 0.4초 안.
- 응답 헤더: CSP, `X-Frame-Options: DENY`, `X-Content-Type-Options: nosniff`, `Referrer-Policy` 확인. HSTS는 HTTPS에서만 붙는다.
- 메일 서버 없이 돌려 메일 발송은 실패했고, 로그에는 예외 종류만 남고 받는 주소는 남지 않았다.

브라우저로 화면을 눌러 보는 확인(Turnstile 위젯, 30분 경고 창)은 하지 않았다.
