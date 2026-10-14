# 002 블로그 관리 데이터 모델

**날짜**: 2026-10-08 | **원천**: Crowfoot 문서 654 "메인블로그", 테스트 스키마 `docs/04-design/schema.sql`

이 기능은 이미 배포된 ERD의 블로그 영역 테이블을 쓴다. **새 테이블이나 컬럼은 없다.** 컬럼 타입·제약의 원천은 Crowfoot이며, 아래는 이 기능이 쓰는 규칙만 정리한다.
모든 테이블에 `id BIGINT` PK와 `created_at`, `updated_at`(DATETIME(6), DB가 채움)이 있다.

## 관계

```text
users 1 ──< blog_members >── 1 blogs          (역할 OWNER·MANAGER·MEMBER, 블로그장은 owner_blog_id 유니크로 1명)
blogs 1 ──< blog_share_links                   (active=true는 블로그당 1개)
blogs 1 ──< blog_tags >── 1 tags
blogs 1 ──< blog_join_requests >── 1 users
blogs 1 ──< blog_delegations >── 1 users(to_user_id)   from_user_id는 FK 없음
blogs 1 ──< blog_sanctions >── 1 users          report_id → reports (선택)
blog_sanctions 1 ──< blog_blacklists >── 1 blogs
blog_blacklists 1 ──< blacklist_appeals >── 1 users
blogs 1 ──< blog_subscriptions >── 1 users
blogs 1 ──< blog_closing_notices >── 1 users
blogs 1 ──< reports (route=BLOG)
images (owner_type=BLOG_COVER, owner_id=blogs.id)
읽기만: user_blocks, notification_settings, posts(author_left 갱신), comments(신고 대상 작성자)
쓰기만: notifications
```

## blogs (블로그)

| 컬럼 | 규칙 | 근거 |
|---|---|---|
| name | 앞뒤 공백 제거 후 1~30자(`blog.name.max-length`), 중복 허용 | FR-006, D-98 #2 |
| address | `^[a-z0-9-]{3,30}$`, 예약어 불가, UNIQUE. 바꿀 수 없음. 폐쇄 30일 뒤 NULL | FR-003, FR-004, FR-008, FR-009 |
| description | 선택, 0~500자(`blog.description.max-length`) | FR-006 |
| visibility | PUBLIC·LINK·PRIVATE. 블로그장만 변경, 변경 때도 개수 제한 | FR-013, FR-025~032 |
| join_policy | FREE·APPROVAL. 블로그장만 변경 | FR-009, FR-017 |
| status | ACTIVE → CLOSING → CLOSED, CLOSING → ACTIVE(철회) | FR-073~078 |
| close_scheduled_at | 누른 날짜(한국 시간) + 7일 04:00. 철회하면 NULL | FR-073, FR-078 |
| close_reason | OWNER·OWNER_REVOKED·ADMIN. 철회하면 NULL | FR-082, FR-084 |
| closed_at | 04:00 처리가 폐쇄한 시각. 30일 정리 기준 | FR-081 |
| member_count | 블로그장 포함 인원. 참여·탈퇴·강퇴 때 같은 트랜잭션에서 ±1 | D-89 |
| hidden | 관리자 숨김(005). true면 목록·검색에서 뺌 | ADM-02 |

### 상태 전이

```text
ACTIVE ──폐쇄(블로그장·관리자·권한 박탈)──> CLOSING ──04:00, 예정 시각 지남──> CLOSED ──30일 뒤 04:00──> (내용 삭제, address=NULL, 행은 남음)
   ^                                         │
   └──────────── 철회(블로그장만) ───────────┘
```

- CLOSING 중에는 평소처럼 운영된다(글·댓글·참여 신청). 위임 요청만 막는다(FR-071).
- CLOSED 블로그는 모든 열람·운영 API에서 404다.

## blog_members (블로그 역할)

| 컬럼 | 규칙 | 근거 |
|---|---|---|
| role | OWNER·MANAGER·MEMBER. 블로그장은 `owner_blog_id` 유니크로 블로그당 1명 | FR-033 |
| joined_at | 멤버가 된 시각 | |
| manager_since | MANAGER가 된 시각. 해제·위임받음이면 NULL. 권한 박탈 승계 기준(같으면 id 작은 순) | FR-043, FR-082 |
| perm_blog_info / perm_member_manage / perm_post_manage | MANAGER일 때만 의미. 다른 역할로 바뀌면 모두 false | FR-040, D-98 #18 |

- 블로그 탈퇴·강퇴하면 행을 지운다. 이력은 `blog_sanctions`(강퇴)에 남는다.
- 위임 수락: 이전 OWNER → MEMBER(권한 false), 받는 사람 → OWNER(manager_since NULL, 권한 false). 이전 행을 먼저 바꾸고 flush한다(research R-12).

### 권한표 (서버 확인 기준)

| 권한 이름 | OWNER | MANAGER | MEMBER | 그 외 |
|---|---|---|---|---|
| VIEW (블로그 열람) | O | O | O | 공개 범위에 따름(research R-06) |
| MEMBER (멤버 기능: 블로그 탈퇴, 위임 응답) | O | O | O | X |
| BLOG_INFO (이름·소개·대표 이미지·태그) | O | perm_blog_info | X | X |
| MEMBER_MANAGE (참여 승인·거절, 경고·정지·해제·강퇴, 신고 처리, 해제 문의, 멤버 정보, 블랙리스트 열람) | O | perm_member_manage | X | X |
| POST_MANAGE (다른 멤버 글 삭제, 카테고리, 공지: 004) | O | perm_post_manage | X | X |
| OWNER (공개 범위·참여 방식, 부블로그장 지정·해제·권한, 위임, 폐쇄·철회, 공유 링크 다시 만들기, 부블로그장 제재) | O | X | X | X |

- 메인 관리자 계정(`users.role = 'ADMIN'`)은 블로그 생성·참여 신청을 할 수 없다(FR-002, FR-018, D-90). 멤버가 될 수 없으므로 위 권한도 없다.
- 그 블로그에서 정지 중인 회원은 VIEW부터 모두 거부된다(403 `BLOG_SUSPENDED`).

## blog_share_links (공유 링크)

| 컬럼 | 규칙 | 근거 |
|---|---|---|
| token | 32바이트 무작위 값 base64url(43자), UNIQUE | FR-027 |
| active | 블로그당 true는 1개. 다시 만들거나 LINK를 벗어나면 false | FR-028, FR-032 |

## blog_tags / tags

- 블로그 태그는 최대 10개(`blog.tag.max-count`). 6.4 규칙으로 정규화한 이름으로 `tags`를 찾고 없으면 만든다. 정보 수정 때는 그 블로그의 태그를 통째로 바꾼다(FR-001, FR-009).

## blog_join_requests (참여 신청)

| 상태 | 언제 | 비고 |
|---|---|---|
| PENDING | 승인제 블로그에 신청 | 회원·블로그당 1개(회원 행 잠금으로 보장) |
| APPROVED | 승인, 또는 자유 참여 블로그에 신청 | 자유 참여는 바로 APPROVED로 저장하고 멤버 추가 |
| REJECTED | 거절 | processed_at + 7일(`blog.join.reapply-after`) 뒤 재신청 |
| CANCELED | 신청자가 취소 | 바로 재신청 가능 |
| AUTO_REJECTED | 블로그장이 차단한 회원, 또는 블로그 폐쇄 | 신청자에게는 REJECTED와 같게 보임. 7일 규칙도 같음 |

## blog_delegations (위임 요청)

| 상태 | 언제 |
|---|---|
| PENDING | 블로그장이 멤버 한 명에게 요청. 블로그당 1개, CLOSING이면 불가 |
| ACCEPTED / REJECTED | 받는 사람이 응답(expires_at 전) |
| AUTO_CANCELED | expires_at(요청 + 7일) 지남, 폐쇄 버튼, 받는 사람이 나감·강퇴 |

## blog_sanctions (멤버 제재)

| sanction_type | suspend_period | starts_at / ends_at |
|---|---|---|
| WARNING | NULL | 처리 시각 / NULL |
| SUSPEND | DAYS_3·DAYS_14·DAYS_30·PERMANENT | 처리 시각 / 시작 + 기간(영구는 NULL) |
| UNSUSPEND | NULL | 해제 시각 / NULL |
| KICK | NULL | 처리 시각 / NULL |

- 진행 중 정지: 그 (블로그, 회원)의 가장 최근 SUSPEND가 아직 안 끝났고 그 뒤 UNSUSPEND가 없음.
- 정지 횟수: 그 블로그에서 최근 1년(`blog.sanction.count-window=365d`) 안에 시작한 SUSPEND 수, 해제된 것 포함. 3번(`blog.sanction.kick-suggest-count`) 이상이면 표시(FR-053, D-95).
- `report_id`: 신고 처리에서 나온 제재면 연결.
- 1년 보관(FR-055) 후 삭제는 005에서 만든다(research R-10).

## blog_blacklists (블랙리스트)

| 컬럼 | 규칙 | 근거 |
|---|---|---|
| sanction_id | 원인 KICK 기록 | FR-056 |
| name_hash / email_hash / phone_hash | HMAC-SHA256(`BLACKLIST_HASH_SECRET`) 16진수 64자. 정규화 후 계산(research R-09) | FR-057, 4.6 |
| released / released_at | 해제 문의 승인 때만 true. 그 외 수정·삭제 없음 | FR-059 |

- 신청 막기: `released = false AND (email_hash = ? OR phone_hash = ?)`인 행이 있으면 막는다. 같은 블로그만 본다(FR-024, FR-058).
- 폐쇄 30일 뒤 정리에서 해제 문의와 함께 지운다(FR-060).

## blacklist_appeals (해제 문의)

| 컬럼 | 규칙 |
|---|---|
| blacklist_id | 문의한 회원과 맞는 해제 안 된 블랙리스트 중 가장 최근 것 |
| name_matched / phone_matched | 문의할 때 서버가 계산해 저장 |
| content | 선택, 최대 1000자 |
| status | PENDING → RELEASED·REJECTED. 블로그 폐쇄 때 PENDING은 REJECTED |

- 같은 블로그(블랙리스트의 blog_id 기준)에 PENDING은 회원당 1개. 마지막 REJECTED 처리 후 7일(`blog.appeal.retry-after`) 뒤 다시 문의(FR-061, D-98 #25).

## blog_subscriptions (구독, 002는 최소 범위)

- (user_id, blog_id) 유니크. 공개 범위가 바뀌어도 유지. 폐쇄 알림·비공개 전환 알림의 대상.

## blog_closing_notices (폐쇄 알림 기록)

- (blog_id, close_scheduled_at, stage, user_id) 유니크. stage는 IMMEDIATE·D3·D1·WITHDRAWN. `INSERT IGNORE`로 넣어 두 번 보내지 않는다(FR-077).

## reports (route = BLOG만)

- 002는 처리만: `status PENDING → DONE`, `result`는 NONE·WARNING·SUSPEND·KICK, `handled_by`, `handled_at`. 만드는 것은 003.

## images (owner_type = BLOG_COVER)

- 블로그당 `deleted_at IS NULL`인 행 1개. 3MB, jpg·jpeg·png·gif·webp, 재인코딩·메타데이터 제거(001 R-11). 바꾸거나 지우면 `deleted_at`, 30일 뒤 파일·행 삭제. 블로그 폐쇄 30일 뒤 정리에서도 지운다.

## posts (author_left만)

- 블로그 탈퇴·강퇴 때 `UPDATE posts SET author_left = true WHERE blog_id = ? AND author_id = ?`(FR-056, FR-064). 다시 참여해도 예전 글은 그대로 "탈퇴한 계정"이다. *가정*

## 알림 종류 (notifications에 쓰는 것)

| notification_type | tab | 받는 사람 | 끌 수 있음(설정 컬럼) | 근거 |
|---|---|---|---|---|
| JOIN_REQUESTED | BLOG | 블로그장, 멤버 관리 권한 부블로그장 | join_request | FR-021 |
| JOIN_APPROVED / JOIN_REJECTED | BLOG | 신청자 | join_result | FR-022, FR-023 |
| BLOG_PRIVATE | BLOG | 구독자 | 없음 | FR-031 |
| MEMBER_WARNED / MEMBER_SUSPENDED / MEMBER_UNSUSPENDED / MEMBER_KICKED | OPERATION | 대상 | 없음 | FR-054 |
| REPORT_RESOLVED | OPERATION | 신고자 | report_result | FR-052 |
| APPEAL_RELEASED / APPEAL_REJECTED | OPERATION | 문의자 | 없음 | FR-063 |
| DELEGATION_REQUESTED | OPERATION | 받는 멤버 | 없음 | FR-069 |
| DELEGATION_ACCEPTED / DELEGATION_REJECTED / DELEGATION_CANCELED | OPERATION | 블로그장(요청한 사람) | 없음 | FR-069 |
| BLOG_CLOSING | BLOG | 블로그장 뺀 멤버 + 구독자 | 없음 | FR-076, FR-077 |
| BLOG_CLOSING_WITHDRAWN | BLOG | 같은 대상 | 없음 | FR-078 |
| BLOG_CLOSED_REQUEST_REJECTED | BLOG | 폐쇄 때 자동 거절된 신청자·문의자 | 없음 | D-98 #15 |

`event_key` 예: `JOIN_REQUESTED:{requestId}`, `BLOG_CLOSING:{blogId}:{yyyyMMddHHmm}:{stage}`, `MEMBER_SUSPENDED:{sanctionId}`.

## 설정값 (application.yml, D-68)

| 키 | 기본값 | 환경변수 | 근거 |
|---|---|---|---|
| blog.limit.public | 3 (1~5) | BLOG_LIMIT_PUBLIC | FR-010, FR-011 |
| blog.limit.private | 5 | BLOG_LIMIT_PRIVATE | FR-010 |
| blog.address.reserved | main,admin,api,login,signup,search | BLOG_ADDRESS_RESERVED | FR-004 |
| blog.name.max-length | 30 | BLOG_NAME_MAX_LENGTH | FR-006 |
| blog.description.max-length | 500 | BLOG_DESCRIPTION_MAX_LENGTH | FR-006 |
| blog.tag.max-count | 10 | BLOG_TAG_MAX_COUNT | FR-001 |
| blog.tag.max-length | 20 | BLOG_TAG_MAX_LENGTH | 6.4 |
| blog.cover-image.max-size | 3MB | BLOG_COVER_IMAGE_MAX_SIZE | FR-007 |
| blog.list.page-sizes | 10,20,30 (기본 10) | BLOG_LIST_PAGE_SIZES | FR-014 |
| blog.search.min-length / max-length | 2 / 20 | BLOG_SEARCH_MIN_LENGTH / MAX_LENGTH | FR-015 |
| blog.join.reapply-after | 7d | BLOG_JOIN_REAPPLY_AFTER | FR-019 |
| blog.appeal.retry-after | 7d | BLOG_APPEAL_RETRY_AFTER | FR-061 |
| blog.delegation.expire-after | 7d | BLOG_DELEGATION_EXPIRE_AFTER | FR-068 |
| blog.closing.grace-days | 7 | BLOG_CLOSING_GRACE_DAYS | FR-073 |
| blog.closing.hour | 4 | BLOG_CLOSING_HOUR | FR-073 |
| blog.closing.notice-days | 3,1 | BLOG_CLOSING_NOTICE_DAYS | FR-076 |
| blog.closing.purge-after | 30d | BLOG_CLOSING_PURGE_AFTER | FR-081 |
| blog.sanction.count-window | 365d | BLOG_SANCTION_COUNT_WINDOW | FR-053 |
| blog.sanction.kick-suggest-count | 3 | BLOG_SANCTION_KICK_SUGGEST_COUNT | FR-053 |
| blog.cover-image.purge-after | 30d | BLOG_COVER_IMAGE_PURGE_AFTER | 프로필 사진과 같음 |
| blacklist.hash-secret | (없음, 필수) | BLACKLIST_HASH_SECRET | research R-09 |
