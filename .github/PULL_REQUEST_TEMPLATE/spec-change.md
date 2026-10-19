<!--
Spec change PR template.
Use: `gh pr create --template spec-change.md`
     or append `?template=spec-change.md` to the GitHub compare URL.
This PR contains ONLY changes under specs/. No code, no tests.
Delete comment blocks before submitting.
-->

## Summary

<!-- What changes in the spec, in 1–3 sentences. -->

## Motivation

<!-- Why the current spec is wrong, incomplete, or outdated.
     Be concrete: what was discovered, by whom, in which PR/issue/conversation. -->

- Triggered by: <!-- PR #, issue #, user request, implementation finding -->

## Change classification

- [ ] New spec (Draft → Approved)
- [ ] New requirement(s) added
- [ ] Existing requirement changed — **breaking** (implemented behavior must change)
- [ ] Existing requirement changed — non-breaking (clarification, no behavior change)
- [ ] Requirement removed (marked `Removed`, ID not reused)
- [ ] Editorial only (typos, formatting)

## Requirements diff

<!-- One row per touched requirement. -->

| ID | Change | Before | After |
|----|--------|--------|-------|
| REQ-<FEATURE>-001 | added / changed / removed | | |

## Impact analysis

- Implemented code affected: <!-- modules/files, or "none — not yet implemented" -->
- Tests that will need to change: <!-- list, or "none" -->
- Other specs affected: <!-- list, or "none" -->
- ADRs affected / contradicted: <!-- NNNN, or "none". If an ADR must change, that is a separate ADR PR. -->
- Blocked implementation PRs: <!-- PRs waiting on this, or "none" -->

## Alternatives considered

<!-- What else could have been changed instead, and why not. "None" requires justification. -->

## Checklist

- [ ] PR touches **only** files under `specs/`
- [ ] Every new/changed requirement has a stable ID and testable acceptance criteria
- [ ] No requirement IDs reused or renumbered
- [ ] Removed requirements are marked `Removed`, not deleted
- [ ] Spec `Changelog` section updated
- [ ] Spec `Status` is correct
- [ ] Out-of-scope section still accurate
- [ ] No implementation details leaked into the spec (the spec says *what*, not *how*)

## Approval

<!-- Single-maintainer project: the owner's merge is the approval. Agents never merge. -->

- [ ] Owner has read the full requirements diff and impact analysis before merging
