# CLAUDE.md

메인블로그(티스토리형 블로그 플랫폼) 프로젝트에서 AI 코딩 에이전트가 따를 규칙입니다.
이 저장소는 문서 저장소입니다(D-130). 소스 코드는 [b-bine-blog](https://github.com/b-bine-blog/b-bine-blog)에 있고, 이 저장소 옆에 `../b-bine-blog`로 받아 두고 작업합니다.
API 계약(OpenAPI)은 소스 저장소의 `api-contracts/`, 테이블 정의는 `db/schema.sql`에 있습니다(테스트가 직접 읽기 때문).

## 프로젝트 한 줄 요약

회원이 메인블로그에서 가입·로그인하고, 개별 블로그를 만들거나 참여해 함께 운영하는 블로그 플랫폼.
블로그장·멤버는 계정 종류가 아니라 블로그별 역할입니다.

## 문서를 읽는 순서

1. `.specify/memory/constitution.md` — 반드시 지킬 원칙(보안, 블로그별 역할 확인, 개인정보, 이중화 대비)
2. `specs/README.md` — 기능별 명세 목록. 기능을 만들 때는 해당 `specs/<번호>-<기능>/spec.md`를 기준으로 함
3. `docs/README.md` — 원본 요구사항 문서 목차
4. `docs/01-requirements/` — 기능·비기능 요구사항, 구현 방식(7장)
5. `docs/02-policies/` — 숫자와 세부 규칙(글자 수, 용량, 만료 시간 등)
6. `docs/03-decisions/` — 왜 그렇게 정했는지(D-번호)

## Spec Kit 흐름

이 저장소는 [Spec Kit](https://github.com/github/spec-kit)으로 명세 → 계획 → 작업 → 구현 순서로 개발합니다(`.claude/skills/speckit-*`).
명세·계획·작업 목록은 이 저장소에, API 계약은 소스 저장소 `api-contracts/`에, 테이블 정의는 소스 저장소 `db/schema.sql`에 둡니다(D-130).
`/speckit-specify` → `/speckit-clarify` → `/speckit-plan` → `/speckit-tasks` → `/speckit-implement`.
명세의 `[NEEDS CLARIFICATION]` 항목은 임의로 정하지 않고 `/speckit-clarify`로 사용자에게 묻습니다.

요구사항과 코드가 다르면 코드를 고치기 전에 사용자에게 먼저 확인합니다.
마크다운 변환본과 원본이 다르면 `docs/01-requirements/요구사항분석서_원본_2026-10-07.md`가 기준입니다(이후 결정은 `docs/03-decisions/`).

## 기술 스택 (요구사항분석서 7장 기준, 모두 확정)

- 백엔드: Spring Boot, Spring Security(보안 헤더, CSRF, 인증·인가) — D-09
- DB: MySQL. Refresh Token도 DB에 저장 — D-82
- 로그인: JWT + HttpOnly 쿠키, "로그인 유지" 체크박스(미체크 30분 무활동 로그아웃, 체크 14일) — D-53, D-61, D-62
- 비밀번호: bcrypt — D-81
- 화면: 정적 HTML + JS(API 호출). 글 상세만 서버가 og 태그를 채움 — D-66
- 에디터: Toast UI Editor(마크다운 저장) — D-74
- XSS: 서버에서 마크다운→HTML 변환 후 jsoup으로 걸러냄. 화면은 글 본문만 innerHTML, 나머지는 textContent — D-64
- CSRF: 모든 JS 요청에 `X-XSRF-TOKEN` 헤더(공통 api.js에서 처리)
- 메일: Gmail SMTP, 6자리 인증번호를 Spring에서 직접 발송·검증 — D-10, D-69
- 사람 확인: Cloudflare Turnstile — D-79
- 알림: 30초 폴링 — D-72
- 이미지: 1차 서버 디스크, FileStorage 인터페이스로 분리(이중화 때 S3) — D-75
- 블로그 주소: 경로 방식 `/blog/{주소}` — D-70

## 요구사항 ID 규칙

`모듈-번호` 형식: USR(회원), BLG(블로그), SOC(소셜), BRD(게시판), ADM(관리자), SEC(보안), SCL(확장성).
코드 주석, 커밋 메시지, PR 설명에서 관련 요구사항 ID와 결정 번호를 적습니다. 예: `BLG-09, D-12`.

## 일하는 규칙

- 새 결정을 하거나 기존 결정을 바꾸면 `docs/03-decisions/`에 다음 번호로 파일을 추가하고 목차(README)를 갱신합니다.
  바꾼 경우 이전 결정 파일의 상태를 `변경됨 → D-xx`로 고칩니다.
- 기능별 계획·데이터 모델·작업 목록은 Spec Kit대로 `specs/<번호>-<기능>/`(plan.md, data-model.md, tasks.md)에 두고, API 계약은 소스 저장소 `api-contracts/`에 둡니다.
  여러 기능에 걸치는 설계(전체 ERD, 아키텍처)는 `docs/04-design/`, 전체 일정·로드맵은 `docs/05-plans/`에 둡니다.
- 숫자 규칙(제한값, 만료 시간)은 하드코딩하지 않고 설정값으로 둡니다. 예: `blog.limit.public=${BLOG_LIMIT_PUBLIC:3}` — D-68
- 개인정보(이메일·전화번호)는 서버에서 가려서 응답합니다(4.4). 화면에서만 가리지 않습니다 — D-22
- 아직 정하지 않은 항목(4.3 이중화 기술, 명세의 `[NEEDS CLARIFICATION]`)은 임의로 정하지 말고 사용자에게 묻습니다.
