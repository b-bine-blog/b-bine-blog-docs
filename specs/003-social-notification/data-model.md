# 003 소셜·알림 데이터 모델 (Phase 1)

**날짜**: 2026-10-08 | **명세**: [spec.md](spec.md) | **조사**: [research.md](research.md)

ERD는 Crowfoot 문서 654에서 배포한 스키마(`docs/04-design/schema.sql`)를 그대로 쓴다. **DB 구조 변경은 없다**(research R-18).
새로 다루는 테이블은 JPA 엔티티 없이 `JdbcTemplate` SQL로 읽고 쓴다(004와 같음). 002의 `blog_subscriptions`·`blog_closing_notices`, 004의 `user_blocks`·`follows` 읽기는 지금 코드 그대로 둔다.

## 관계

```text
users 1 ─ N follows (follower_id, FK)        users 1 ─ N follows (followee_id, FK 선 없음, idx_follows_followee_id)
users 1 ─ N user_blocks (blocker_id, FK)     users 1 ─ N user_blocks (blocked_id, FK 선 없음)
users 1 ─ N blog_subscriptions N ─ 1 blogs
users 1 ─ N reports (reporter_id)            blogs 1 ─ N reports (blog_id, 메인 프로필 신고는 NULL)
reports.target_type + target_id → users / blogs / posts / comments (FK 선 없음, 당시 내용은 target_snapshot)
users 1 ─ N notifications (recipient_id)     notifications.actor_id → users (FK 선 없음)
users 1 ─ 0..1 notification_settings
읽기만: blog_members, blog_join_requests(차단 자동 거절은 002 JoinService로), posts, comments, blogs
```

## users (프로필에 쓰는 칸)

| 필드 | 규칙 | 근거 |
|---|---|---|
| nickname | 프로필·목록·알림 문구에 보이는 유일한 이름 | FR-001, FR-033 |
| bio | 앞뒤 공백 제거 후 0~500자(`social.bio.max-length`, 코드 포인트), 글자 종류 제한 없음, 줄바꿈 허용. 빈 값은 NULL | FR-004, D-102 #7 |
| role | ADMIN이면 팔로우·구독·차단·신고 403 `ADMIN_NOT_ALLOWED`, 프로필 404 | D-90, research 가정 1 |
| status | WITHDRAWN이면 프로필 404, 팔로우·차단·신고 대상 아님, 알림 받지 않음 | D-102 #16 |
| email, name, phone | 003의 어떤 응답에도 넣지 않는다 | FR-002, D-22 |

## follows (팔로우)

- 한 쌍에 한 건(`uk_follows_follower_id_followee_id`). 팔로우는 `INSERT IGNORE`, 취소는 `DELETE`(FR-008, SC-007).
- `follower_id = followee_id`는 서비스에서 400 `SELF_NOT_ALLOWED`(D-102 #1).
- 두 회원 사이에 어느 방향이든 `user_blocks`가 있으면 만들 수 없다(403 `FOLLOW_NOT_ALLOWED`, D-102 #11).
- 지워지는 때: 취소, 차단(두 방향 모두, FR-019), 탈퇴(두 방향 모두, D-102 #16). 차단을 풀어도 되살리지 않는다(D-102 #10).
- 목록 정렬: `created_at DESC, id DESC`, 20명씩(D-102 #9).

## blog_subscriptions (블로그 구독, 002에서 만듦)

- 한 쌍에 한 건(`uk_blog_subscriptions_user_id_blog_id`). 비공개로 바뀌어도 유지(D-37).
- 만들 수 있는 사람: 그 블로그를 볼 수 있는 로그인 회원(002 `BlogPermission.VIEW`), 관리자 제외, 블로그장 제외(D-102 #1, #2).
- 지워지는 때: 취소, 블로그가 폐쇄되는 순간(`closeIfDue`, D-102 #5), 탈퇴(D-102 #16).

## user_blocks (차단)

- 한 쌍에 한 건(`uk_user_blocks_blocker_id_blocked_id`). 자기 자신 차단은 400 `SELF_NOT_ALLOWED`.
- 차단할 때 같은 트랜잭션에서: 두 방향 `follows` 삭제, 차단한 회원이 블로그장인 블로그의 대기 중 참여 신청 자동 거절(D-102 #13).
- 숨김은 차단한 쪽에서만(004 `PostVisibility.notBlocked`, `CommentService`), 같은 블로그 멤버는 예외(D-36, D-102 #11).
- 해제는 행 삭제. 탈퇴하면 두 방향 모두 삭제(D-102 #16).

## reports (신고)

| 필드 | 규칙 | 근거 |
|---|---|---|
| reporter_id | 로그인 회원(관리자 아님). 탈퇴해도 행은 1년 남고 관리자 화면에서 "탈퇴한 회원" | D-102 #16, D-60 |
| target_type / target_id | USER, BLOG, POST, COMMENT + 번호 | FR-022, D-85 |
| blog_id | BLOG는 그 블로그, POST·COMMENT는 글의 블로그, 블로그 안 USER 신고는 요청의 blogId, 메인 프로필 USER 신고는 NULL | FR-023, FR-024 |
| target_snapshot | 신고 당시 내용 JSON(아래). 이메일·이름·전화번호 없음 | FR-027, D-85 |
| reason | `SPAM`, `ABUSE`, `SEXUAL`, `PRIVACY`, `COPYRIGHT`, `OTHER` 중 하나(`social.report.reasons`) | D-102 #14 |
| reason_detail | 앞뒤 공백 제거 후 0~500자, `OTHER`면 1자 이상 필수 | D-102 #14 |
| route | 아래 접수처 표 | D-93 |
| status / result / handled_by / handled_at | 003은 PENDING으로 넣기만 한다. 처리는 002(BLOG)·005(ADMIN) | FR-026 |
| created_at | 2주 제한 기준 | FR-025 |

### 접수처 (신고하는 순간의 blog_members로 판단)

| 대상 | route |
|---|---|
| BLOG | ADMIN |
| POST·COMMENT, 작성자가 지금 그 블로그의 블로그장 | ADMIN |
| POST·COMMENT, 그 밖 | BLOG |
| USER + blogId, 대상이 그 블로그의 블로그장 | ADMIN |
| USER + blogId, 대상이 그 블로그의 멤버·부블로그장 | BLOG |
| USER, blogId 없음(메인 프로필) | ADMIN |

- 블로그 안 USER 신고의 대상이 그 블로그 멤버가 아니면 404 `NOT_FOUND`, 공지 글은 400(research 가정 5).
- 자기 자신·내 글·내 댓글·내가 블로그장인 블로그는 400 `SELF_NOT_ALLOWED`(D-102 #1).

### 2주 제한

- 같은 `reporter_id` + `target_type` + `target_id`의 `created_at`이 14일(`social.report.repeat-after`) 안이면 409 `REPORT_TOO_SOON` + `reportableAt`.
- 신고자 `users` 행을 `FOR UPDATE`로 잠그고 확인 → 넣기(동시 요청 한 건, SC-008). 확인 조회는 `idx_reports_reporter_id_target_type_target_id_created_at`.

### target_snapshot

| 대상 | 저장 내용 |
|---|---|
| USER | `{"nickname": ..., "bio": ...}` |
| BLOG | `{"name": ..., "address": ..., "description": ...}` |
| POST | `{"title": ..., "content": 마크다운 원문, "authorNickname": ..., "blogId": ...}` |
| COMMENT | `{"content": ..., "authorNickname": ..., "postId": ...}` |

### 상태 전이

```text
(접수, 003) PENDING ──블로그장·멤버 관리 부블로그장 처리(002, route=BLOG)──▶ DONE + REPORT_RESOLVED 알림
            PENDING ──메인 관리자 처리(005, route=ADMIN)──────────────────▶ DONE + REPORT_RESOLVED 알림
DONE ──1년 뒤 04:00(005, D-103 #19)──▶ (행 삭제)
```

## notifications (알림)

| 필드 | 규칙 | 근거 |
|---|---|---|
| recipient_id | 받는 회원. 본인만 조회·읽음·삭제(남의 것은 404) | FR-033 |
| notification_type / tab | 아래 알림 종류 표 | FR-029, 3.6 |
| target_type / target_id | 이동할 곳(link) 계산에 쓴다 | FR-033, D-102 #21 |
| actor_id | 행동한 회원. 차단 확인에 쓴다. 화면에는 `content` 안의 닉네임으로만 | FR-033, D-102 #11 |
| content | 300자 이내 문구. 행동한 회원은 닉네임으로만 | FR-033 |
| event_key | `(recipient_id, event_key)` 유니크로 같은 알림 한 번 | FR-035 |
| is_read | 알림 하나를 누르거나 "모두 읽음"일 때만 TRUE | FR-030, D-102 #18 |
| created_at | 정렬(최신순)과 보관 기간 기준 | FR-029, FR-056 |

- 목록: 최신순(`id DESC`) 20개, `before` 커서로 "더 보기"(D-102 #17).
- 삭제: 회원이 지우면 바로 행 삭제(D-102 #28). 04:00에 보관 기간(30일, 설정 7일) 지난 행 삭제(FR-056, D-102 #27).
- 안 읽은 개수: 100에서 멈춰 세고 화면은 "99+"(D-102 #20).

### 알림 종류 → 탭 → 끄는 설정 → 받는 사람

| notification_type | 저장 tab | 화면 탭 | 끄는 설정(컬럼) | 받는 사람 | 차단 확인 | 만드는 곳 | 근거 |
|---|---|---|---|---|---|---|---|
| POST_COMMENT | COMMENT | 댓글 | post_comment | 글 작성자(본인 제외) | O | 004 CommentService | FR-036 |
| COMMENT_REPLY | COMMENT | 댓글 | comment_reply | 답한 대상 회원(본인 제외) | O | 004 CommentService | FR-037 |
| POST_LIKE | LIKE | 좋아요 | post_like | 글 작성자(본인 제외) | O | 004 LikeService | FR-038 |
| NEW_FOLLOWER | FOLLOW | 팔로우·구독 | new_follower | 팔로우받은 회원 | O | **003 FollowService** | FR-039 |
| BLOG_SUBSCRIBED | SUBSCRIBE | 팔로우·구독 | blog_subscribed | 그 블로그의 블로그장 | O | **003 SubscriptionService 보강** | FR-040 |
| JOIN_REQUESTED | BLOG | 블로그 | join_request | 블로그장, 멤버 관리 권한 부블로그장 | O | 002 JoinService | FR-041 |
| JOIN_APPROVED / JOIN_REJECTED | BLOG | 블로그 | join_result | 신청한 회원(차단 자동 거절도 같음) | X | 002 JoinService, **003 차단 때** | FR-042, FR-020 |
| BLOG_CLOSED_REQUEST_REJECTED | BLOG | 블로그 | 없음 | 폐쇄 때 자동 거절된 신청자·문의자 | X | 002 | D-98 #15 |
| DELEGATION_REQUESTED | OPERATION → **BLOG(확인 뒤)** | 블로그 | 없음 | 받는 멤버 | X | 002 DelegationService | FR-043, research R-03 |
| DELEGATION_ACCEPTED / _REJECTED / _CANCELED | OPERATION → **BLOG(확인 뒤)** | 블로그 | 없음 | 요청한 블로그장 | X | 002 DelegationService | FR-044 |
| BLOG_CLOSING | BLOG | 블로그 | 없음 | 블로그장 뺀 멤버 + 구독자(보낼 때 다시 계산, 한 번만) | X | 002 BlogClosingService | FR-045, FR-046, D-102 #22 |
| BLOG_CLOSING_WITHDRAWN | BLOG | 블로그 | 없음 | 같은 대상 | X | 002 BlogClosingService | FR-047 |
| BLOG_PRIVATE | BLOG | 블로그 | 없음 | 구독자 모두(바꾼 본인 제외) | X | 002 BlogService(**본인 제외 보강**) | FR-048, D-102 #25 |
| APPEAL_RELEASED / APPEAL_REJECTED | OPERATION → **BLOG(확인 뒤)** | 블로그 | 없음 | 문의한 회원 | X | 002 AppealService | FR-049 |
| POST_DELETED | OPERATION | 운영 | 없음 | 남이 지운 글의 작성자 | X | 004 PostService | FR-050 |
| REPORT_RESOLVED | OPERATION | 운영 | report_result | 신고한 회원 | X | **003 ReportResultNotifier**(002·005가 부름) | FR-051 |
| MEMBER_WARNED / _SUSPENDED / _UNSUSPENDED / _KICKED | OPERATION | 운영 | 없음 | 대상 회원 | X | 002 SanctionService | FR-052 |
| 블로그장 경고·권한 박탈 | OPERATION | 운영 | 없음 | 그 블로그장 | X | 005가 종류를 더함 | FR-052, ADM-07 |
| NOTICE | OPERATION | 운영 | notice | 관리자 아닌 활동 회원 | X | 004 NoticeService | FR-053 |

- 끌 수 있는 9가지 = 설정 컬럼이 있는 종류(post_comment, comment_reply, post_like, new_follower, blog_subscribed, join_request, join_result, report_result, notice). 처음에는 모두 켜짐(D-102 #26).
- "차단 확인 O": 받는 사람이 행동한 회원(`actor_id`)을 차단했으면 만들지 않는다(research R-07, 가정 2).
- 탈퇴한 회원에게는 어떤 알림도 만들지 않는다(research R-07).
- 005가 더하는 운영 알림(내 글 숨겨짐·복구, 블로그 숨김 등, D-103 #7·#9·#11·#15)도 같은 표 규칙(탭 OPERATION 등)을 따른다.

### event_key (003이 새로 쓰는 것)

| 종류 | event_key | 뜻 |
|---|---|---|
| NEW_FOLLOWER | `NEW_FOLLOWER:{팔로우한 회원}` | 다시 팔로우해도 한 번(D-102 #3) |
| BLOG_SUBSCRIBED | `BLOG_SUBSCRIBED:{블로그}:{회원}` | 다시 구독해도 한 번(D-102 #3) |
| JOIN_REJECTED(차단 자동 거절) | `JOIN_RESULT:{신청 번호}` | 002 일반 거절과 같은 키 |
| REPORT_RESOLVED | `REPORT_RESOLVED:{신고 번호}` | 002와 같은 키 |

### 이동할 곳 (link)

research R-06 표. 대상이 없어졌으면 null → 화면 "볼 수 없는 내용입니다".

## notification_settings (알림 설정)

| 필드 | 규칙 | 근거 |
|---|---|---|
| post_comment … notice (9개) | TRUE/FALSE. 행이 없으면 모두 TRUE | FR-054, D-102 #26 |
| retention_days | 30(기본) 또는 7. DB CHECK와 같다 | FR-057, D-102 #27 |

- 회원당 한 행(`uk_notification_settings_user_id`). 처음 저장할 때 `INSERT ... ON DUPLICATE KEY UPDATE`로 만든다.
- 끌 수 없는 알림을 끄는 키가 오면 400 `VALIDATION_FAILED`(code `NotAllowed`).
- 블로그 단위 설정은 없다(D-102 #29).

## 권한표 (서버 확인 기준)

| 동작 | 비회원 | 회원 | 본인 | 메인 관리자 |
|---|---|---|---|---|
| 프로필·팔로워 수 보기 | O(공개 블로그만) | O(공개 블로그만) | O(모든 블로그) | O(공개 블로그만) |
| 팔로워·팔로잉 목록 | O | O | O | O |
| 소개 고치기 | X | 본인만 | O | 본인만 |
| 팔로우·취소 | X(401) | O(자기 자신 X, 차단 사이 X) | — | X(403) |
| 블로그 구독·취소 | X(401) | 볼 수 있는 블로그만, 블로그장 X | — | X(403) |
| 차단·해제·차단 목록 | X(401) | O(자기 자신 X) | — | X(403, 가정 1) |
| 신고 | X(401) | 볼 수 있는 대상만, 자기 것 X, 같은 대상 14일 1번 | — | X(403) |
| 알림 목록·개수·읽음·삭제 | X(401) | 본인 알림만 | — | 본인 알림만 |
| 알림 설정 | X(401) | 본인만 | — | 본인만 |
| 블로그 안 신고 처리 | X | 그 블로그의 MEMBER_MANAGE 권한자(002, 요청마다 DB 확인) | — | X(ADMIN 신고는 005) |

- "볼 수 있는"은 002 `BlogPermissionService.context`(공개 범위, 정지)와 004 `PostPolicy.requireReadable`를 요청마다 다시 부른다(SEC-07).
- 상대가 나를 차단했는지는 어떤 응답에도 넣지 않는다(D-102 #11).

## 설정값 (application.yml, D-68)

| 키 | 기본값 | 환경변수 | 근거 |
|---|---|---|---|
| social.follow.rate-limit / rate-window | 30 / 1m | SOCIAL_FOLLOW_RATE_LIMIT / SOCIAL_FOLLOW_RATE_WINDOW | D-102 #4 |
| social.subscribe.rate-limit / rate-window | 30 / 1m | SOCIAL_SUBSCRIBE_RATE_LIMIT / SOCIAL_SUBSCRIBE_RATE_WINDOW | D-102 #4 |
| social.list.page-size | 20 | SOCIAL_LIST_PAGE_SIZE | D-102 #9, 가정 4 |
| social.bio.max-length | 500 | SOCIAL_BIO_MAX_LENGTH | D-102 #7 |
| social.report.reasons | SPAM=스팸·광고,ABUSE=욕설·비방,SEXUAL=음란·불쾌한 내용,PRIVACY=개인정보 노출,COPYRIGHT=저작권 침해,OTHER=기타 | SOCIAL_REPORT_REASONS | D-102 #14 |
| social.report.detail-required | OTHER | SOCIAL_REPORT_DETAIL_REQUIRED | D-102 #14 |
| social.report.detail-max-length | 500 | SOCIAL_REPORT_DETAIL_MAX_LENGTH | D-102 #14 |
| social.report.repeat-after | 14d | SOCIAL_REPORT_REPEAT_AFTER | FR-025, 6.5 |
| notification.page-size | 20 | NOTIFICATION_PAGE_SIZE | D-102 #17 |
| notification.poll-interval | 30s | NOTIFICATION_POLL_INTERVAL | D-72 |
| notification.badge-max | 99 | NOTIFICATION_BADGE_MAX | D-102 #20 |
| notification.retention.default-days | 30 | NOTIFICATION_RETENTION_DEFAULT_DAYS | 4.5, FR-056 |
| notification.retention.short-days | 7 | NOTIFICATION_RETENTION_SHORT_DAYS | 6.7, FR-057 |

- `notification.retention.*`는 DB CHECK `retention_days IN (7, 30)`과 같아야 한다. 값을 바꾸려면 Crowfoot에서 CHECK도 바꾼다.
- `reason_detail`(VARCHAR(500))과 `users.bio`(VARCHAR(500)) 길이보다 큰 값으로 설정하면 앱 시작 때 실패하게 `@Max(500)`으로 검사한다.
