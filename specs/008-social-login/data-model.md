# 데이터 모델: 소셜 로그인

## 바뀌는 표

### users
- `password_hash`: NOT NULL → NULL 허용. NULL이면 이메일 로그인 불가(FR-009).

## 새 표

### social_accounts — 소셜 연결
| 컬럼 | 타입 | 설명 |
|---|---|---|
| id | BIGINT PK | 번호 |
| user_id | BIGINT FK → users.id | 회원 |
| provider | VARCHAR(10) | GOOGLE·KAKAO·NAVER (CHECK) |
| provider_user_id | VARCHAR(100) | 그 서비스의 회원 고유 번호 |
| email | VARCHAR(255) NULL | 연결할 때의 이메일(참고용) |
| created_at | DATETIME(6) | 연결 일시 |

- UNIQUE(provider, provider_user_id): 한 소셜 계정은 한 회원에게만(FR-002, FR-011).
- UNIQUE(user_id, provider): 회원당 서비스별 하나.
- 탈퇴하면 바로 삭제(FR-012).

### social_pendings — 가입·연결 대기
| 컬럼 | 타입 | 설명 |
|---|---|---|
| id | BIGINT PK | 번호 |
| token_hash | VARCHAR(100) UNIQUE | 브라우저에 준 대기 토큰의 해시 |
| provider | VARCHAR(10) | GOOGLE·KAKAO·NAVER |
| provider_user_id | VARCHAR(100) | 고유 번호 |
| email | VARCHAR(255) NULL | 확인된 이메일. 없으면 FR-016 인증 뒤 채움 |
| purpose | VARCHAR(10) | SIGNUP·LINK (CHECK) |
| remember_me | BOOLEAN | 로그인 유지 체크 |
| expires_at | DATETIME | SIGNUP 30분, LINK 10분(설정값) |
| created_at | DATETIME(6) | 생성 일시 |

- 끝나거나 만료되면 삭제. 남은 것은 04:00 정리 작업이 지움.
