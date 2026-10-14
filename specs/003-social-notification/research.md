# 003 소셜·알림 조사 (Phase 0 Research)

**날짜**: 2026-10-08 | **명세**: [spec.md](spec.md) | **계획**: [plan.md](plan.md)

명세의 확인 필요 항목 32개는 D-102로 모두 정해졌다. 001(R-01~R-14), 002(R-01~R-17), 004(R-01~R-17)에서 정한 기술은 그대로 쓰고, 여기서는 003에서 새로 생기는 구현 방식만 정한다.
003은 002·004보다 늦게 만들어서, 소셜·알림의 상당 부분(알림 쓰기, 구독, 블로그 안 신고 처리, 폐쇄 알림, 차단·팔로우 읽기)이 이미 코드에 있다. 그래서 R-01에서 먼저 있는 것을 정리하고, 그 위에 빠진 것만 더한다.
규칙 값(개수·기간)은 명세·결정을 따르고 여기서 새로 정하지 않는다. "*가정*"으로 표시한 것은 문서와 D-102에 없어 구현 기본값으로 둔 것이며, 아래 "가정 목록"에 모았다.

---

## R-01 이미 있는 코드 (다시 만들지 않고 쓴다)

`src/main/java/com/mainblog/` 기준으로 확인했다(2026-10-08, 브랜치 `003-social-notification` = 004 위).

| 있는 것 | 위치 | 003에서 하는 일 |
|---|---|---|
| 알림 쓰기 | `common/notification/NotificationWriter` | 그대로 쓴다. 설정이 꺼져 있으면 안 만들고(설정 행이 없으면 켜짐), `(recipient_id, event_key)` 유니크 + `INSERT IGNORE`로 같은 알림을 두 번 만들지 않는다. 차단한 회원이 행동한 알림과 탈퇴 회원에게 가는 알림을 빼는 확인만 더한다(R-07) |
| 알림 종류 | `common/notification/NotificationType` | 002·004 종류 23개가 있다. `NEW_FOLLOWER`, `BLOG_SUBSCRIBED`를 더하고, 차단 확인 대상 표시를 더한다(R-03, R-07) |
| 알림 설정 확인 | `NotificationWriter.enabled` (`notification_settings` 읽기) | 그대로 쓴다. 설정 화면·API만 새로 만든다(R-08) |
| 블로그 구독 | `blog/api/SubscriptionController`, `blog/application/SubscriptionService` (`POST·DELETE /api/blogs/{blogId}/subscription`, `GET /api/me/subscriptions`) | 경로·화면은 그대로 둔다. 관리자 거부, 블로그장 자기 블로그 거부, 요청 제한, 블로그장에게 구독 알림을 더한다(R-11) |
| 내 구독 목록 | `BlogQueryService.subscribedBlogs` | 그대로 쓴다. 이미 `ACTIVE`·`CLOSING` 블로그만 보여준다. 일부 공개 블로그는 구독자면 링크 없이 들어간다(002 `BlogAccessPolicy`) |
| 비공개 전환 알림 | `BlogService.notifyPrivate` | 구독자 전체에 보낸다(D-102 #25와 같음). 바꾼 본인을 빼는 조건만 더한다 |
| 폐쇄 예정·철회 알림 | `BlogClosingService.notifyAll`, `BlogDailyTasks` (`blog_closing_notices`) | 그대로 쓴다. 보낼 때마다 대상을 다시 계산하고(D-102 #22), 밀린 3일 전·1일 전 알림도 보내며(#23), 보낸 기록으로 한 번만 간다. 폐쇄되는 순간 구독을 지우는 한 줄만 더한다(R-11, D-102 #5) |
| 폐쇄 버튼의 위임 요청 자동 취소 | `BlogClosingService.cancelPendingDelegations` | 그대로 쓴다. 받은 멤버에게 알리지 않는다(D-102 #24와 같음) |
| 위임 요청·결과 알림 | `DelegationService` | 그대로 쓴다. 다만 탭이 `OPERATION`으로 되어 있어 3.6 표("블로그" 탭)와 다르다(R-03) |
| 참여 신청·결과 알림 | `JoinService` (`approvers` = 블로그장 + 멤버 관리 권한 부블로그장) | 그대로 쓴다(FR-034, FR-041, FR-042) |
| 블로그장 차단 시 참여 신청 자동 거절 | `JoinService.request` → `blockedByOwner` → `AUTO_REJECTED` + `JOIN_REJECTED` 알림, 7일 규칙은 `REJECTED` 목록에 `AUTO_REJECTED` 포함 | 그대로 쓴다(D-102 #12와 같음). 차단하는 순간 대기 중이던 신청을 거절하는 메서드만 더한다(R-13, D-102 #13) |
| 블로그 안 신고 목록·처리 | `BlogReportService`, `SanctionController` (`GET /api/blogs/{blogId}/reports`, `POST .../resolution`), 화면 `blog-manage.js` 신고 탭 | 그대로 쓴다. `route = 'BLOG'`만 보이고, 응답에 신고자가 없다(`reporterId`는 `@JsonIgnore`, D-102 #15와 같음). 결과 알림 문구 만들기만 `ReportResultNotifier`로 옮겨 005와 같이 쓴다(R-15) |
| 멤버 제재·해제 문의 결과 알림 | `SanctionService`, `AppealService` | 그대로 쓴다(FR-049, FR-052). 해제 문의 결과 탭은 R-03 |
| 글 댓글·대댓글·좋아요·삭제·공지 알림 | `board/application/CommentService`, `LikeService`, `PostService`, `NoticeService` | 그대로 쓴다. 자기 행동은 알리지 않고, 다시 누른 좋아요는 `event_key`로 다시 알리지 않는다(D-100 #13) |
| 차단·팔로우 읽기 | `board/application/PostVisibility` (`FOLLOWING`, `notBlocked`), `FeedService`(팔로우 탭), `SearchService`, `PostListService.tagPosts`, `CommentService.NOT_BLOCKED` | 그대로 쓴다. 차단한 쪽에서만 숨기고 같은 블로그 멤버는 예외(D-102 #11과 같음). **블로그 글 목록(`PostListService.blogPosts`)에는 차단 조건이 없어** 더한다(R-13) |
| 관리자 활동 거부 | `ErrorCode.ADMIN_NOT_ALLOWED` (`LikeService`, `CommentService`, `PostPolicy`, `JoinService`, `BlogService`가 `users.role`로 확인) | 같은 코드·같은 방식으로 팔로우·구독·차단·신고를 막는다(D-90) |
| 요청 제한 | `common/ratelimit/RateLimiter`(`InMemoryRateLimiter`), 429 `RATE_LIMITED` + `retryAfterSeconds` | 팔로우·구독에 같은 방식으로 쓴다(키 `follow:{회원}`, `subscribe:{회원}`, D-102 #4) |
| 사용자 IP | `common/ratelimit/ClientIpResolver` | 003은 회원 단위 제한만 써서 필요 없다 |
| 로그인 연장 판단 | `auth/security/ActivityTrackingFilter`(헤더 `X-User-Activity: 1`일 때만 RT `last_active_at` 갱신), `TokenService.refresh`(회전해도 `last_active_at` 유지), 화면 `api.js`(`{activity: true}`일 때만 헤더) | 그대로 쓴다. 폴링은 헤더 없이 보낸다(R-05) |
| 04:00 정리 | `batch/DailyCleanupJob`(ShedLock) + `BlogDailyTasks`, `BoardDailyTasks` | 알림 보관 기간 정리 단계(`NotificationDailyTasks`)를 더한다(R-08) |
| 회원 소개 칸 | `users.bio`(VARCHAR(500)), `User.getBio()`, `GET /api/members/me` 응답의 `bio` | 읽기는 있다. 고치는 API와 화면을 새로 만든다(R-09). 탈퇴 30일 뒤 `bio = NULL`은 `DailyCleanupJob`에 이미 있다 |
| 회원탈퇴 | `member/application/WithdrawalService` | 팔로우·구독·차단 관계를 지우는 호출을 더한다(R-16) |
| 화면 공통 | `static/js/layout.js`(상단 메뉴), `api.js`(CSRF·5초 중단·`setText`), `session.js`(무활동 안내), `css/base.css`, `blog-home.js`(구독 버튼, 위임 수락·거절), `blog-manage.js`(탭: requests 등) | 종 아이콘·사이드바를 `layout.js`에 붙여 모든 화면(메인·개별 블로그)에 같게 나오게 한다(R-17) |

### 이미 코드로 만족하는 FR (새 코드 없이 테스트로만 확인)

- FR-010, FR-011, FR-012: 일부 공개 링크·구독 버튼·내 구독 목록·비공개 전환 뒤 구독 유지 (002)
- FR-013: 메인 피드 팔로우·구독 탭, 볼 때마다 모음 (004)
- FR-018: 같은 블로그 멤버끼리는 차단해도 그 블로그 안 글이 보임 (004)
- FR-026: 신고 수로 자동 제재하지 않음 (자동 처리 코드 없음)
- FR-034, FR-041, FR-042: 블로그별 현재 역할로 참여 신청 알림 대상 결정, 참여 결과 알림 (002)
- FR-035: 같은 이벤트 알림 한 번(`event_key`), 폐쇄 알림 보낸 기록 (002)
- FR-036, FR-037, FR-038: 댓글·대댓글·좋아요 알림 (004)
- FR-045, FR-047: 폐쇄 예정(즉시·3일 전·1일 전)·철회 알림, 대상 다시 계산, 밀린 알림 (002, D-102 #22·#23)
- FR-046: 권한 박탈·관리자 강제 폐쇄의 폐쇄 예정 알림(문구 포함)은 002 `BlogClosingService`에 있고, 부르는 쪽은 005
- FR-050, FR-053: 내 글 삭제됨·공지 알림 (004)
- FR-055: 끈 동안 새 알림을 만들지 않고 받은 알림은 그대로 (`NotificationWriter`)
- FR-051(블로그 안 신고 결과), FR-052(블로그장의 멤버 조치): 002. 관리자 쪽 결과·블로그장 경고·권한 박탈 알림은 005

### 조금 고치는 FR

- FR-007·FR-008·FR-009·FR-040: 구독은 있으나 관리자·자기 블로그 거부, 요청 제한, 구독 알림이 없다 (R-11)
- FR-017: 블로그 글 목록에 차단 조건이 없다 (R-13)
- FR-020: 차단하는 순간 대기 중이던 신청 자동 거절이 없다 (R-13)
- FR-043·FR-044·FR-049: 알림은 가지만 탭이 `OPERATION`이다. 3.6 표대로 `BLOG`로 바꾸려면 사용자 확인이 먼저다 (R-03)
- FR-048: 바꾼 본인을 빼는 조건이 없다 (R-11)

### 새로 만드는 FR

FR-001~FR-006, FR-014~FR-016, FR-019, FR-021~FR-025, FR-027, FR-028~FR-033, FR-039, FR-054, FR-056~FR-058.

## R-02 패키지와 데이터 접근

- **결정**: 001·002·004와 같은 Spring Boot 앱에 두 패키지를 더한다.
  - `social`: 프로필·팔로우·차단·신고 (`api`, `application`)
  - `notification`: 알림함·폴링·설정·보관 정리 (`api`, `application`). 알림 쓰기(`NotificationWriter`)와 종류(`NotificationType`)는 002부터 쓰던 `common/notification`에 그대로 둔다.
- **데이터 접근**: 새로 다루는 테이블(`follows`, `user_blocks`, `reports`, `notifications`, `notification_settings`)은 JPA 엔티티 없이 `JdbcTemplate`으로 읽고 쓴다(004와 같음). 대부분 한두 줄 SQL이고 여러 테이블을 잇는 조회라서다.
- **설정**: `common/config/SocialProperties`(`social.*`), `NotificationProperties`(`notification.*`)를 `@ConfigurationProperties`로 만든다(D-68).
- **이유**: 소셜은 "회원 단위로 메인에서 한 번만 만들고 모든 블로그가 같이 쓴다"(3.3)라서 `blog`가 아니라 `social`에 둔다. 알림함은 모든 기능이 쓰는 통로라 따로 둔다.
- **검토한 다른 안**: 모두 `blog` 패키지에 넣기(구독이 이미 거기 있지만 팔로우·신고는 블로그와 상관없는 것도 있어 섞인다).

## R-03 알림 탭 값

- **DB 값과 화면 탭**:

  | 화면 탭 | API `tab` 값 | `notifications.tab` 값 |
  |---|---|---|
  | 전체 | `ALL` | (조건 없음) |
  | 댓글 | `COMMENT` | `COMMENT` |
  | 좋아요 | `LIKE` | `LIKE` |
  | 팔로우·구독 | `FOLLOW` | `FOLLOW`, `SUBSCRIBE` |
  | 블로그 | `BLOG` | `BLOG` |
  | 운영 | `OPERATION` | `OPERATION` |

- **결정**: 새 팔로워는 `FOLLOW`, 블로그 구독은 `SUBSCRIBE`로 저장하고, 화면의 "팔로우·구독" 탭은 둘을 함께 보여준다(`tab IN ('FOLLOW', 'SUBSCRIBE')`). 스키마 설명(`COMMENT, LIKE, FOLLOW, SUBSCRIBE, BLOG, OPERATION`)과 같아 DB 변경이 없고, 인덱스 `idx_notifications_recipient_id_tab_created_at`을 그대로 쓴다.
- **3.6 표와 지금 코드가 다른 곳 (사용자 확인 필요)**:
  - `DELEGATION_REQUESTED`, `DELEGATION_ACCEPTED`, `DELEGATION_REJECTED`, `DELEGATION_CANCELED`: 코드는 `OPERATION`, 3.6 표는 "블로그" 탭(FR-043, FR-044)
  - `APPEAL_RELEASED`, `APPEAL_REJECTED`: 코드는 `OPERATION`, 3.6 표는 "블로그" 탭(FR-049)
  - 002 data-model도 `OPERATION`으로 적혀 있어 002 때 옮기면서 생긴 차이로 보인다. CLAUDE.md "요구사항과 코드가 다르면 고치기 전에 사용자에게 먼저 확인"에 따라 plan.md "구현 전에 할 일"에 올렸다. 확인되면 `NotificationType`의 탭 값만 바꾸고, 이미 쌓인 개발 DB 행은 `UPDATE notifications SET tab = 'BLOG' WHERE notification_type IN (...)`로 맞춘다(구조 변경 아님).
- **이유**: 3.6 표의 탭 구성(D-39, D-56)을 그대로 따른다.

## R-04 알림 목록·읽음·삭제

- **목록** `GET /api/notifications?tab=ALL&before={알림 번호}`:
  - 받는 사람 본인 것만(`recipient_id = 로그인 회원`) 최신순(`id DESC`)으로 20개(`notification.page-size`)씩 준다. 화면은 아래 "더 보기"로 마지막 번호를 `before`에 넣어 이어 받는다(D-102 #17).
  - 응답 항목: `id`, `type`, `tab`(API 값), `content`, `link`(R-06, 없으면 null), `read`, `createdAt`. 행동한 회원은 알림을 만들 때 `content`에 닉네임으로만 넣는다(FR-033). 이메일·이름·전화번호는 없다.
- **읽음** (D-102 #18):
  - `POST /api/notifications/{id}/read`: 알림 하나를 누를 때 화면이 부른다. 남의 알림이면 404 `NOT_FOUND`.
  - `POST /api/notifications/read-all?tab=`: 보고 있는 탭의 안 읽은 알림을 모두 읽음으로 바꾸고 바꾼 수를 준다.
  - 사이드바·탭을 여는 것만으로는 아무것도 바꾸지 않는다.
- **삭제** (D-102 #19, #28):
  - `DELETE /api/notifications/{id}`: 하나 지우기(x 버튼).
  - `DELETE /api/notifications?tab=`: `ALL`이면 모두, 다른 탭이면 그 탭만 지운다. 확인 창은 화면이 띄운다.
  - 행을 바로 지운다(30일 보관하지 않음).
- **이유**: FR-029~FR-031. 알림은 시간순으로 계속 쌓이므로 번호 페이지보다 "더 보기"가 맞고(피드와 같음), 알림 번호가 늘어나는 순서라 `before`만으로 이어 받을 수 있다.

## R-05 30초 폴링과 로그인 연장 제외

- **결정**:
  - 화면은 로그인한 상태에서 `GET /api/notifications/unread-count`를 30초마다 부른다. 응답은 `{ unreadCount, pollIntervalSeconds }`이고, 간격은 서버 설정 `notification.poll-interval`(30s, D-72)을 내려줘 화면이 그 값을 쓴다.
  - 개수는 100에서 멈춰 센다(`SELECT COUNT(*) FROM (SELECT 1 ... LIMIT 100)`). 화면은 99를 넘으면 "99+"로 표시한다(`notification.badge-max`, D-102 #20). 받는 사람 번호로 시작하는 인덱스를 쓴다.
  - 목록은 사이드바를 열 때만 받는다. 폴링은 개수만 받는다.
- **로그인 연장에서 빼는 방법 (이미 있는 장치)**:
  - 001에서 "직접 한 행동"은 화면이 `X-User-Activity: 1` 헤더를 붙인 요청만이고, 이 헤더가 있을 때만 `ActivityTrackingFilter`가 RT의 `last_active_at`을 갱신한다(001 R-04, D-62).
  - 폴링은 `api.get(url)`로 `{activity: true}` 없이 보낸다. 그래서 헤더가 없고, `session.markActivity()`도 부르지 않아 화면의 무활동 안내 시계도 그대로 간다.
  - Access Token이 만료돼 폴링이 401을 받으면 `api.js`가 `/api/auth/refresh`를 한 번 부른다. `TokenService.refresh`는 RT를 회전하지만 `last_active_at`은 그대로 두므로 연장되지 않는다. 30분 무활동이 지나면 refresh가 401이 되고, 화면은 폴링을 멈추고 종 아이콘을 숨긴다.
  - 서버 쪽에 폴링 전용 예외를 따로 두지 않는다. 헤더 규칙 하나로 충분하고, 새 경로가 생겨도 같은 규칙이 걸린다.
- **확인**: `NotificationPollingSessionTest`가 "미체크 로그인 + 헤더 없는 unread-count 요청만 30초마다 31분 → refresh 401"을 확인한다(SC-012, 001 `SessionLifetimeIntegrationTest`와 같은 방식).
- **이유**: FR-032, SEC-04, D-62, D-72. SSE·WebSocket은 쓰지 않는다(Constitution VI).

## R-06 알림을 눌렀을 때 이동할 곳

- **결정**: 목록을 만들 때 서버가 `link`를 계산해 준다. 화면은 누르면 읽음 처리 뒤 `link`로 이동하고, `link`가 null이면 내용만 펼쳐 보여준다(D-102 #21).

  | 알림 종류 | link |
  |---|---|
  | POST_COMMENT, COMMENT_REPLY | `/blog/{주소}/posts/{글 번호}` (댓글 → 글을 이어서 찾음) |
  | POST_LIKE | `/blog/{주소}/posts/{글 번호}` |
  | NOTICE | `/notices/{글 번호}` |
  | NEW_FOLLOWER | `/profile/{팔로우한 회원 번호}` |
  | BLOG_SUBSCRIBED, BLOG_CLOSING, BLOG_CLOSING_WITHDRAWN, BLOG_PRIVATE | `/blog/{주소}` |
  | JOIN_REQUESTED | `/blog/{주소}/manage?tab=requests` (블로그 관리의 신청 목록) |
  | DELEGATION_REQUESTED | `/blog/{주소}` (블로그 홈에 수락·거절 버튼이 있음, 002 `blog-home.js`) |
  | 그 밖의 모든 종류(JOIN_APPROVED·JOIN_REJECTED·BLOG_CLOSED_REQUEST_REJECTED·위임 결과·제재·신고 결과·해제 문의 결과·POST_DELETED, 005의 운영 알림) | null (내용만) |

- **대상이 없어진 경우**: 글·댓글이 지워졌거나 블로그 주소가 비워졌으면(폐쇄 30일 정리) `link`를 null로 주고, 화면은 "볼 수 없는 내용입니다"를 보여준다.
- **권한**: `link`는 주소일 뿐이다. 이동한 화면이 부르는 API가 권한을 다시 확인하고(002 `BlogPermissionService`, 004 `PostPolicy`), 볼 수 없으면 404로 "볼 수 없는 내용입니다"를 보여준다. 알림 목록이 대상 글을 볼 수 있는지까지 미리 판단하지는 않는다.
- **운영 화면 탭**: `blog-manage.js`가 주소의 `?tab=` 값을 읽어 그 탭을 먼저 연다(권한이 없는 탭이면 지금처럼 첫 탭).

## R-07 알림 쓰기 보강 (차단·탈퇴)

- **차단한 회원의 행동**: `NotificationType`에 `blockable` 표시를 둔다. `blockable`인 종류는 `actorId`가 있고 받는 사람이 그 행동한 회원을 차단했으면(`user_blocks.blocker_id = 받는 사람 AND blocked_id = 행동한 회원`) 만들지 않는다(D-102 #11).
  - `blockable`: POST_COMMENT, COMMENT_REPLY, POST_LIKE, NEW_FOLLOWER, BLOG_SUBSCRIBED, JOIN_REQUESTED (끌 수 있는 알림 가운데 행동한 회원이 있는 것)
  - 끌 수 없는 운영 알림(위임·폐쇄·제재 등)은 차단과 관계없이 보낸다. *가정*
  - 참여 신청 알림은 블로그장이 차단한 회원이면 신청 자체가 자동 거절되어 알림이 생기지 않는다. 부블로그장이 개인적으로 차단한 회원의 신청은 그 부블로그장에게만 알림이 가지 않고 신청 목록에는 그대로 보인다(D-102 #12 "개인 차단으로만 적용").
- **탈퇴한 받는 사람**: `users.status <> 'ACTIVE'`이면 만들지 않는다. 004의 댓글·좋아요가 서비스에서 하던 확인을 `NotificationWriter` 한 곳으로 모은다.
- **자기 행동**: 부르는 쪽(댓글·좋아요·팔로우·구독)에서 이미 뺀다. 팔로우·구독은 자기 자신을 대상으로 할 수 없어 생기지 않는다(D-102 #1).
- **이유**: 모든 기능이 같은 규칙을 따르게 쓰는 곳 한 군데에서 거른다.

## R-08 알림 설정과 보관 정리

- **설정 API**:
  - `GET /api/me/notification-settings`: 9가지 켜짐 여부와 `retentionDays`. 행이 없으면 모두 켜짐, 30일로 응답한다(D-102 #26). 가입 때 행을 미리 만들지 않는다. 컬럼 기본값이 모두 TRUE라서 처음 저장할 때 만들어도 같다.
  - `PUT /api/me/notification-settings`: 보낸 항목만 바꾼다. `INSERT ... ON DUPLICATE KEY UPDATE`(유니크 `uk_notification_settings_user_id`).
  - 받을 수 있는 키는 `postComment`, `commentReply`, `postLike`, `newFollower`, `blogSubscribed`, `joinRequest`, `joinResult`, `reportResult`, `notice`, `retentionDays` 뿐이다. 다른 키(예: `blogClosing`)가 오면 400 `VALIDATION_FAILED`(field 그 키, code `NotAllowed`)로 거부한다(FR-054, 인수 시나리오 5-4).
  - `retentionDays`는 7 또는 30만 받는다. DB CHECK(`ck_notification_settings_retention`)와 같다.
- **끌 때와 켤 때**: 설정은 앞으로 만들 알림에만 쓰인다(`NotificationWriter`). 이미 받은 알림은 건드리지 않고, 꺼 둔 동안의 알림을 뒤늦게 만들지 않는다(FR-055).
- **보관 정리** (`NotificationDailyTasks`, `DailyCleanupJob`에 단계 추가):
  - `retention_days = 7`인 회원: `created_at < 지금 - 7일`인 알림 삭제
  - 그 밖(행 없음 포함): `created_at < 지금 - 30일`인 알림 삭제
  - 기준 시각보다 오래된 것을 모두 지우므로, 7일로 줄인 다음 날 이미 7일이 지난 알림도 지워지고(D-102 #27) 서버가 꺼져 있던 날의 몫도 다음 실행에서 지워진다.
  - `idx_notifications_created_at`을 쓴다. 한 번에 많으면 1,000건씩 나눠 지운다.
- **화면**: 7일로 바꿀 때 "7일이 지난 알림은 다음 정리 때 지워집니다"를 확인 창으로 보여준다(D-102 #27).
- **블로그 단위 설정**: 두지 않는다. 블로그장도 같은 개인 설정을 쓴다(D-102 #29).

## R-09 프로필

- **조회** `GET /api/users/{userId}/profile` (비회원 포함 누구나, D-102 #8):
  - 응답: `id`, `nickname`, `profileImageUrl`, `bio`, `ownedBlogs`, `joinedBlogs`, `followerCount`, `viewer`
  - `viewer`는 로그인했을 때만: `self`(본인인지), `following`(내가 팔로우하는지), `blocking`(내가 차단했는지). 상대가 나를 차단했는지는 넣지 않는다(D-102 #11).
  - 이메일·이름·전화번호는 DTO에 없다(FR-002, D-22). `SocialSecurityTest`가 응답을 검사한다.
- **운영·참여 블로그** (D-102 #6):
  - 운영 = 그 회원이 `OWNER`인 블로그, 참여 = `MANAGER`·`MEMBER`인 블로그. `blogs.status IN ('ACTIVE','CLOSING')`만.
  - 다른 사람(비회원 포함)이 볼 때: `visibility = 'PUBLIC' AND hidden = FALSE`만 넣는다. 일부 공개·비공개·숨김 블로그는 이름도 넣지 않는다.
  - 본인이 볼 때: 모두 넣는다.
- **없는 회원**: 없는 번호, 탈퇴한 회원, 메인 관리자 계정은 404 `NOT_FOUND`이다. 관리자 계정은 블로그 활동이 없어(D-90) 보여줄 프로필이 없다. *가정*
- **소개 고치기** `PUT /api/members/me/bio` (D-102 #7):
  - 본인만(경로에 회원 번호가 없고 로그인 정보로만 정함, 001 내 정보와 같음).
  - 앞뒤 공백을 빼고 0~500자(`social.bio.max-length`, 코드 포인트 기준)이다. 빈 문자열이나 null이면 지운다. 글자 종류는 제한하지 않고 줄바꿈을 허용한다.
  - 001의 `PATCH /api/members/me`는 고칠 수 있는 항목을 닉네임·전화번호로 막고 있어(001 FR-041), 그 계약을 건드리지 않도록 소개만 따로 받는다.
- **화면**: `/profile/{회원 번호}` → `static/profile.html`. 소개는 `textContent`와 CSS `white-space: pre-line`으로 줄바꿈을 보인다(D-64). 글 상세·댓글·피드의 작성자 닉네임을 프로필 링크로 바꾼다(작성자 `state = ACTIVE`일 때만).

## R-10 팔로우

- **결정**:
  - `POST /api/users/{userId}/follow`(팔로우), `DELETE /api/users/{userId}/follow`(취소). 응답은 둘 다 `{ following, followerCount }`. 화면은 같은 버튼을 상태에 따라 둘 중 하나로 부른다(FR-008).
  - 002 구독과 같은 방식(POST·DELETE)을 써서 여러 번 와도 결과가 같다. 빠르게 두 번 눌러도 `uk_follows_follower_id_followee_id`와 `INSERT IGNORE`로 한 건만 남는다(SC-007).
- **확인 순서**:
  1. 요청 제한: 회원당 1분 30번(`social.follow.rate-limit`, `rate-window`) → 429 `RATE_LIMITED`(D-102 #4)
  2. 로그인 회원이 메인 관리자면 403 `ADMIN_NOT_ALLOWED`(D-90)
  3. 대상이 없거나 탈퇴했거나 관리자면 404 `NOT_FOUND`
  4. 자기 자신이면 400 `SELF_NOT_ALLOWED`(D-102 #1)
  5. 둘 사이에 어느 방향이든 차단이 있으면 403 `FOLLOW_NOT_ALLOWED`. 문구는 "이 회원을 팔로우할 수 없습니다."로, 차단을 드러내지 않는다(D-102 #11)
- **알림**: 새 행이 생겼을 때만 대상에게 `NEW_FOLLOWER`(탭 FOLLOW, 설정 `new_follower`). `event_key = NEW_FOLLOWER:{팔로우한 회원}`이라 취소 후 다시 팔로우해도 `INSERT IGNORE`로 다시 만들어지지 않는다(D-102 #3). 받는 사람이 그 알림을 지웠거나 보관 기간이 지나 지워진 뒤에는 다시 갈 수 있다(004 좋아요와 같은 방식). *가정*
- **취소**: 행이 없어도 200이다. 차단이 있어도 취소는 된다.

## R-11 구독 보강 (002 코드에 더함)

- **결정**: 경로와 응답(204)은 002 그대로 두고 `SubscriptionService.subscribe`에 확인을 더한다.
  1. 요청 제한: 회원당 1분 30번(`social.subscribe.rate-limit`) → 429 `RATE_LIMITED`(D-102 #4)
  2. 관리자면 403 `ADMIN_NOT_ALLOWED`(D-90)
  3. 볼 수 있는 블로그인지: 기존 `permissionService.require(blogId, VIEW)`. 비공개는 멤버만, 일부 공개는 멤버·구독자·유효한 공유 쿠키만 통과한다. 그래서 비공개 블로그는 멤버만 구독할 수 있다(D-102 #2, FR-010)
  4. 블로그장이면 400 `SELF_NOT_ALLOWED`(D-102 #1)
  5. 새 행이 생겼을 때만 블로그장에게 `BLOG_SUBSCRIBED`(탭 SUBSCRIBE, 설정 `blog_subscribed`, `event_key = BLOG_SUBSCRIBED:{블로그}:{회원}`, D-102 #3)
- **취소**: 지금처럼 요청 제한만 더한다(구독·취소를 합쳐 센다).
- **폐쇄될 때**: `BlogClosingService.closeIfDue`에서 폐쇄 처리와 같은 트랜잭션으로 `DELETE FROM blog_subscriptions WHERE blog_id = ?`를 한다(D-102 #5). 폐쇄 알림은 이미 갔으므로 따로 알리지 않는다. 관리자 강제 폐쇄도 같은 `closeIfDue`를 지나서 함께 처리된다.
- **비공개 전환 알림**: `BlogService.notifyPrivate`가 바꾼 본인(`actorId`)을 빼게 한다. 한 사람에게 한 번은 구독 행이 한 쌍에 하나라 이미 지켜진다(D-102 #25). 일부 공개 전환은 지금처럼 알리지 않는다.
- **화면**: `blog-home.js`의 구독 버튼을 블로그장·관리자에게는 숨기고, 429·400 응답의 `message`를 그대로 보여준다.

## R-12 팔로워·팔로잉 목록

- **결정**: `GET /api/users/{userId}/followers`, `GET /api/users/{userId}/following` (비회원 포함 누구나, D-102 #9).
  - 최근에 팔로우한 순서(`follows.created_at DESC, id DESC`)로 한 페이지 20명(`social.list.page-size`) 번호 페이지다(D-76).
  - 항목은 `{ id, nickname, profileImageUrl }`만이다(FR-015).
  - 팔로워 목록은 `idx_follows_followee_id`, 팔로잉 목록은 `uk_follows_follower_id_followee_id`를 쓴다.
  - 탈퇴하면 관계가 지워지므로(R-16) 탈퇴 회원은 나오지 않는다. 그래도 `users.status = 'ACTIVE'` 조건을 함께 둔다.
- **화면**: 프로필 화면의 "팔로워 N" 글자를 누르면 목록 탭이 열린다.

## R-13 차단

- **결정**:
  - `POST /api/users/{userId}/block`(차단), `DELETE /api/users/{userId}/block`(해제), `GET /api/me/blocks`(내 차단 목록).
  - 차단: 관리자면 403 `ADMIN_NOT_ALLOWED`(*가정*: 관리자는 소셜 기능을 쓰지 않음, D-90의 연장), 대상이 없거나 탈퇴·관리자면 404, 자기 자신이면 400 `SELF_NOT_ALLOWED`이다. `INSERT IGNORE`로 한 건만 둔다(`uk_user_blocks_blocker_id_blocked_id`).
  - 차단과 같은 트랜잭션에서
    1. 두 방향 팔로우를 지운다(FR-019).
    2. 차단한 회원이 블로그장인 블로그에 차단당한 회원의 대기 중 참여 신청이 있으면 `JoinService.rejectPendingBlockedByOwner(ownerId, blockedId)`로 일반 거절과 똑같이 처리한다. 블로그 행을 잠그고 `AUTO_REJECTED` + 처리 시각(7일 규칙) + `JOIN_REJECTED` 알림이다(D-102 #13, #12). 부블로그장의 차단은 신청에 영향이 없다.
  - 해제: 행을 지운다. 끊긴 팔로우는 되살리지 않는다(D-102 #10). 없어도 204.
  - 목록: 닉네임·프로필 사진·차단한 날짜, 최근 차단 순 20개 번호 페이지(`social.list.page-size`, *가정*: 개수는 문서에 없어 팔로워 목록과 같은 값을 쓴다).
- **숨기기**: 004 `PostVisibility.notBlocked`와 `CommentService.NOT_BLOCKED`를 그대로 쓴다. 차단한 쪽에서만 숨기고 같은 블로그 멤버는 예외다(D-102 #11, D-36).
  - **빠진 곳**: `PostListService.blogPosts`(블로그 글 목록)에 `PostVisibility.notBlocked`를 붙인다. 같은 블로그 멤버 예외 조건이 이미 들어 있어, 둘 다 멤버인 블로그 J에서는 보이고 멤버가 아닌 블로그 K에서는 빠진다(US8-2·3).
  - 글 상세를 주소로 직접 열면 보인다. 목록·피드·검색·태그·댓글에서만 뺀다. *가정*
- **차단 사실 숨김**: 차단당한 회원에게 가는 알림이 없고, 차단당한 회원이 보는 응답(프로필 `viewer`, 팔로우 거부 문구)에도 "차단"이라는 말이 없다(D-102 #11).

## R-14 신고 접수

- **API** `POST /api/reports`:
  - 요청: `{ targetType: USER|BLOG|POST|COMMENT, targetId, blogId(USER를 블로그 안에서 신고할 때만), reason, detail }`
  - 응답: 201 `{ id, route }`. `route`는 `BLOG`(블로그장에게 접수) 또는 `ADMIN`(메인 관리자에게 접수)이고 화면이 "블로그장에게 접수되었습니다" 같은 안내에 쓴다.
  - `GET /api/reports/reasons`: 사유 목록(코드·이름·설명 필수 여부)과 설명 최대 길이. 화면이 설정값을 그대로 쓰게 한다.
- **누가**: 로그인 회원. 관리자는 403 `ADMIN_NOT_ALLOWED`. 대상을 볼 수 없으면(비공개 블로그의 글 등) 그 대상의 404(`POST_NOT_FOUND`, `COMMENT_NOT_FOUND`, `BLOG_NOT_FOUND`, `NOT_FOUND`)이다. 그 블로그에서 정지 중이면 002와 같이 403 `BLOG_SUSPENDED`.
- **접수처** (D-93, D-45, FR-023, FR-024). 블로그장 여부는 신고하는 그 순간의 `blog_members`로 본다(SEC-07):

  | 대상 | blog_id | route |
  |---|---|---|
  | BLOG | 그 블로그 | ADMIN |
  | POST (블로그 글) | 글의 블로그 | 작성자가 지금 그 블로그의 블로그장이면 ADMIN, 아니면 BLOG |
  | COMMENT | 댓글이 달린 글의 블로그 | 작성자가 지금 그 블로그의 블로그장이면 ADMIN, 아니면 BLOG |
  | USER + blogId (블로그 안) | blogId | 대상이 그 블로그의 블로그장이면 ADMIN, 아니면 BLOG |
  | USER, blogId 없음 (메인 프로필) | NULL | ADMIN |

  - 블로그 안 회원 신고는 그 블로그의 멤버만 대상으로 받는다. 멤버가 아니면 404 `NOT_FOUND`이다. *가정*
  - 공지 글(`board_type = 'NOTICE'`)은 신고 대상이 아니다(400 `VALIDATION_FAILED`, field targetId). 관리자가 쓴 글이고 받을 접수처가 없다. *가정*
  - `route = 'BLOG'` 신고는 002 신고 탭(블로그장, 멤버 관리 권한 부블로그장)에 바로 나온다. `route = 'ADMIN'`은 005가 처리한다.
- **자기 자신** (D-102 #1): 대상이 나, 내 글, 내 댓글, 내가 블로그장인 블로그이면 400 `SELF_NOT_ALLOWED`.
- **사유** (D-102 #14): `social.report.reasons`의 코드만 받는다(`SPAM`, `ABUSE`, `SEXUAL`, `PRIVACY`, `COPYRIGHT`, `OTHER`). `detail`은 앞뒤 공백을 빼고 0~500자(`social.report.detail-max-length`)이고, `OTHER`(`social.report.detail-required`)는 1자 이상이어야 한다. 아니면 400 `VALIDATION_FAILED`(field reason·detail). `reports.reason`(VARCHAR(30))에 코드, `reason_detail`(VARCHAR(500))에 설명을 넣는다.
- **2주 제한과 동시 요청** (FR-025, SC-008):
  - 같은 신고자가 같은 대상(`target_type` + `target_id`)을 14일(`social.report.repeat-after`) 안에 신고했으면 409 `REPORT_TOO_SOON`과 `reportableAt`(마지막 신고 + 14일)을 준다. 어디서 신고했는지(블로그 안·메인 프로필)는 따지지 않는다. *가정*
  - DB 유니크가 없으므로 신고자의 `users` 행을 `SELECT ... FOR UPDATE`로 잠근 뒤 확인하고 넣는다. 같은 사람의 동시 요청은 차례로 처리되어 한 건만 들어간다. 확인 조회는 `idx_reports_reporter_id_target_type_target_id_created_at`을 쓴다. 다른 회원의 신고는 서로 막지 않는다.
- **신고 당시 내용** (D-85, FR-027): `target_snapshot`에 JSON 문자열로 넣는다.
  - USER: 닉네임, 소개
  - BLOG: 이름, 주소, 소개
  - POST: 제목, 본문 마크다운, 작성자 닉네임
  - COMMENT: 내용, 작성자 닉네임, 글 번호
  - 이메일·이름·전화번호는 넣지 않는다.
- **알림**: 신고당한 사람에게 아무 알림도 보내지 않고, 블로그장 화면에도 신고자를 보여주지 않는다(D-102 #15, 지금 002와 같음). 접수 알림은 3.6 표에 없어 만들지 않는다.
- **보관**: 1년(D-60). 1년 지난 신고 삭제는 005가 운영 기록과 함께 04:00 정리에 넣는다(D-103 #19). 003은 지우지 않는다.

## R-15 신고 처리 결과 알림 (005와 같이 쓰는 부분)

- **결정**: `social/application/ReportResultNotifier.resolved(reportId)`를 만든다. 신고 행을 읽어 신고자에게 `REPORT_RESOLVED`(탭 OPERATION, 설정 `report_result`, `event_key = REPORT_RESOLVED:{신고 번호}`)를 보낸다.
  - 결과 이름: NONE 문제 없음, WARNING 경고, SUSPEND 정지, KICK 강제 퇴장 / OWNER_WARNING 블로그장 경고, OWNER_KICK 블로그장 강퇴, BLOG_CLOSE 블로그 폐쇄(D-38, ADM-04).
  - 문구에는 대상 종류와 결과만 넣고, 신고 대상 회원의 닉네임은 넣지 않는다.
  - 신고자가 탈퇴했으면 보내지 않는다(R-07).
- **쓰는 곳**: 002 `BlogReportService.resolve`가 지금 직접 쓰는 알림을 이것으로 바꾼다(동작 같음). 005의 관리자 신고 처리도 이것을 부른다.
- **이유**: FR-051. 결과 문구를 한 곳에 둬 블로그장·관리자 처리가 같은 알림을 만든다.

## R-16 회원탈퇴 때 관계 정리

- **결정**: `WithdrawalService.withdraw`의 같은 트랜잭션에서 `SocialCleanup.onWithdraw(userId)`를 부른다(D-102 #16).
  - `DELETE FROM follows WHERE follower_id = ? OR followee_id = ?`
  - `DELETE FROM blog_subscriptions WHERE user_id = ?`
  - `DELETE FROM user_blocks WHERE blocker_id = ? OR blocked_id = ?`
- **남기는 것**: 그 회원이 한 신고(`reports`)는 1년 보관한다. 신고자 표시 "탈퇴한 회원"은 관리자 화면(005)에서 한다. 블로그장 화면에는 신고자가 원래 없다.
- **이유**: 관계는 화면에 보이지 않고 재가입해도 이어지지 않으므로 30일 보관할 이유가 없다.

## R-17 화면

- **종 아이콘과 사이드바** (FR-028~FR-033):
  - `layout.js`가 로그인 상태의 상단 메뉴에 종 버튼(`aria-label="알림"`, 안 읽은 개수 배지)을 넣고 `notifications.js`를 시작한다. `layout.js`는 메인과 모든 개별 블로그 화면이 같이 쓰므로 어디서나 같게 보인다(4.2 일관성).
  - 사이드바는 오른쪽에서 열리는 패널(`<aside role="dialog">`)이다. 탭 6개("전체", 댓글, 좋아요, 팔로우·구독, 블로그, 운영), "모두 읽음", "전체 삭제", 알림마다 x 버튼, 아래 "더 보기"가 있다.
  - 안 읽은 알림은 `.is-unread` 강조 색, 읽은 알림은 기본 색이다.
  - 알림 내용과 모든 글자는 `api.setText`(textContent)로만 넣는다(D-64).
  - 탭 전환·더 보기·읽음·삭제는 사용자가 누른 것이라 `{activity: true}`로 보낸다. 폴링만 빼고 보낸다(R-05).
- **새 화면**:
  - `profile.html` + `js/profile.js`: 프로필, 팔로우·차단·신고 버튼, 팔로워·팔로잉 목록
  - `me/notifications.html` + `js/me-notifications.js`: 알림 설정 체크박스 9개, 보관 기간(30일·7일), 일괄 삭제
  - `me/blocks.html` + `js/me-blocks.js`: 차단 목록과 해제
  - `me/index.html`·`js/me.js`: 소개 고치기 칸, 알림 설정·차단 목록 링크
  - `js/report.js`: 신고 창(사유 라디오, 설명 칸, 글자 수). 글 상세·댓글·블로그 홈·프로필에서 같이 쓴다.
- **반응형**: 사이드바는 PC에서 오른쪽 360px, 모바일(폭 600px 이하)에서 화면 전체다. 360px 폭에서 가로 스크롤이 없어야 한다(4.2). 스타일은 `css/base.css`에 더한다.

## R-18 스키마 확인 결과

- 003이 쓰는 테이블과 인덱스는 Crowfoot 문서 654에서 배포한 스키마(`docs/04-design/schema.sql`)에 모두 있다.
  - 테이블: `follows`, `user_blocks`, `blog_subscriptions`, `reports`, `notifications`, `notification_settings`, `blog_closing_notices`(읽지 않음, 002가 씀), `users`(`bio`, `role`, `status`), `blogs`, `blog_members`, `blog_join_requests`, `posts`, `comments`
  - 인덱스: `idx_follows_followee_id`, `idx_user_blocks_blocked_id`, `idx_reports_reporter_id_target_type_target_id_created_at`, `idx_reports_route_status_created_at`, `idx_notifications_recipient_id_tab_created_at`, `idx_notifications_created_at`, 유니크 `uk_follows_*`, `uk_user_blocks_*`, `uk_blog_subscriptions_*`, `uk_notifications_recipient_id_event_key`, `uk_notification_settings_user_id`
- **DB 구조 변경 없음**.
  - 팔로우·구독 탭은 스키마 설명에 이미 있는 `FOLLOW`·`SUBSCRIBE` 값을 쓴다(R-03).
  - 신고 2주 제한은 유니크 대신 신고자 행 잠금으로 한다(R-14).
  - 보관 기간 7·30은 DB CHECK와 같다. 그래서 설정값(`notification.retention.*`)을 바꾸려면 CHECK도 함께 바꿔야 한다(설정값 표에 적음).
- **설명 문구만 "미정"으로 남은 곳** (구조 변경 아님, 사용자 승인 뒤 Crowfoot에서 고침):
  - `users.bio`: "길이·허용 문자 미정" → "0~500자, 글자 종류 제한 없음, 줄바꿈 허용(D-102 #7)"
  - `reports.reason`: "사유 목록 미정" → "SPAM, ABUSE, SEXUAL, PRIVACY, COPYRIGHT, OTHER(설정값, D-102 #14)"
  - `reports.reason_detail`: "직접 입력 칸 여부 미정" → "추가 설명 0~500자, OTHER는 필수(D-102 #14)"
  - `notification_settings` 테이블 설명: "기본값(모두 켜짐) 미정" → "기본값 모두 켜짐(D-102 #26)"
  - `notifications.tab` 설명에 "화면의 팔로우·구독 탭은 FOLLOW·SUBSCRIBE를 함께 보여줌"을 더함

## R-19 응답 시간

- **목표**: 알림 목록·안 읽은 개수, 프로필, 팔로워·팔로잉 목록, 내 구독 목록은 1초 목표, 2초 이내다(SC-002).
- **확인**: `perf/SocialResponseTimeTest`가 팔로워 5,000명인 회원의 팔로워 목록과 프로필, 알림 3,000건인 회원의 알림 목록·안 읽은 개수를 2초 안으로 확인한다. 팔로워 목록은 `followee_id` 인덱스로 찾은 뒤 정렬하므로 팔로워가 아주 많은 회원에서 느려질 수 있어 함께 잰다.
- **화면**: 공통 `api.js`의 5초 중단을 그대로 쓴다(D-48).

---

## 가정 목록 (문서와 D-102에 없어 구현 기본값으로 둔 것)

1. 메인 관리자 계정과 탈퇴한 회원은 프로필이 404이고 팔로우·차단·신고 대상이 아니다(R-09). 관리자 계정은 차단도 하지 않는다(R-13, D-90의 연장).
2. 차단 때문에 알림을 만들지 않는 것은 끌 수 있는 알림 가운데 행동한 회원이 있는 종류(댓글·대댓글·좋아요·새 팔로워·블로그 구독·참여 신청)뿐이다. 끌 수 없는 운영 알림은 차단과 관계없이 보낸다(R-07).
3. 차단한 회원의 글은 목록·피드·검색·태그·댓글에서 빠지고, 글 주소로 직접 열면 보인다(R-13).
4. 차단 목록은 최근 차단 순 20개씩 번호 페이지다(팔로워 목록과 같은 설정값, R-13).
5. 블로그 안에서 회원을 신고할 때 대상은 그 블로그의 멤버만이다. 공지 글은 신고 대상이 아니다(R-14).
6. 신고 2주 제한의 "같은 대상"은 대상 종류 + 번호로 보고, 블로그 안에서 했는지 메인 프로필에서 했는지는 따지지 않는다(R-14).
7. 다시 팔로우·구독할 때 알림을 다시 보내지 않는 것은 004 좋아요와 같이 알림의 이벤트 키로 막는다. 받는 사람이 처음 알림을 지웠거나 보관 기간이 지나 지워진 뒤에는 다시 갈 수 있다(R-10).
