# 001 회원 기능 데이터 모델

**날짜**: 2026-10-07 | **원천**: Crowfoot 문서 654 "메인블로그"(https://crowfoot.java21.net/workspaces/54/models/654), 배포 DB `cf_u33_d1`

이 기능은 이미 배포된 ERD의 회원 영역 테이블 6개와 `images`(프로필 사진)를 쓰고, `login_failures` 1개를 새로 더한다(research R-05).
컬럼 타입·제약의 원천은 Crowfoot이며, 아래는 이 기능이 쓰는 규칙만 정리한다. 모든 테이블에 `id BIGINT` PK와 `created_at`, `updated_at`(DATETIME(6), DB가 채움)이 있다(REQ-001).

## 관계

```text
users 1 ──< user_agreements        (가입 동의 2건)
users 1 ──< refresh_tokens         (기기마다 1건)
users 1 ──< password_reset_codes   (재설정 인증번호)
users 1 ──< password_reset_tokens  (이메일 찾기 임시 토큰)
users 1 ──< images (owner_type=PROFILE, owner_id=users.id)  ※ FK는 uploader_id
email_verifications                (가입 전이라 users와 관계 없음, email 기준)
login_failures                     (새 테이블, 입력한 email 기준, users와 관계 없음)
```

## users (회원)

| 컬럼 | 규칙 | 근거 |
|---|---|---|
| email | 소문자로 저장, UNIQUE. 탈퇴 즉시 NULL | FR-002, FR-047 |
| withdrawn_email | 탈퇴 때 email을 옮겨 30일 보관 | 4.5 |
| password_hash | bcrypt | FR-009, D-81 |
| name | 앞뒤 공백 제거 후 2~20자, 한글·영문·공백. 변경 불가 | FR-013, D-32, D-97 |
| nickname | 2~12자 한글·영문·숫자, 대소문자 무시 UNIQUE, 예약어 포함 불가. 탈퇴 후 30일 동안 그대로 둠 | FR-010, FR-011, FR-048, D-97 |
| phone | 숫자만, `^010\d{8}$`, 1차 중복 허용 | FR-012, D-24, D-97 |
| bio | 선택. 수정은 SOC-03(별도 명세) | 4.6 |
| role | USER / ADMIN. 가입은 항상 USER | SEC-09 |
| status | ACTIVE / WITHDRAWN | USR-05 |
| withdrawn_at | 탈퇴 시각. 04:00 배치가 +30일 지나면 개인정보 삭제 | 4.5 |
| login_fail_count, locked_until | **쓰지 않음**(login_failures로 옮김). 지우는 것은 승인 후 별도 | R-05 |

**상태 변화**

```text
(가입 완료) → ACTIVE ──탈퇴──> WITHDRAWN(email=NULL, withdrawn_email=원래 이메일, 로그인 불가, 화면 비표시)
                                   └─ 30일 뒤 04:00 배치 → withdrawn_email·name·nickname·phone·bio = NULL, 프로필 이미지 삭제
```

탈퇴 조건: 그 회원이 `blog_members.role = OWNER`인 행이 하나도 없어야 한다(폐쇄 예정 블로그 포함, FR-046).

## email_verifications (가입 이메일 인증)

| 컬럼 | 규칙 | 근거 |
|---|---|---|
| email | 소문자, UNIQUE(이메일당 진행 중인 인증 1건. 다시 보내면 같은 행을 새 번호로 덮어 이전 번호 무효) | FR-005 |
| code_hash | HMAC-SHA256 | FR-004, R-08 |
| sent_at | 다시 보내기는 sent_at + 1분 뒤부터 | FR-005 |
| expires_at | sent_at + 10분 | FR-004 |
| fail_count | 5가 되면 무효. **NOT NULL로 고침**(R-05 마이그레이션) | FR-004 |
| verified_at | 맞게 입력한 시각. 가입 완료는 verified_at + 30분 안에만 | FR-007, D-97 |

가입이 끝나거나, 인증이 만료·무효가 되면 행을 지운다(4.5 예외).
이미 가입된 이메일이면 행을 만들지 않고 안내 메일만 보낸다(FR-006). 응답은 같다.

## user_agreements (가입 동의)

`(user_id, agreement_type)` UNIQUE. 가입 때 TERMS, PRIVACY 2건을 같은 트랜잭션에서 만든다. `agreed_at` = 가입 요청 시각(FR-014).

## refresh_tokens (로그인 연장 자격)

| 컬럼 | 규칙 | 근거 |
|---|---|---|
| token_hash | SHA-256, UNIQUE | R-03 |
| remember_me | 로그인 유지 체크 여부 | FR-023 |
| last_active_at | 사용자 행동 요청(X-User-Activity)마다 갱신, 1분에 한 번만 씀 | FR-024, R-04 |
| expires_at | 로그인 시각 + 14일 고정. 갱신(회전)해도 이전 값 그대로 물려받음 | FR-023, D-97 |
| revoked | 로그아웃·비밀번호 변경(현재 기기 제외)·재설정·탈퇴·재사용 감지 때 true | FR-029, FR-033, FR-044 |

**유효 조건**: `revoked = false AND expires_at > now AND (remember_me OR last_active_at + 30분 > now)`.
만료·폐기된 행은 04:00 배치가 지운다(D-83). 인덱스 `idx_refresh_tokens_expires_at`이 이미 있다.

## password_reset_codes (재설정 인증번호)

| 컬럼 | 규칙 | 근거 |
|---|---|---|
| user_id | 대상 회원 | USR-06 |
| code_hash | HMAC-SHA256 | FR-031 |
| sent_at | 다시 보내기 1분에 한 번 | FR-031, D-97 |
| expires_at | sent_at + 30분 | FR-031 |
| fail_count | 5면 무효 | FR-031 |
| used | 1회용 | FR-031 |

회원당 유효한 코드는 1건만 둔다. 새로 보내면 이전 행을 지운다. 쓰이거나 만료·무효가 되면 지운다.
화면 흐름은 두 번의 요청이다. ① 인증번호 확인(맞는지만 보고 쓰지 않음, 틀리면 fail_count 증가) ② 새 비밀번호 저장(같은 이메일·인증번호를 다시 확인하고 이때 `used = true` 후 행 삭제). 새 테이블 없이 1회용과 5번 무효 규칙이 그대로 지켜진다.

## password_reset_tokens (이메일 찾기 임시 토큰)

이메일 찾기 결과의 계정마다 1건. `token_hash` UNIQUE, `expires_at` = 발급 + 10분(FR-038). [비밀번호 재설정]은 이 토큰으로만 받고, 쓰이거나 만료되면 지운다.

## images (프로필 사진)

`owner_type = PROFILE`, `owner_id = users.id`, `uploader_id = users.id`. 회원당 유효한 프로필 사진 1장(새로 올리면 이전 행 `deleted_at` 설정). `stored_name` UUID, `content_type`은 jpg·jpeg·png·gif·webp, `size_bytes` ≤ 3MB(FR-043).

## login_failures (새 테이블, 승인 후 추가)

| 컬럼 | 타입 | 규칙 | 근거 |
|---|---|---|---|
| id | BIGINT PK auto_increment | | REQ-001 |
| email | VARCHAR(255) NOT NULL, UNIQUE | 로그인 때 입력한 이메일(소문자). 가입 여부와 무관 | D-97 1번 |
| fail_count | INT NOT NULL DEFAULT 0 | 3 이상이면 사람 확인, 5면 잠금 | FR-020, FR-022 |
| locked_until | DATETIME NULL | 5번째 실패 시각 + 5분 | FR-020 |
| last_failed_at | DATETIME NOT NULL | 오래된 행 정리용 | |
| created_at, updated_at | DATETIME(6) | | REQ-001 |

- 로그인 성공, 잠금이 풀린 뒤 다음 시도, 비밀번호 재설정 때 행을 지운다(fail_count 0, D-97 2번).
- `last_failed_at`이 1일 지난 행은 04:00 배치가 지운다.
- Crowfoot 반영: apply_schema로 테이블 추가(근거 REQ: 로그인 잠금·사람 확인 요구사항) → plan_migration 결과를 사용자에게 보여 승인 → apply_migration.

## 설정값 (D-68)

| 키 | 기본값 | 근거 |
|---|---|---|
| `auth.access-token-ttl` | 15m | D-97 |
| `auth.remember-me-ttl` | 14d | D-61 |
| `auth.idle-timeout` | 30m | D-61 |
| `auth.extend-interval` | 5m | D-97 |
| `auth.login.captcha-after` | 3 | SEC-13 |
| `auth.login.lock-after` | 5 | SEC-03 |
| `auth.login.lock-duration` | 5m | SEC-03 |
| `auth.rate-limit.login` | 20 / 10m | D-97 |
| `auth.rate-limit.find-email` | 5 / 10m | USR-08 |
| `auth.signup.code-ttl` | 10m | USR-02 |
| `auth.signup.verified-ttl` | 30m | D-97 |
| `auth.code.resend-interval` | 1m | USR-02, D-97 |
| `auth.code.max-fail` | 5 | USR-02, SEC-05 |
| `auth.reset.code-ttl` | 30m | SEC-05 |
| `auth.find-email.token-ttl` | 10m | USR-08 |
| `member.withdrawal.retention` | 30d | 4.5 |
| `member.profile-image.max-size` | 3MB | 6.3 |
