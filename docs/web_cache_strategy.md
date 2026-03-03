# Web Cache / Service Worker Strategy

## Goal
Define stable caching behavior for Flutter Web while avoiding stale bundle issues.

## Current Issue
- Aggressive cache can serve stale JS/assets after deploy.
- Full disable reduces stale risk but sacrifices offline/PWA benefits.

## Options

### Option A: Disable service worker (current conservative mode)
- Pros: lowest stale-asset risk
- Cons: no offline/PWA, higher repeated load cost

### Option B: Keep service worker with strict cache busting
- Pros: retains PWA/offline benefits
- Cons: requires robust versioning and cache invalidation checks

### Option C: Hybrid
- Keep service worker only for static shell, force network-first for app bundle
- Pros: partial PWA value with lower stale risk
- Cons: extra implementation complexity

## Decision Process
1. Measure deploy-related stale incidents for 2 release cycles.
2. If stale incidents remain low with improved build/version policy, evaluate Option C.
3. Promote to Option B only after deterministic invalidation is proven.

## Operational Checks
- Verify new build hash is served after release.
- Validate hard refresh and normal refresh behavior.
- Validate at least two browsers (Safari + Chrome).

## Status
- Default for now: Option A (safe baseline)
- Re-evaluation owner: release maintainer
- Re-evaluation cadence: every 2 production releases
