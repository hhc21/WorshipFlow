# WorshipFlow Documentation Index

이 문서는 WorshipFlow 저장소의 문서 구조를 설명한다.

원칙:
- 루트 md 문서는 **제품 기준선(canonical)** 문서다.
- docs 폴더는 **운영 / 테스트 / 런북 / 기술부채** 문서를 포함한다.

---

# 1. Canonical Product Documents (Root)

제품 구조와 개발 기준선을 정의하는 핵심 문서.

- `plan.md`  
  실행 기준선 및 SP 진행 상태 정의

- `research.md`  
  현재 코드 상태 및 기술 분석

- `product_roadmap.md`  
  제품 전략 및 단계 로드맵

- `system_architecture.md`  
  전체 시스템 구조

- `data_model.md`  
  Firestore canonical 데이터 모델

- `firestore_rules.md`  
  Firestore 권한 모델

- `livecue_protocol.md`  
  LiveCue 동기화 및 상태 해석 규약

---

# 2. Operations / Runbooks (docs)

운영 및 장애 대응 문서.

- `docs/release_runbook.md`  
  SP-07 Release Gate 및 배포 절차

- `docs/livecue_incident_runbook.md`  
  LiveCue 장애 대응 절차

- `docs/livecue_repro_matrix.md`  
  브라우저/환경 재현 매트릭스

---

# 3. Engineering Operations

개발 운영 및 정책 문서.

- `docs/test_strategy.md`  
  테스트 전략

- `docs/security_key_rotation_runbook.md`  
  Firebase 키 교체 절차

- `docs/tech_debt_register.md`  
  기술부채 기록

---

# 4. Experimental / Reference

실험 또는 참고 문서.

- `docs/delete_queue_poc.md`
- `docs/web_cache_strategy.md`
- `docs/feature_checklist.md`

---

# 5. Governance Rule

문서 변경 규칙:

1. 제품 구조 변경 → canonical 문서 수정
2. 운영 절차 변경 → docs runbook 수정
3. 코드 기준과 문서 불일치 시 → **코드 기준으로 plan.md 업데이트**

---

# 6. Quick Navigation

개발 시작 순서:

1. `plan.md`
2. `system_architecture.md`
3. `data_model.md`
4. `livecue_protocol.md`
5. `docs/release_runbook.md`