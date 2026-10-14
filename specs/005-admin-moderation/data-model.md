# 005 메인 관리자·제재 데이터 모델 (Phase 1)

**날짜**: 2026-10-08 | **명세**: [spec.md](spec.md) | **조사**: [research.md](research.md)

ERD는 Crowfoot 문서 654에서 배포한 스키마(`docs/04-design/schema.sql`, 문서 버전 41)를 쓴다. 관리자 활동 기록(`admin_actions`), 블로그장 경고(`owner_warnings`), 권한 박탈(`owner_revocations`)은 이미 있다.
**구조 변경은 칸 2개**(`comments.deleted_by`, `owner_warnings.reason`)이고, 둘 다 NULL 허용 추가라 지우는 문장이 없다. Crowfoot에서 승인을 받은 뒤 반영한다(research R-15, plan "구현 전에 할 일").
조회는 002·004처럼 `JdbcTemplate` SQL로 하고, 새 JPA 엔티티는 만들지 않는다. 기존 `Blog` 엔티티에 숨김 메서드만 더한다.

## 관계

```text
users(role = ADMIN) 1 ─ N admin_actions (admin_id)        admin_actions N ─ 1 reports (report_id, NULL 가능)
blogs 1 ─ N owner_warnings ─ N 1 users (user_id = 경고받은 블로그장)   owner_warnings N ─ 1 reports (NULL 가능)
blogs 1 ─ N owner_revocations ─ N 1 users (user_id = 박탈된 사람)
reports (003이 만듦, route = ADMIN만 005가 처리)
고치는 칸: blogs.hidden·hidden_at·close_reason, posts.status·hidden_at·deleted_at·deleted_by,
          comments.status·deleted_at·(deleted_by 추가), blog_members.role(002 서비스로), blog_delegations.status
읽기만: users, blog_members, blog_subscriptions, blog_sanctions(1년 정리만), blog_blacklists, images
```

## 관리자 확인

| 항목 | 규칙 | 근거 |
|---|---|---|
| 관리자 | `users.role = 'ADMIN' AND status = 'ACTIVE'`. 매 요청 `JwtAuthenticationFilter`가 DB에서 읽어 `ADMIN` 권한을 붙인다 | FR-001, FR-002, D-90 |
| 만들기·회수 | 화면 없음. 운영자가 DB에서 `role`을 ADMIN·USER로 바꾼다. 회수하면 다음 요청부터 403 | D-103 #1 |
| `/api/admin/**` | URL 단위 `hasAuthority("ADMIN")` + 서비스 `AdminGuard.require` | SEC-11, research R-02 |
| `/admin` 화면 | `AdminPageController`가 role 확인 뒤 HTML. 비로그인 → 로그인 화면, 관리자 아님 → 404 | D-103 #1, research R-03 |

## admin_actions (관리자 활동 기록)

| 필드 | 규칙 | 근거 |
|---|---|---|
| admin_id | 조치한 관리자 | FR-039 |
| action_type | research R-06 표의 16가지. 스키마 설명의 13개 + BLOG_UNHIDE·POST_UNHIDE·COMMENT_UNHIDE(설명만 고침) | FR-039, D-103 #7·#10 |
| target_type / target_id | USER·BLOG·POST·COMMENT·REPORT와 그 번호 | FR-039 |
| report_id | 신고 처리로 생긴 조치면 그 신고 | FR-031 |
| memo | 0~500자. 경고 사유, 폐쇄 예정 시각, 새 블로그장 번호 등. 이메일·전화번호 원문은 넣지 않는다 | D-103 #12, D-22 |
| created_at | 조치 시각. 1년 뒤 04:00 정리에서 삭제 | D-103 #19 |

- 쓰기는 조치와 같은 트랜잭션에서만 한다(`AdminActionLog`). 고치는 SQL과 API는 없다(D-103 #20).
- 보기는 모든 관리자. 거르기: action_type, admin_id, target_type + target_id, 날짜 범위(한국 시간).

## owner_warnings (블로그장 경고)

| 필드 | 규칙 | 근거 |
|---|---|---|
| blog_id, user_id | 경고한 블로그와 그때의 블로그장 | FR-020, D-95 |
| reason (**추가**) | 앞뒤 공백 제거 후 1~500자(`admin.warning.reason-max-length`). 칸이 생기기 전에는 admin_actions.memo에만 남는다 | D-103 #12, research R-15 |
| report_id | 신고 처리로 준 경고면 그 신고 | FR-031 |
| admin_id | 경고한 관리자 | FR-039 |

- **경고 수**: `SELECT COUNT(*) FROM owner_warnings WHERE blog_id = ? AND user_id = ? AND created_at > ?(지금 - admin.warning.window)`. 블로그별, 그 사람 기준이라 블로그장이 바뀌면 새 사람은 0부터 센다(D-95, D-103 #13).
- 경고 수가 `admin.warning.revoke-threshold`(3) 이상이 되면 같은 트랜잭션에서 박탈한다(FR-021).

## owner_revocations (블로그장 권한 박탈)

| 필드 | 규칙 | 근거 |
|---|---|---|
| cause | `WARNING_3`(경고 누적) / `DIRECT_KICK`(바로 강퇴) | FR-021, FR-022 |
| new_owner_id | 자동 위임받은 부블로그장(`manager_since`가 가장 이른 사람, 같으면 id 순). 없으면 NULL | FR-023, D-17 |
| close_scheduled_at | 부블로그장이 없을 때의 폐쇄 예정 시각. 이미 폐쇄 예정이었으면 그 시각 그대로 | FR-024, D-103 #14 |
| admin_id | 처리한 관리자 | FR-039 |

### 박탈 한 번의 처리 순서 (블로그 행 잠금 안, 한 트랜잭션)

```text
1. 지금 블로그장 = 요청의 ownerId 확인 (아니면 409 OWNER_CHANGED)
2. 대기 중 위임 요청 → AUTO_CANCELED + 받는 멤버에게 DELEGATION_CANCELED 알림 (D-103 #15)
3. OwnerSuccessionService.revokeOwner
     부블로그장 있음 → 가장 먼저 된 사람 OWNER, 박탈된 사람 MEMBER (폐쇄 예정이면 그대로, D-103 #14)
     부블로그장 없음 → 이미 폐쇄 예정이면 그 시각 유지, 아니면 OWNER_REVOKED로 + 7일 04:00 예약 + 즉시 알림
                      (즉시 알림에서 박탈된 사람을 뺌)
4. owner_revocations 넣기 (3일 전·1일 전 알림이 이 행의 user_id를 빼고 보냄, US3-5)
5. 박탈된 사람에게 OWNER_REVOKED 알림
6. admin_actions: OWNER_KICK, 그리고 AUTO_DELEGATE 또는 CLOSE_SCHEDULE
```

## blogs (관리 관점)

| 필드 | 규칙 | 근거 |
|---|---|---|
| hidden / hidden_at | 숨김 TRUE·시각, 해제 FALSE·NULL. 누가 했는지는 admin_actions | FR-012, D-103 #7 |
| close_reason | 강제 폐쇄 `ADMIN`. 이미 폐쇄 예정이면 시각은 그대로 두고 `ADMIN`으로만 바꿈. `ADMIN`이면 블로그장은 철회할 수 없고 관리자만 철회(철회하면 NULL) | FR-013, D-103 #8, D-104 |

### 상태와 관리자 조치

| 블로그 상태 | 숨김 | 숨김 해제 | 강제 폐쇄 | 경고·강퇴 |
|---|---|---|---|---|
| ACTIVE | O | O(숨김일 때) | + 7일 04:00 예약, 즉시 알림 | O |
| CLOSING | O | O | 기존 시각 유지, 사유만 ADMIN, 알림 없음 | O(블로그장이 있을 때. 박탈 폐쇄 중이면 블로그장이 없어 409 OWNER_CHANGED) |
| CLOSED | 409 BLOG_ALREADY_CLOSED | 409 | 409 | 409 |

### 숨긴 블로그를 누가 보나 (002 `BlogAccessPolicy.canView` 고침)

| 보는 사람 | 숨기지 않음 | 숨김 |
|---|---|---|
| 블로그장·멤버 | 볼 수 있음 | 볼 수 있음, 글쓰기도 됨 |
| 구독자·공유 링크·비회원·다른 회원 | 공개 범위 규칙(002 R-06) | 못 봄(404) |
| 메인 관리자 | 공개 범위 규칙 | 못 봄. 관리자 화면 API로 봄 |
| 메인 목록·블로그 검색·피드·통합 검색·태그 | 공개 블로그만 | 빠짐(이미 구현) |

## posts (관리 관점)

| 필드 | 규칙 | 근거 |
|---|---|---|
| status | VISIBLE·HIDDEN·DELETED | FR-015 |
| hidden_at | 숨길 때 채우고 해제할 때 비움. 숨긴 채 지운 글은 남아 복구 때 HIDDEN으로 돌림 | D-103 #10 |
| deleted_at / deleted_by | 지운 시각·회원. `deleted_by = author_id`면 작성자가 지운 것 → 복구 불가 | D-103 #11 |

### 상태 전이 (004 그림에 관리자 조치를 더함)

```text
VISIBLE ──숨김(관리자)──▶ HIDDEN ──해제(관리자)──▶ VISIBLE
VISIBLE·HIDDEN ──삭제(작성자·POST_MANAGE·관리자)──▶ DELETED ──30일 뒤 04:00──▶ (행 삭제, 004 R-11)
DELETED ──복구(관리자, 30일 안, deleted_by ≠ author_id, 블로그 폐쇄 아님)──▶ hidden_at 있으면 HIDDEN, 없으면 VISIBLE
HIDDEN: 기간 없음(30일 정리 대상 아님, D-103 #10)
```

### 숨긴 글을 누가 보나 (004 `PostQueryService` 고침)

| 보는 사람 | 상세 | 목록·검색·피드 | 할 수 있는 것 |
|---|---|---|---|
| 작성자 본인 | `hiddenByAdmin: true`와 함께 보임 | 안 보임 | 삭제만(수정·댓글·좋아요·공유 X) |
| 블로그장·멤버·그 밖 | 404 POST_NOT_FOUND | 안 보임 | 없음 |
| 메인 관리자 | 관리자 API(`/api/admin/posts/{id}`) | 관리자 글 목록 | 해제·삭제 |

## comments (관리 관점)

| 필드 | 규칙 | 근거 |
|---|---|---|
| status | VISIBLE·HIDDEN·DELETED | FR-015 |
| deleted_at | 지운 시각. 30일 뒤 04:00 정리(004) | 4.5 |
| deleted_by (**추가**) | 지운 회원(작성자·POST_MANAGE·관리자). 004 `CommentService.delete`도 채움 | D-103 #11, research R-15 |

- 숨긴 댓글은 응답에서 뺀다. 답글이 남은 최상위 댓글은 `{ hidden: true }` 자리("관리자가 숨긴 댓글입니다")로 남긴다. *가정*
- 복구: DELETED, 30일 안, 작성자가 지운 것이 아님(칸 추가 전에는 admin_actions에 그 댓글의 COMMENT_DELETE가 있음) → VISIBLE. 알림 없음(D-103 #9·#11).

## reports (관리 관점, 003이 만듦)

| 필드 | 005에서의 규칙 | 근거 |
|---|---|---|
| route | `ADMIN`만 처리 | D-93 |
| blog_id | NULL이면 메인 프로필 회원 신고 → `NONE`만 | research R-10 *가정* |
| target_type / target_id / target_snapshot | 처리 대상 블로그장 판단, 화면에 당시 내용 | D-85 |
| status | PENDING → DONE(한 번만, 잠금 + 상태 확인) | FR-034 |
| result | 관리자: `NONE`·`OWNER_WARNING`·`OWNER_KICK`·`BLOG_CLOSE` | FR-031 |
| handled_by / handled_at | 처리한 관리자·시각 | FR-039 |

### 처리 결과별 효과

| result | 효과 | 신고자 알림 |
|---|---|---|
| NONE | 없음 | REPORT_RESOLVED "문제 없음" |
| OWNER_WARNING | 처리 대상 블로그장 경고(사유 필수) → 3번이면 박탈 | "블로그장 경고" |
| OWNER_KICK | 처리 대상 블로그장 박탈 | "블로그장 강퇴" |
| BLOG_CLOSE | 강제 폐쇄(이미 폐쇄 예정이면 사유만) | "블로그 폐쇄" |

- 처리 대상 블로그장: BLOG → 지금 블로그장, USER → target_id, POST·COMMENT → 작성자. 지금 블로그장이 아니면 409 `OWNER_CHANGED`.
- 잠금 순서: 블로그 행 → 신고 행.

## 개인정보 보기 (응답 규칙)

| 응답 | 이메일 | 전화번호 | 이름 | 닉네임 | 비밀번호 |
|---|---|---|---|---|---|
| 회원 목록 | 가림(`ab***@gmail.com`) | 없음 | 보임 | 보임 | 없음 |
| 회원 상세 | 가림 | 가림(`010-****-5678`) | 보임 | 보임 | 없음 |
| "전체 보기" 응답 | 원문 | 원문(`010-1234-5678`) | - | - | 없음 |
| 블로그·신고·활동 기록·글 목록 | 없음 | 없음 | 없음 | 보임(탈퇴는 "탈퇴한 회원") | 없음 |

- 가리기는 `EmailMasker`·`PhoneMasker`로 서버가 응답을 만들 때 한다(D-22). "전체 보기"만 원문을 주고 `PRIVACY_VIEW`를 같은 트랜잭션에 쓴다(D-103 #5).

## 복구 규칙 한눈에

| 대상 | 복구할 수 있음 | 복구 뒤 상태 | 작성자 알림 | 기록 |
|---|---|---|---|---|
| 글 | 30일 안 + 관리자·블로그장이 지움 + 블로그 폐쇄 아님 | hidden_at 있으면 HIDDEN, 없으면 VISIBLE | POST_RESTORED | RESTORE(POST) |
| 댓글 | 30일 안 + 관리자·블로그장이 지움(칸 추가 전에는 관리자가 지운 것만) + 블로그 폐쇄 아님 | VISIBLE | 없음 | RESTORE(COMMENT) |
| 사진 | 글을 복구하면 함께(글 정리 전에는 이미지 행·파일이 그대로) | - | - | - |
| 작성자가 지운 글·댓글 | X(409 NOT_RESTORABLE) | | | |
| 30일 지남 | X(행 없음, 404) | | | |

## 1년 정리 (04:00, `AdminDailyTasks`)

| 표 | 지우는 조건 | 남기는 예외 |
|---|---|---|
| admin_actions | created_at < 지금 - 1년 | 없음 |
| owner_warnings | 같음 | 없음 |
| owner_revocations | 같음 | 없음 |
| blog_sanctions | 같음 | 효력 있는 영구 정지(그 뒤 해제 없음), 블랙리스트가 가리키는 강제 퇴장 |
| reports | 같음 | 없음. 지우기 전에 남는 행의 report_id를 NULL로 |

## 통계 쿼리 (한국 시간, 시작일 = 오늘 - (daily-days - 1))

```sql
-- 회원 수 (D-103 #21: 탈퇴 제외, 관리자 제외)
SELECT COUNT(*) FROM users WHERE status = 'ACTIVE' AND role = 'USER';
-- 블로그 수 (운영 중·폐쇄 예정, 숨김 포함)
SELECT COUNT(*) FROM blogs WHERE status IN ('ACTIVE', 'CLOSING');
-- 일별 가입 수 (나중에 탈퇴해도 셈)
SELECT DATE(created_at) AS d, COUNT(*) FROM users
WHERE role = 'USER' AND created_at >= ? GROUP BY DATE(created_at);
-- 일별 글 수 (블로그 글, 상태와 관계없이. 30일 정리 전이라 지운 글도 셈)
SELECT DATE(created_at) AS d, COUNT(*) FROM posts
WHERE board_type = 'BLOG' AND created_at >= ? GROUP BY DATE(created_at);
```

- 빈 날은 0으로 채워 `daily-days`개를 오래된 날부터 준다.

## 알림 종류 (notifications에 쓰는 것)

| notification_type | tab | 받는 사람 | 끌 수 있음 | event_key | 근거 |
|---|---|---|---|---|---|
| OWNER_WARNED (**새**) | OPERATION | 경고받은 블로그장 | 없음 | `OWNER_WARNED:{warningId}` | FR-020, D-103 #12 |
| OWNER_REVOKED (**새**) | OPERATION | 박탈된 사람 | 없음 | `OWNER_REVOKED:{revocationId}` | FR-027 |
| BLOG_HIDDEN (**새**) | OPERATION | 숨긴 블로그의 블로그장 | 없음 | `BLOG_HIDDEN:{blogId}:{숨긴 시각}` | D-103 #7 |
| POST_HIDDEN (**새**) | OPERATION | 숨긴 글의 작성자 | 없음 | `POST_HIDDEN:{postId}:{숨긴 시각}` | D-103 #9 |
| POST_RESTORED (**새**) | OPERATION | 복구된 글의 작성자 | 없음 | `POST_RESTORED:{postId}:{복구 시각}` | D-103 #11 |
| POST_DELETED | OPERATION | 남이 지운 글의 작성자 | 없음 | `POST_DELETED:{postId}:{삭제 시각}`(004 키를 바꿈) | FR-017 |
| DELEGATION_CANCELED | OPERATION | 위임 요청을 받은 멤버 | 없음 | `DELEGATION_CANCELED:{delegationId}` | D-103 #15 |
| BLOG_CLOSING | BLOG | 블로그장 뺀 멤버·구독자 | 없음 | 002와 같음 | FR-013, FR-024 |
| REPORT_RESOLVED | OPERATION | 신고한 회원 | report_result | `REPORT_RESOLVED:{reportId}` | FR-033 |

- 탈퇴한 회원에게는 보내지 않는다(002·004와 같음). 알림 문구에 신고자·이메일·전화번호를 넣지 않는다.
- 이름은 005가 정한 것이다. 003 plan이 다른 이름을 정하면 그 이름을 따른다(research R-16).

## 설정값 (application.yml, D-68)

| 키 | 기본값 | 환경변수 | 근거 |
|---|---|---|---|
| admin.list.page-sizes | 10,20,50 | ADMIN_LIST_PAGE_SIZES | research 가정 13 |
| admin.list.default-size | 20 | ADMIN_LIST_DEFAULT_SIZE | research 가정 13 |
| admin.member.nickname-search-max-length | 12 | ADMIN_MEMBER_NICKNAME_SEARCH_MAX_LENGTH | 닉네임 2~12자(D-97) |
| admin.privacy-view.rate-limit / rate-window | 30 / 1m | ADMIN_PRIVACY_VIEW_RATE_LIMIT / _WINDOW | research R-04 *가정* |
| admin.warning.revoke-threshold | 3 | ADMIN_WARNING_REVOKE_THRESHOLD | ADM-07, D-30 |
| admin.warning.window | 365d | ADMIN_WARNING_WINDOW | D-95 |
| admin.warning.reason-max-length | 500 | ADMIN_WARNING_REASON_MAX_LENGTH | D-103 #12 |
| admin.revocation.reason-max-length | 500 | ADMIN_REVOCATION_REASON_MAX_LENGTH | research R-09 *가정* |
| admin.records.retention | 365d | ADMIN_RECORDS_RETENTION | 4.5, D-60, D-103 #19 |
| admin.stats.daily-days | 30 | ADMIN_STATS_DAILY_DAYS | D-103 #21. 30보다 크면 지운 글이 빠짐 |
| (재사용) board.purge-after | 30d | BOARD_PURGE_AFTER | 복구 가능 기간 = 삭제 글·댓글 보관 기간(4.5) |
| (재사용) blog.closing.purge-after | 30d | BLOG_CLOSING_PURGE_AFTER | 관리자 블로그 검색의 폐쇄 블로그 범위 |
