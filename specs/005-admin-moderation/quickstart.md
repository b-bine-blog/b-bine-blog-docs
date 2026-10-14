# 005 메인 관리자·제재 확인 안내 (Quickstart)

**명세**: [spec.md](spec.md) | **API**: [contracts/admin-api.yaml](contracts/admin-api.yaml) | **데이터**: [data-model.md](data-model.md)

## 준비

- 자동 테스트: Docker가 돌고 있으면 `./gradlew test`(Testcontainers MySQL 8)로 전부 확인한다.
- 화면 확인: `local/start.sh`(Windows는 `local\start.bat`)로 MySQL·Mailpit·앱을 띄우고 http://localhost:8080/admin 을 연다. 시드 계정은 모두 비밀번호 `Passw0rd!`이다.
  - `admin@local.test`: 메인 관리자
  - `owner@local.test`: travel-log 블로그장
  - `member@local.test`: travel-log 멤버
  - `newbie@local.test`: 멤버 아님
- 신고는 003 신고 버튼으로 넣거나, 003이 아직 없으면 `local/seed.sql`의 관리자 신고 예시 행(T059에서 더함)을 쓴다.

## 시나리오별 확인

| # | 확인할 것 | 방법 | 기대 결과 | 근거 |
|---|---|---|---|---|
| 1 | 관리자만 들어감 | newbie·owner로 /admin, `/api/admin/members?type=NICKNAME&q=a` / 로그아웃 상태로 같은 요청 | 화면 404, API 403 `ADMIN_ONLY` / 401 | SC-002, D-103 #1 |
| 2 | 권한 회수 | admin 로그인 상태에서 DB로 role = USER, 다음 관리자 요청 | 403 `ADMIN_ONLY` | FR-002 |
| 3 | 회원 검색 | 닉네임 일부, 이메일 전체, 이메일 일부, 탈퇴 회원 닉네임 | 앞의 둘만 찾음, 일부 이메일·탈퇴 회원은 없음 | D-103 #2·#3 |
| 4 | 가림 | `abcdef@gmail.com`·`01012345678`·`ab@x.com` 회원 상세 응답 원문 | `ab***@gmail.com`, `010-****-5678`, `a***@x.com`, 이름 보임, 원문·비밀번호 없음 | SC-003, D-103 #4 |
| 5 | 전체 보기 | 상세에서 "전체 보기" → 다시 열기 → 활동 기록 | 원문 보임 → 다시 가림 → `PRIVACY_VIEW` 1건(관리자·시각·대상) | FR-008, D-103 #5 |
| 6 | 전체 보기 제한 | 1분에 31번 호출 | 31번째 429 `RATE_LIMITED` | research R-04 |
| 7 | 블로그 검색 | 공개·일부 공개·비공개·폐쇄 예정·폐쇄·숨김 블로그를 이름·주소·블로그장 닉네임으로, 상태 거르기 | 모두 상태와 함께, 블로그장·멤버 수·글 수 맞음 | D-103 #6, US2-1 |
| 8 | 블로그 숨김 | 공개 블로그 숨김 → 비회원·구독자·공유 링크·멤버로 열기, 메인 목록·검색·피드 → 해제 | 비회원·구독자·링크 404, 멤버는 보고 씀, 목록에서 빠짐, 블로그장 알림 1건, 해제 기록 | FR-012, D-103 #7 |
| 9 | 강제 폐쇄 | 10월 2일 15:00(Clock)에 폐쇄 → 04:00 처리를 10월 6·8·9일로 | 10월 9일 04:00 폐쇄, 멤버·구독자 알림 3번(블로그장 제외), 블로그장 철회 403 `ADMIN_CLOSE_LOCKED`·관리자 철회(`DELETE .../force-close`) 204, 운영 중·철회 알림·`RESTORE` 기록. 블로그장 폐쇄를 관리자가 철회하면 409 `NOT_ADMIN_CLOSE` | US2-3·6, D-94, D-104 |
| 10 | 폐쇄 예정 블로그 강제 폐쇄 | 블로그장이 폐쇄 누른 블로그에 강제 폐쇄 | 시각 그대로, 알림 다시 없음, 사유 ADMIN, `keptExisting: true` | D-103 #8 |
| 11 | 경고 3번 | 부블로그장 S1(10/1)·S2(10/3) 있는 블로그장에게 경고 3번(사유 포함) | 알림 "3번 중 1·2번", 3번째에 박탈, S1이 블로그장, 전 블로그장은 멤버, `OWNER_REVOKED` 알림 | US3-1~4, D-103 #12 |
| 12 | 바로 강퇴(부블로그장 없음) | 10월 2일 15:00에 강퇴, 대기 중 위임 요청 있음 | 10월 9일 04:00 폐쇄 예약, 알림 문구 "블로그장 권한 박탈로 인한 폐쇄 조치", 위임 요청 취소 + 받는 멤버 알림, 폐쇄 전까지 글쓰기 됨 | US3-5·6, D-103 #15·#17 |
| 13 | 동시 경고 | 경고 2번 받은 블로그장에게 두 관리자가 동시에 경고 10번 | 박탈 1번, 위임 또는 폐쇄 예약 1번, 나머지 409 `OWNER_CHANGED` | SC-005 |
| 14 | 경고 세기 | 1년 지난 경고 1 + 새 경고 2, 다른 블로그 경고, 새 블로그장 | 박탈 안 됨, 블로그별로 셈, 새 블로그장은 0부터 | D-95, D-103 #13 |
| 15 | 신고함 | 블로그 신고, 블로그장 신고, 블로그장 글 신고, 메인 프로필 신고, 멤버 글 신고(route BLOG) | 관리자 신고함에 앞의 4건, 블로그장 신고함에 멤버 글 신고만 | SC-007, D-93 |
| 16 | 신고 처리 | 네 결과를 각각 처리, 같은 신고 두 번, 신고자 알림 끈 경우 | 효과가 경고·강퇴·폐쇄와 같음, 두 번째 409, 꺼 두면 알림 없음(처리·기록은 남음) | US4, FR-034 |
| 17 | 글 숨김 | 멤버 글 숨김 → 작성자·블로그장·비회원으로 상세, 목록·검색·피드 | 작성자만 "관리자가 숨긴 글", 나머지 404, 목록에서 빠짐, 작성자 알림 1건 | D-103 #9·#10 |
| 18 | 글 삭제·복구 | 10월 1일 관리자 삭제 → 10월 20일 복구 / 작성자가 지운 글 복구 / 10월 31일 04:00 뒤 복구 | 알림 "내 글 삭제됨" → 복구·사진 보임·알림 / 409 `NOT_RESTORABLE` / 404 | US5-2·4, D-103 #11 |
| 19 | 남의 글 수정 | admin으로 `PUT /api/posts/{id}` | 403 | SC-008 |
| 20 | 댓글 | 댓글 숨김·삭제·복구, 답글 있는 최상위 댓글 숨김 | 작성자 알림 없음, "관리자가 숨긴 댓글입니다" 자리 | D-103 #9 |
| 21 | 블로그 활동 거부 | admin으로 블로그 만들기·참여 신청·글쓰기·댓글·좋아요·팔로우 | 모두 403, 공지 쓰기는 성공 | FR-004, D-90 |
| 22 | 활동 기록 | 관리자 둘이 조치 몇 개 → 기록 목록·거르기, 고치기·지우기 요청 | 조치자·시각·종류·대상 맞음, 고치는 API 없음(405·404) | US6, D-103 #20 |
| 23 | 1년 정리 | 기록 만들고 Clock 31일 뒤·366일 뒤 04:00 작업, 영구 정지 기록 | 31일 뒤 그대로, 366일 뒤 삭제, 영구 정지는 남음 | SC-004, D-103 #19 |
| 24 | 통계 | 10/1 회원 3명, 10/2 회원 5명과 관리자 1명 가입, 블로그 4개, 10/2 글 7개. 그 뒤 회원 1명 탈퇴, 글 1개 삭제 | 회원 수 7, 10/1 가입 3·10/2 가입 5, 블로그 4, 10/2 글 7, 빈 날 0 | US7, D-103 #21 |
| 25 | 개인정보 | 관리자 응답 전체(상세·"전체 보기" 제외)와 로그에서 이메일·전화번호 원문 찾기 | 0건 | SC-003 |
| 26 | 화면 | 360px·1280px에서 /admin 여섯 탭 | 가로 스크롤 없음, 표는 좁으면 카드 | SC-010 |

## 확인 결과

2026-10-08, 브랜치 `005-admin-moderation`. 1~25번은 자동 테스트(Testcontainers MySQL 8, 서버 시계는 `MutableClock`)로 확인했다. 전체 `./gradlew test` 결과는 아래 표 밑에 적었다.

| # | 결과 | 확인한 테스트 |
|---|---|---|
| 1·2 | 통과 | `admin/AdminAccessIntegrationTest`, `admin/AdminSecurityTest`(계약의 28개 요청 × 비회원·회원·블로그장·부블로그장·권한 회수 관리자) |
| 3~6 | 통과 | `admin/AdminMemberIntegrationTest` |
| 7 | 통과 | `admin/AdminBlogQueryIntegrationTest` |
| 8 | 통과 | `admin/AdminBlogHideIntegrationTest`, `blog/VisibilityIntegrationTest` |
| 9·10 | 통과 | `admin/AdminForceCloseIntegrationTest` |
| 11·12·14 | 통과 | `admin/OwnerWarningIntegrationTest`, `admin/OwnerRevocationIntegrationTest` |
| 13 | 통과 | `admin/OwnerConcurrencyTest`(두 관리자 × 10번, 블로그장 교체·폐쇄 예약 두 경우) |
| 15·16 | 통과 | `admin/AdminReportIntegrationTest`(15번은 003 신고 API로 넣은 신고) |
| 17~19 | 통과 | `admin/AdminPostModerationIntegrationTest` |
| 20 | 통과 | `admin/AdminCommentModerationIntegrationTest` |
| 21 | 통과 | `admin/AdminBlogActivityDeniedTest` |
| 22 | 통과 | `admin/AdminActionLogIntegrationTest`(16가지 조치 모두) |
| 23 | 통과 | `admin/AdminDailyTasksIntegrationTest` |
| 24 | 통과 | `admin/AdminStatsIntegrationTest` |
| 25 | 통과 | `admin/AdminSecurityTest` |
| 26 | **확인 안 함** | 이 작업 환경에서는 앱을 띄워 브라우저로 볼 수 없어 하지 못했다. 표는 720px 이하에서 카드로 바뀌도록 `css/base.css`에 넣었고, 모든 관리자 요청은 `api.js`의 5초 중단 안내(`activity: true`)를 쓴다. 360px·1280px 화면 확인은 `local/start.sh`로 띄워 직접 봐야 한다(tasks T056) |

- 응답 시간(SC-001): `perf/AdminResponseTimeTest` — 회원 10,000명·블로그 1,000개·신고 5,000건에서 회원 검색·블로그 검색·신고함·통계 모두 2초 안.
- 계약 대조: `contract/OpenApiConformanceTest` — 관리자 계약 22개 경로의 모든 메서드가 매핑돼 있고, 계약에 없는 `/api` 경로가 없다.
- 전체 `./gradlew test`: 598개 중 597개 통과, 실패 0, 건너뜀 1(화면 확인용 `support/UiPreviewServer`, 원래 꺼 둔 테스트). 17분 28초.
