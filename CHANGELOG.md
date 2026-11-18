# Changelog

Semantic versions. Every release lists its sandbox test result.

## 0.1.0 (2026-11-18)
- First release: Your AWS bill as a table: a daily CUR 2.0 export to an encrypted bucket, an Athena table over it with no crawler to pay for, a 1 GB-per-query cap and four saved queries.
- Sandbox test: **passed 2026-11-18** (AWS ap-south-1: apply, re-plan with no changes, destroy, nothing left).
