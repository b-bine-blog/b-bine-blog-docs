# b-bine blog 문서

[b-bine blog](https://github.com/b-bine-blog/b-bine-blog) 프로젝트의 요구사항·정책·결정 기록·기능별 명세를 모아 둔 문서 저장소입니다(D-130).
소스 코드는 [b-bine-blog](https://github.com/b-bine-blog/b-bine-blog) 저장소에 있습니다. 👉 사이트: https://mainttblog.java21.net

## 무엇이 어디에 있나

| 위치 | 내용 |
|---|---|
| [docs/](docs/README.md) | 원본 요구사항(01), 세부 정책(02), 결정 기록 D-번호(03), 설계(04), 계획(05), 장애 기록(06) |
| [docs/03-decisions/](docs/03-decisions/README.md) | 정하거나 바꾼 것과 그 이유(최신순) |
| [specs/](specs/README.md) | 기능별 명세·계획·데이터 모델·작업 목록(Spec Kit) |
| [.specify/memory/constitution.md](.specify/memory/constitution.md) | 개발 원칙 |
| [.claude/skills/](.claude/skills/) | Spec Kit 명령(speckit-*) |

## 소스 저장소에 남긴 것

코드와 테스트가 직접 읽는 파일은 소스 저장소에 둡니다.

| 파일 | 위치 |
|---|---|
| API 계약(OpenAPI) | [b-bine-blog/api-contracts/](https://github.com/b-bine-blog/b-bine-blog/tree/main/api-contracts) — 테스트가 실제 응답과 비교 |
| 테이블 정의(DDL) | [b-bine-blog/db/schema.sql](https://github.com/b-bine-blog/b-bine-blog/blob/main/db/schema.sql) — 테스트가 이 파일로 DB를 만듦 |
| 개발환경 | [b-bine-blog/DEVELOPMENT.md](https://github.com/b-bine-blog/b-bine-blog/blob/main/DEVELOPMENT.md) |
| 브랜치 전략 | [b-bine-blog/CONTRIBUTING.md](https://github.com/b-bine-blog/b-bine-blog/blob/main/CONTRIBUTING.md) |
| 릴리스 노트 | [b-bine-blog/release-notes/](https://github.com/b-bine-blog/b-bine-blog/tree/main/release-notes) — 사이트 공지로 올라감 |

2026-10-14 이전 명세·작업 목록에 나오는 `docs/04-design/schema.sql`, `specs/<기능>/contracts/*.yaml`, `docs/04-design/development-environment.md`는 위 위치로 옮겼습니다.

## 함께 쓰는 법

두 저장소를 같은 폴더에 나란히 받습니다.

```bash
git clone https://github.com/b-bine-blog/b-bine-blog.git
git clone https://github.com/b-bine-blog/b-bine-blog-docs.git
```

기능을 만들 때는 이 저장소에서 명세(spec.md) → 계획 → 작업 목록을 만들고, 소스 저장소에서 구현합니다. 결정을 새로 하거나 바꾸면 이 저장소의 `docs/03-decisions/`에 D-번호로 남깁니다.
