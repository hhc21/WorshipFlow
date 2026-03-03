## Summary
- What changed?
- Why was this needed?

## Scope
- [ ] Phase 1 (Infra / CI-CD)
- [ ] Phase 2 (Tests / Coverage Gate)
- [ ] Phase 3 (Tech Debt / Refactor)

## Plan Gate
- [ ] `PLAN-APPROVED` confirmed in chat
- [ ] `plan-approved` label attached

## Validation
- [ ] `flutter analyze`
- [ ] `flutter test --coverage`
- [ ] `scripts/ci/check_coverage.sh`
- [ ] `flutter build web --release`

## Risk Check
- [ ] Auth / Rules impact reviewed
- [ ] Team/Project self-healing flow regression checked
- [ ] Delete flow safety reviewed (project/team)

## Deployment
- [ ] Staging deploy candidate
- [ ] Production deploy candidate
- [ ] Rollback notes updated in `docs/release_runbook.md`

