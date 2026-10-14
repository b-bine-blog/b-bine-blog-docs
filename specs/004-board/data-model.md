# 004 게시판 데이터 모델 (Phase 1)

**날짜**: 2026-10-08 | **명세**: [spec.md](spec.md) | **조사**: [research.md](research.md)

ERD는 Crowfoot 문서 654에서 배포한 스키마(`docs/04-design/schema.sql`)를 그대로 쓴다. **DB 변경은 없다**(research R-17).
JPA 엔티티는 `ddl-auto=validate`로 스키마와 맞춘다. 목록·검색·피드처럼 여러 테이블을 묶는 조회는 `JdbcTemplate` SQL로 만든다(002와 같음).

## 관계

```text
blogs 1 ─ N categories
blogs 1 ─ N posts (board_type = BLOG)      posts(board_type = NOTICE, blog_id NULL) = 메인 공지
users 1 ─ N posts (author_id)
categories 1 ─ N posts (category_id, NULL = 미분류)
posts 1 ─ N post_tags N ─ 1 tags
posts 1 ─ N comments (post_id, CASCADE)    comments 1 ─ N comments (parent_id, 1단계)
posts 1 ─ N post_likes (CASCADE)           posts 1 ─ N post_views (CASCADE)
posts 1 ─ N images (owner_type = POST, owner_id, FK 선 없음)
users 1 ─ N recent_searches (CASCADE)
읽기만: user_blocks, follows, blog_subscriptions, blog_members, notification_settings
```

## posts (글)

| 필드 | 규칙 | 근거 |
|---|---|---|
| board_type | BLOG(블로그 글) / NOTICE(메인 공지). NOTICE는 blog_id NULL(DB CHECK) | FR-001, FR-065 |
| title | 앞뒤 공백 제거 후 1~30자(`board.post.title-max-length`) | FR-003 |
| content | 마크다운 원문, 코드 포인트 기준 1~5,000자(`board.post.content-max-length`), 서버 검사 | FR-003, D-92 |
| category_id | NULL = 미분류. 같은 블로그의 카테고리만. 공지는 항상 NULL | FR-021, D-100 #8 |
| status | VISIBLE → DELETED(작성자·권한자 삭제). HIDDEN은 005 관리자 숨김 | FR-013 |
| author_left | 블로그 탈퇴·강퇴 때 true(002가 바꿈). true면 작성자 수정·삭제 불가 | FR-016, D-100 #1 |
| view_count | post_views에 새 행이 생길 때만 +1 | FR-066, D-77 |
| like_count | post_likes 행이 실제로 생기거나 지워질 때만 ±1 | FR-042 |
| deleted_at / deleted_by | 삭제 시각·삭제한 회원. 30일 뒤 04:00에 행 삭제 | FR-013, D-40 |
| created_at | 목록 정렬 기준. 글에는 수정 표시를 하지 않는다 | FR-040 |

### 상태 전이

```text
VISIBLE ──삭제(작성자·POST_MANAGE·관리자)──▶ DELETED ──30일 뒤 04:00──▶ (행 삭제, 댓글·좋아요·조회·태그 CASCADE, 이미지 deleted_at)
VISIBLE ◀──────복구(005 관리자)────────── DELETED
VISIBLE ──숨김(005)──▶ HIDDEN
```

### 권한표 (서버 확인 기준)

| 동작 | 비회원 | 회원(멤버 아님) | 멤버 | POST_MANAGE(블로그장·권한 부블로그장) | 메인 관리자 |
|---|---|---|---|---|---|
| 블로그 글 읽기 | 블로그 열람 규칙(002 R-06) | 같음 | O | O | 블로그 열람 규칙 |
| 블로그 글 쓰기 | X | X | O(정지 X) | O | X(D-90) |
| 블로그 글 수정 | X | X | 본인 글만(지금 멤버) | 본인 글만 | X |
| 블로그 글 삭제 | X | X | 본인 글만(지금 멤버) | 그 블로그 글 모두 | 모두 |
| 카테고리 관리 | X | X | X | O | X |
| 댓글 쓰기 | X | 글을 볼 수 있으면 O | O | O | X |
| 댓글 수정 | X | 본인 | 본인 | 본인 | X |
| 댓글 삭제 | X | 본인 | 본인 | 그 블로그 댓글 모두 | 005(ADM-03) |
| 좋아요 | X | 글을 볼 수 있으면 O | O | O | X |
| 공지 쓰기·수정·삭제 | X | X | X | X | O(누구나) |

정지 중인 회원은 그 블로그에서 읽기를 포함해 모두 403(002 R-01).

## comments (댓글)

| 필드 | 규칙 | 근거 |
|---|---|---|
| parent_id | NULL = 최상위. 답글은 최상위 댓글 번호만(답글의 답글도 같은 부모) | FR-038, D-100 #10 |
| reply_to_user_id | 답한 대상 회원. 최상위에 답하면 그 작성자, 답글에 답하면 그 답글 작성자. 화면은 대상의 지금 닉네임으로 "@닉네임" | D-87 |
| content | 앞뒤 공백 제거 후 1~500자(`board.comment.max-length`) | FR-037 |
| edited | 작성자가 고치면 true → "수정됨" | FR-040 |
| status | VISIBLE → DELETED. HIDDEN은 005 | FR-041 |

- 응답 규칙: DELETED인 최상위 댓글은 보이는 답글이 있을 때만 `{ deleted: true }`(내용·작성자 없음)로 넣는다. 답글이 모두 지워지면 빠진다(D-100 #3). DELETED 답글은 넣지 않는다.
- 작성자 표시: 회원탈퇴 → "탈퇴한 회원"(D-100 #2), 블로그 탈퇴는 닉네임 그대로(D-100 #1).
- 차단: 보는 사람이 차단한 회원의 댓글은 빼고, 둘 다 그 블로그 멤버면 넣는다(FR-045).
- 정리: DELETED 30일 뒤 04:00에 행 삭제. 남은 답글이 있는 최상위 댓글은 답글이 정리된 뒤 지운다.

## categories (카테고리)

- 블로그당 최대 30개(`board.category.max-count`), 이름 앞뒤 공백 제거 후 1~30자(`board.category.name-max-length`), 블로그 안에서 이름 중복 불가(서비스 확인, 블로그 행 잠금). `sort_order`는 만든 순서대로 끝에 붙이고, 순서 바꾸기 API로 고친다.
- 삭제: `UPDATE posts SET category_id = NULL WHERE category_id = ?` 뒤 행 삭제(D-100 #8).

## tags / post_tags

- 002 `TagNormalizer` 규칙(6.4): `#`·앞뒤 공백 제거, 가운데 공백 → `_`, 영문 소문자, 1~20자 한글·영문·숫자·`_`, 한 글 안 중복 합침, 최대 10개(`board.tag.max-count`). 금칙어 없음(D-96).
- `uk_post_tags (post_id, tag_id)`가 중복을 막는다. 수정은 전체 교체.

## images (owner_type = POST)

| 상태 | 조건 | 다음 |
|---|---|---|
| 올림(연결 전) | owner_id NULL, deleted_at NULL | 글 저장 때 본문에 있으면 owner_id = 글 번호 |
| 연결됨 | owner_id = 글 번호 | 수정 때 본문에서 빠지면 owner_id NULL로 되돌림 |
| 정리 표시 | owner_id NULL로 1일(`board.image.orphan-after`) 지남, 또는 글이 30일 정리됨 | deleted_at 채움(D-100 #4) |
| 삭제 | deleted_at 30일(`board.image.purge-after`) 지남 | 파일·행 삭제 |

- 연결은 "올린 사람 = 글 작성자"인 이미지만(공지는 같은 관리자). 서로 다른 이미지 10장 초과면 저장 거부(FR-031).
- 장당 3MB, 한 요청 10MB, jpg·jpeg·png·gif·webp, 확장자·MIME·시그니처 모두 확인, 재인코딩으로 EXIF 제거, UUID 이름(FR-029~FR-034).

## post_likes (좋아요)

- `uk_post_likes_user_id_post_id`가 한 회원 한 글 하나를 보장(SC-006). 토글: 있으면 DELETE, 없으면 INSERT IGNORE. 바뀐 행 수만큼 `like_count` 조정.

## post_views (조회 기록)

- `viewer_key`: 회원 `U:{id}`, 비회원 `G:{VID 쿠키 32자 hex}`(D-100 #20).
- `uk_post_views_post_id_viewer_key_view_date`가 하루 한 번을 보장(D-77). 7일(`board.view.retention`) 지난 행은 04:00에 삭제. *가정*

## recent_searches (최근 검색어)

- 로그인 회원만. 같은 회원·같은 검색어가 있으면 `searched_at`만 바꿈(맨 앞으로), 없으면 넣고 10개(`board.search.recent-max`) 넘는 오래된 행 삭제(D-100 #17). 본인 것만 조회·삭제.

## 알림 종류 (notifications에 쓰는 것)

| notification_type | tab | 받는 사람 | 끌 수 있음(설정 컬럼) | event_key | 근거 |
|---|---|---|---|---|---|
| POST_COMMENT | COMMENT | 글 작성자(본인 댓글 제외) | post_comment | `POST_COMMENT:{commentId}` | FR-044 |
| COMMENT_REPLY | COMMENT | 답한 대상 회원(본인 제외) | comment_reply | `COMMENT_REPLY:{commentId}` | FR-044 |
| POST_LIKE | LIKE | 글 작성자(본인 제외) | post_like | `POST_LIKE:{postId}:{userId}` (다시 눌러도 한 번) | FR-044, D-100 #13 |
| POST_DELETED | OPERATION | 남이 지운 글의 작성자 | 없음 | `POST_DELETED:{postId}` | FR-011 |
| NOTICE | OPERATION | 관리자 아닌 활동 회원 | notice | `NOTICE:{postId}` | FR-065 |

- 답글이 글 작성자에게도 가는지: 답글은 `COMMENT_REPLY`만 보내고 `POST_COMMENT`는 최상위 댓글에만 보낸다. *가정*
- 탈퇴한 회원에게는 보내지 않는다.

## 설정값 (application.yml, D-68)

| 키 | 기본값 | 환경변수 | 근거 |
|---|---|---|---|
| board.post.title-max-length | 30 | BOARD_POST_TITLE_MAX_LENGTH | FR-003 |
| board.post.content-max-length | 5000 | BOARD_POST_CONTENT_MAX_LENGTH | FR-003, D-92 |
| board.list.page-sizes | 10,20,30 (첫 값이 기본) | BOARD_LIST_PAGE_SIZES | FR-017, FR-057 |
| board.category.max-count | 30 | BOARD_CATEGORY_MAX_COUNT | D-100 #8 |
| board.category.name-max-length | 30 | BOARD_CATEGORY_NAME_MAX_LENGTH | D-100 #8 |
| board.tag.max-count | 10 | BOARD_TAG_MAX_COUNT | FR-024 |
| board.image.max-size | 3MB | BOARD_IMAGE_MAX_SIZE | FR-031 |
| board.image.max-request-size | 10MB | BOARD_IMAGE_MAX_REQUEST_SIZE | FR-031 |
| board.image.max-per-post | 10 | BOARD_IMAGE_MAX_PER_POST | FR-031 |
| board.image.max-pixels | 25000000 | BOARD_IMAGE_MAX_PIXELS | 001 R-11 |
| board.image.orphan-after | 1d | BOARD_IMAGE_ORPHAN_AFTER | D-100 #4 |
| board.image.purge-after | 30d | BOARD_IMAGE_PURGE_AFTER | D-100 #4, 4.5 |
| board.purge-after | 30d | BOARD_PURGE_AFTER | FR-013 |
| board.comment.max-length | 500 | BOARD_COMMENT_MAX_LENGTH | FR-037 |
| board.comment.page-size | 20 | BOARD_COMMENT_PAGE_SIZE | research R-08 |
| board.like.rate-limit / rate-window | 30 / 1m | BOARD_LIKE_RATE_LIMIT / _WINDOW | D-100 #12 |
| board.view.guest-cookie-max-age | 365d | BOARD_VIEW_GUEST_COOKIE_MAX_AGE | D-100 #20 |
| board.view.ip-limit / ip-window | 60 / 1m | BOARD_VIEW_IP_LIMIT / _WINDOW | D-100 #21 |
| board.view.bot-user-agents | bot,crawler,spider,slurp,preview | BOARD_VIEW_BOT_USER_AGENTS | D-100 #21 |
| board.view.retention | 7d | BOARD_VIEW_RETENTION | research R-10 *가정* |
| board.search.min-length / max-length | 2 / 20 | BOARD_SEARCH_MIN_LENGTH / _MAX_LENGTH | FR-054 |
| board.search.recent-max | 10 | BOARD_SEARCH_RECENT_MAX | FR-059 |
| board.search.blog-preview-size | 5 | BOARD_SEARCH_BLOG_PREVIEW_SIZE | research R-13 *가정* |
| board.feed.recent-days | 30 | BOARD_FEED_RECENT_DAYS | D-100 #18 |
| board.feed.page-size | 20 | BOARD_FEED_PAGE_SIZE | D-100 #18 |
| board.og.summary-length | 100 | BOARD_OG_SUMMARY_LENGTH | D-100 #14 |
| board.og.default-image | /img/og-default.png | BOARD_OG_DEFAULT_IMAGE | D-100 #15 |
| app.base-url | http://localhost:8080 | APP_BASE_URL | og 절대 주소(research R-12) |
| spring.servlet.multipart.max-request-size | 11MB | BOARD_MULTIPART_MAX_REQUEST_SIZE | 10MB + multipart 여유 |
