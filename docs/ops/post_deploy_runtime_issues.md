# Post Deploy Runtime Issues

Environment  
Production (Firebase Hosting)

URL  
https://worshipflow-df2ce.web.app

Deploy version  
wf-v1.0.0

---

# Issue 1 — LiveCue stuck on sync

## Symptom

Entering LiveCue shows:

LiveCue 상태 동기화 중...

The screen remains stuck and never resolves.

## Steps to reproduce

1. login
2. go to team
3. open project
4. click LiveCue tab

## Expected

LiveCue should show current cue state and setlist.

## Actual

UI remains stuck on "LiveCue 상태 동기화 중..."

## Suspected causes

Possible Firestore read issues:

teams/{teamId}/projects/{projectId}/liveCue/state

Possible problems:

- missing document
- listener attach timing
- snapshot fallback not handled
- loading state never exits

---

# Issue 2 — Sheet exists in library but not visible in project

## Symptom

Song appears in Library:

주의 집에 거하는 자

But when the song is added to project setlist:

Sheet is not displayed.

## Steps

1. register song
2. upload sheet
3. confirm sheet exists in Library
4. add song to project
5. sheet does not render

## Expected

Project setlist should display linked sheet.

## Actual

Library shows sheet file  
Project does not resolve sheet.

## Suspected causes

Possible reference mismatch:

library collection
vs
project setlist reference

Possible issues:

- incorrect songId reference
- storage path mismatch
- file metadata not propagated
- project setlist schema mismatch

---

# Status

Deploy succeeded.

Core flows working:

- login
- team
- project
- library
- song registration

But runtime issues detected in:

- LiveCue state sync
- sheet resolution in project