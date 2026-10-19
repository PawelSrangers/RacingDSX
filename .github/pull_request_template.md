<!--
Implementation PR template (default).
Spec changes MUST NOT go here — use .github/PULL_REQUEST_TEMPLATE/spec-change.md
(`gh pr create --template spec-change.md`).
Delete comment blocks before submitting. Sections marked (optional) may be removed if empty.
-->

## Summary

<!-- 1–3 sentences: what this PR does and why. No marketing. -->

## Spec traceability

- Spec: <!-- specs/<feature>.md, or "none — not a behavior change" -->
- Requirements implemented: <!-- REQ-<FEATURE>-001, REQ-<FEATURE>-002 -->
- Requirements partially implemented / deferred: <!-- IDs + reason, or "none" -->

## Type of change

- [ ] Feature (implements spec requirements)
- [ ] Bug fix (code did not match spec)
- [ ] Refactoring (no behavior change)
- [ ] Infrastructure / tooling / CI
- [ ] Documentation
- [ ] Other: <!-- describe -->

## Changes

<!-- Bullet list of meaningful changes. Group by component if large. -->

-

## Architecture

- ADRs affected: <!-- NNNN, or "none" -->
- New ADR in this PR: <!-- NNNN, or "none" -->
- Conflicts with accepted ADRs: <!-- list, or "none" -->

## Testing

<!-- How this was verified. Name the tests and which REQ IDs they cover. -->

- [ ] Automated tests added/updated
- [ ] Tests pass locally
- [ ] Manually verified: <!-- how, or remove -->

## Risks and rollback

<!-- What can break, blast radius, how to roll back. "Low risk" without reasoning is not an answer. -->

## Security and secrets

- [ ] No secrets, tokens, or credentials in code, config, logs, or tests
- [ ] New secrets added only as `op://` references in `config/*.tpl`
- [ ] No new external data exposure (or described above)

## Checklist

- [ ] PR does **not** modify files in `specs/`
- [ ] No behavior beyond what the spec requires (no scope creep)
- [ ] Spec ambiguities found during implementation were raised, not silently resolved
- [ ] PR is small enough to review in one sitting; otherwise split
- [ ] Self-reviewed the diff

## Open questions (optional)

<!-- Anything the reviewer must decide. -->
