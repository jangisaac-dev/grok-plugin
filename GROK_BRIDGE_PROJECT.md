# Grok Bridge Project

## 1. 프로젝트 목적

Claude Code 안에서 OpenAI Codex plugin처럼 Grok Build CLI를 로컬 보조 작업자로 호출한다.

이 프로젝트는 서버 제품이 아니다.  
다중 사용자 중계 서비스가 아니다.  
OAuth 토큰을 추출하거나 공유하지 않는다.  
공식 로컬 `grok` CLI와 사용자의 로컬 로그인 세션 또는 `XAI_API_KEY`만 사용한다.

---

## 2. 기본 구조

```text
Claude Code
  → /grok:* command
  → local wrapper script
  → grok CLI headless 실행
  → 결과를 .ai-runs/grok/<job-id>/ 에 저장
  → Claude Code가 결과를 읽고 최종 판단
```

---

## 3. 핵심 원칙

1. 모든 작업은 사용자의 로컬 머신에서 실행한다.
2. 기본 모드는 read-only review다.
3. 파일 수정은 명시적 승인 없이는 수행하지 않는다.
4. 결과는 stdout에만 의존하지 말고 반드시 파일로 저장한다.
5. Grok은 메인 구현자가 아니라 별도 시각의 리뷰어/검색형 보조자/대안 제안자로 사용한다.
6. Codex, Claude와 충돌하지 않도록 역할을 분리한다.

---

## 4. 권장 명령 세트

```text
/grok:review
/grok:adversarial-review
/grok:plan
/grok:rescue
/grok:status
/grok:result
/grok:cancel
```

| 명령 | 목적 |
|---|---|
| `/grok:review` | 현재 git diff를 읽고 버그, 회귀, 보안 문제를 리뷰 |
| `/grok:adversarial-review` | 의도적으로 반대자 관점에서 설계/구현의 약점 지적 |
| `/grok:plan` | 구현 전 대안 설계 및 작업 계획 생성 |
| `/grok:rescue` | Claude/Codex가 막혔을 때 별도 해결안 생성 |
| `/grok:status` | 실행 중인 Grok job 상태 확인 |
| `/grok:result` | 저장된 결과 회수 |
| `/grok:cancel` | 실행 중인 작업 중단 |

---

## 5. 권장 폴더 구조

```text
~/.claude/plugins/grok-bridge/
  plugin.json
  commands/
    review.md
    adversarial-review.md
    plan.md
    rescue.md
    status.md
    result.md
    cancel.md
  scripts/
    grok-review.sh
    grok-adversarial-review.sh
    grok-plan.sh
    grok-rescue.sh
    grok-status.sh
    grok-result.sh
    grok-cancel.sh
    job-runner.sh
  agents/
    grok-reviewer.md
    grok-rescuer.md
  skills/
    grok-local-cli/
      SKILL.md
```

프로젝트별 실행 결과는 repo 내부에 저장한다.

```text
.ai-runs/
  grok/
    <job-id>/
      prompt.md
      context.txt
      result.md
      result.json
      status.json
```

---

## 6. wrapper 실행 흐름

```text
1. repo root 확인
2. job-id 생성
3. .ai-runs/grok/<job-id>/ 생성
4. git diff, staged diff, branch 정보, 파일 목록 수집
5. 명령 목적에 맞는 prompt.md 생성
6. grok --no-auto-update -p "$PROMPT" 실행
7. 가능하면 --output-format json 또는 streaming-json 사용
8. stdout/stderr/status를 모두 파일로 저장
9. Claude Code는 result.md/result.json을 읽고 최종 판단
```

---

## 7. Grok 역할 정의

Grok은 다음 작업에 우선 사용한다.

- 반대자 리뷰
- 최신 검색 기반 검증
- UI/이미지/영상 관련 아이디어
- 설계 대안 생성
- Codex/Claude 결과물의 외부 시각 검토
- 코드베이스 구조 이해 보조

Grok을 다음 작업의 최종 판정자로 사용하지 않는다.

- 신학/성경 원어 최종 판정
- 보안 패치 자동 적용
- 대규모 파일 수정
- 배포 명령 실행
- 인증/토큰/비밀키 관련 변경

---

## 8. 기본 리뷰 프롬프트 템플릿

```text
You are Grok running as a local secondary reviewer for this repository.

Task:
Review the provided git diff and context.

Focus:
- correctness bugs
- security risks
- regression risk
- unnecessary complexity
- missing tests
- edge cases
- maintainability

Rules:
- Do not rewrite the entire solution.
- Do not suggest unrelated architecture changes.
- Do not modify files.
- Return concise actionable findings.
- Prioritize issues by severity.
- If no serious issue exists, say so directly.

Output format:
1. Critical issues
2. Important issues
3. Minor suggestions
4. Missing tests
5. Final verdict
```

---

## 9. Adversarial Review 프롬프트 템플릿

```text
You are Grok running as an adversarial reviewer.

Task:
Attack the current plan or implementation.

Assume the implementation may be subtly wrong.
Find the weakest assumptions, hidden coupling, bad abstractions, and cases where this will fail in production.

Rules:
- Be concrete.
- Cite exact files, functions, or diff sections when possible.
- Do not be polite.
- Do not invent issues.
- Separate real blockers from preferences.

Output:
- Blockers
- High-risk assumptions
- Failure scenarios
- Simpler alternatives
- Final verdict
```

---

## 10. 안전 기준

허용:

```text
내 로컬 머신
내 Claude Code
내 Grok CLI 로그인
내 프로젝트
공식 CLI 호출
결과 파일 저장
```

금지:

```text
OAuth 토큰 추출
세션 파일 복사
다른 사용자에게 내 계정 중계
웹/API 서버로 프록시화
rate limit 우회
자동 배포/삭제/결제 명령 실행
```

---

## 11. 최종 운영 포지션

```text
Claude = 총괄 판단자
Codex = 실제 구현/수정/테스트
Grok = 반대자 리뷰/검색/멀티모달/대안 생성
```

Grok Bridge는 Codex 대체제가 아니라 **두 번째 독립 관점의 로컬 보조 작업자**다.
