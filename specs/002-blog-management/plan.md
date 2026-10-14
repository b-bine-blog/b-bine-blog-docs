# 구현 계획 (Implementation Plan): 블로그 생성·참여·운영

**브랜치**: `002-blog-management` | **날짜**: 2026-10-08 | **명세**: [spec.md](spec.md)

**입력**: `specs/002-blog-management/spec.md` (확인 필요 항목 0개, D-98까지 반영)

## 요약 (Summary)

회원이 블로그를 만들고(이름·주소·소개·대표 이미지·태그·공개 범위·참여 방식), 목록·검색으로 찾아 참여하고, 블로그장과 부블로그장이 멤버·제재·블랙리스트·위임·폐쇄를 운영하는 기능을 만든다.
001과 같은 단일 Spring Boot 앱에 `blog` 패키지를 더한다. 블로그별 역할은 요청마다 `blog_members`에서 확인하고(research R-01), 매일 04:00 처리는 001의 `DailyCleanupJob`에 블로그 단계를 더한다(R-13).
ERD는 이미 배포된 Crowfoot 문서 654의 블로그 영역 테이블을 그대로 쓰며 **DB 변경은 없다**(data-model).

## 기술 맥락 (Technical Context)

**언어/버전**: Java 21, Spring Boot 3.5.16 (001 R-01)

**주요 의존성**: 001과 같음(Web, Security, Data JPA, Validation, Mail, jjwt, ShedLock). 새 의존성 없음

**저장소**: MySQL 8(Crowfoot 문서 654). 대표 이미지는 `FileStorage` → 서버 디스크(D-75)

**테스트**: JUnit 5, MockMvc, Testcontainers MySQL 8.0, `MutableClock`, 001의 `IntegrationTestBase`

**대상 플랫폼**: Linux 서버 1대(1차), PC·모바일 브라우저

**프로젝트 종류**: 웹 서비스(REST API + 정적 화면, 단일 Spring Boot 앱)

**성능 목표**: 목록·검색 1초 목표, 2초 이내(SC-001)

**제약**: 서버에 상태를 두지 않는다. 공유 링크 열람도 쿠키 + DB로 판단한다(R-06). 숫자 규칙은 모두 설정값으로 둔다(D-68). 다른 회원의 이메일·전화번호 원문은 응답에 넣지 않는다(D-22).

**규모/범위**: API 38개(경로 28개). 화면 6개는 블로그 만들기, 블로그 홈, 운영, 내 블로그, 블로그 목록·검색(메인), 공유 링크 진입이다. 테이블 15개를 쓰고 새로 만드는 테이블은 없다.

**다른 기능과 나눈 범위** (research R-11, R-14, R-15):
- 알림: 002는 쓰기만 하고, 보기·폴링은 003에서 만든다.
- 신고: 002는 처리만 하고, 만들기는 003에서 만든다.
- 구독: 002는 최소 범위만 만든다.
- 차단: 002는 읽기만 한다.
- 다른 멤버 글 삭제(FR-037): 004의 글 기능에서 만든다. 002는 권한 확인 `POST_MANAGE`만 준비한다.
- 블로그장 강퇴 뒤 승계(FR-082)와 관리자 강제 폐쇄(FR-084): 002가 서비스 메서드를 만들고, 005의 관리자 API가 이를 부른다.
- FR-083(블로그장 알림 설정): 003의 알림 설정 화면에서 만든다.

## 헌장 확인 (Constitution Check)

*Phase 0 전 확인, Phase 1 설계 후 다시 확인함.*

| 원칙 | 이 계획에서 지키는 방법 | 결과 |
|---|---|---|
| I. 보안 우선 | 모든 상태 변경 API에 CSRF(001과 같음). 대표 이미지는 001의 검사·재인코딩을 그대로 쓴다(R-05). 공유 링크는 32바이트 무작위 값이고 쿠키는 HttpOnly다(R-06). 블랙리스트는 HMAC 해시로 저장한다(R-09). 검색어는 바인딩 파라미터와 구절 검색으로 넘긴다(R-07). 응답은 DTO로만 만든다 | 통과 |
| II. 블로그별 역할 서버 확인 | `@PreAuthorize` + `BlogPermissionService`가 요청마다 `blog_members`와 진행 중 정지를 조회한다(R-01). 토큰에는 회원 번호만 있다. 권한표는 data-model에 있다. 다른 블로그 요청은 403이고 SC-004 테스트로 확인한다 | 통과 |
| III. 개인정보 서버에서 가림 | 멤버 관리 응답에는 `maskedEmail`·`maskedPhone`만 넣는다(R-16). 블랙리스트·해제 문의 응답에는 해시·원문 없이 일치 여부만 넣는다. 폐쇄 30일 뒤 블랙리스트를 지운다(R-13) | 통과 |
| IV. 서버에 상태를 두지 않음 | 개수 제한과 동시성은 DB 행 잠금으로 처리한다(R-02, R-17). 공유 링크는 쿠키 + DB로 확인한다. 04:00 처리는 ShedLock으로 한 번만 돈다. 이미지는 `FileStorage`에 둔다. 설정값은 환경변수로 바꾼다 | 통과 |
| V. 명세와 결정이 먼저 | 모든 API에 FR 번호가 있다(contracts). 문서에 없어 구현 기본값으로 둔 것은 research에 *가정*으로 표시했고, 아래 "확인할 가정"으로 사용자에게 보고한다 | 통과(가정 보고) |
| VI. 단순하게 시작 | 새 테이블·라이브러리가 없다. 검색은 MySQL ngram 전문 검색을 쓴다. 알림·구독은 필요한 최소만 만든다 | 통과 |

**설계 후 다시 확인**: data-model과 contracts에서 새로 생긴 위반은 없다. ERD 변경이 없으므로 Crowfoot 마이그레이션도 필요 없다.

## 확인할 가정 (문서에 없어 기본값으로 둔 것)

사용자가 "일단 만들고 수정하자"(2026-10-08)고 해서 아래 기본값으로 진행한다. 다르면 고친다.

1. 생성 개수는 "지금 블로그장인 운영 중·폐쇄 예정 블로그"로 센다. 위임받은 블로그도 센다(R-02).
2. 비공개 블로그에는 참여 신청 경로가 없다(404). 멤버는 다른 경로로 들어오지 않는다(R-08).
3. 숨김 블로그는 목록·검색에서만 뺀다. 접근 규칙은 005에서 정한다(R-06).
4. 검색 정렬 기본값은 최신순이다(R-07).
5. 위임받을 사람이 블로그를 나가거나 강퇴되면 대기 중 위임 요청을 자동 취소한다(R-12).
6. 다시 참여해도 예전 글은 "탈퇴한 계정"으로 남는다(data-model posts).
7. 제재·신고 기록 1년 뒤 삭제와 FR-083 알림 설정 화면은 각각 005, 003에서 만든다.
8. 블랙리스트 해시는 비밀키 HMAC으로 만든다(R-09). 키를 잃으면 기존 블랙리스트와 비교할 수 없다.

## 프로젝트 구조 (Project Structure)

### 문서 (이 기능)

```text
specs/002-blog-management/
├── spec.md
├── clarify-questions.md
├── plan.md              # 이 파일
├── research.md          # Phase 0
├── data-model.md        # Phase 1
├── quickstart.md        # Phase 1
├── contracts/
│   └── blog-api.yaml
└── tasks.md             # Phase 2 (/speckit-tasks)
```

### 소스 코드 (저장소 루트, 001에 더하는 것)

```text
src/main/java/com/mainblog/
├── common/
│   ├── tag/             # TagNormalizer (6.4, 004에서도 씀)
│   ├── masking/         # PhoneMasker 추가
│   ├── notification/    # NotificationWriter, NotificationType, NotificationSettingKey (003에서 보기 기능 추가)
│   └── config/          # BlogProperties, BlacklistProperties
├── blog/
│   ├── api/             # BlogController(생성·조회·수정·목록·검색·내 블로그), BlogCoverImageController,
│   │                    # JoinRequestController, ShareLinkController, SubscriptionController,
│   │                    # MemberManageController(멤버·부블로그장·탈퇴), SanctionController, BlogReportController,
│   │                    # BlacklistController(열람·문의), DelegationController, ClosingController, BlogPageController(/blog/** forward)
│   ├── application/     # BlogService, BlogQueryService, BlogPermissionService(@blogAuth), BlogAccessPolicy,
│   │                    # BlogLimitPolicy, BlogAddressPolicy, JoinService, ShareLinkService, SubscriptionService,
│   │                    # MemberManageService, SanctionService, BlogReportService, BlacklistService, BlacklistHasher,
│   │                    # AppealService, DelegationService, BlogClosingService, OwnerSuccessionService, BlogDailyTasks
│   └── domain/          # Blog, BlogMember, BlogShareLink, BlogTag, Tag, BlogJoinRequest, BlogDelegation,
│                        # BlogSanction, BlogBlacklist, BlacklistAppeal, BlogSubscription, BlogClosingNotice,
│                        # BlogCoverImage(images), BlogReport(reports 읽기·처리) (+ Repository, enum)
└── batch/
    └── DailyCleanupJob.java   # BlogDailyTasks 단계 추가(위임 만료 → D3·D1 알림 → 폐쇄 → 30일 정리 → 대표 이미지 정리)

src/main/resources/
├── application.yml      # blog.*, blacklist.* 설정값 (data-model "설정값")
└── static/
    ├── index.html       # 메인: 블로그 목록(최신·인기, 페이지)과 블로그 검색
    ├── blogs/new.html   # 블로그 만들기
    ├── blog/index.html  # /blog/{주소} 블로그 홈(정보, 참여·구독·공유 버튼, 정지 안내, 블랙리스트 안내·문의)
    ├── blog/manage.html # 운영: 정보 수정, 참여 신청, 멤버·부블로그장, 제재, 신고, 블랙리스트·문의, 위임, 폐쇄
    ├── me/blogs.html    # 내 블로그(운영하는·참여한), 받은 위임 요청
    └── js/blog-*.js

src/test/java/com/mainblog/
├── blog/                # 사용자 스토리별 통합 테스트, 정책 단위 테스트
├── common/              # TagNormalizer, PhoneMasker 단위 테스트
├── contract/            # OpenApiConformanceTest에 blog-api.yaml 추가
└── perf/                # BlogResponseTimeTest
```

**구조 결정**: 001과 같은 기능 단위 패키지를 쓴다. 블로그 운영 기능이 많아 컨트롤러는 영역별로 나누되, 권한 확인은 `BlogPermissionService` 한 곳에 모은다. 알림 쓰기와 태그 정규화는 003·004에서도 쓰므로 `common`에 둔다.

## 구현 전에 할 일

1. **비밀키 추가**: `.env.example`과 운영 환경변수에 `BLACKLIST_HASH_SECRET`을 넣는다(R-09).
2. **001 브랜치 병합 순서**: 002 브랜치는 `001-member-auth` 위에 있다. PR #1 → PR #2 → 002 PR 순서로 병합한다.

## 복잡도 기록 (Complexity Tracking)

헌장 위반 없음.
