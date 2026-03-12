# Post Deploy Runtime Issues

Environment  
Production (Firebase Hosting)

URL  
https://worshipflow-df2ce.web.app

Deploy version  
wf-v1.0.0

---

# Issue 1 — LiveCue first-entry render latency

## Symptom

Entering LiveCue shows:

LiveCue 상태 동기화 지연

## Steps to reproduce

1. login
2. go to team
3. open project
4. click LiveCue tab

## Expected

LiveCue should render score state without long startup delay.

## Actual

LiveCue eventually loads, but first score render can take about 15 seconds.

## Suspected causes

Possible first-entry timing instability around:
- auth readiness
- first snapshot attach timing
- watchdog start timing
- re-entry mode transition timing

---

# Issue 2 — Setlist reorder numbering stale after reorder

## Symptom

Setlist reorder works, but visible leading numbers do not refresh correctly after move up/down.

## Steps

1. open project setlist
2. reorder items
3. verify item ordering changed
4. check visible numbering labels

## Expected

Displayed numbering should immediately match current order.

## Actual

Order is updated, but rendered numbering remains stale for one or more items.

## Suspected causes

Display label appears to be cached/persisted and not fully recomputed from current order on every render.

---

# Status

Deploy succeeded.

Core flows working:

- login
- team
- project
- library
- song registration

Latest manual verification PASS:
- problem song resolution (`주의 집에 거하는 자`)
- in-app preview flow

Residual runtime issues:
- LiveCue first-entry render latency (~15s)
- setlist reorder numbering stale after reorder
