# Changelog

## 1.0.0 — 2026-06-19

First public release.

Previously developed in-tree as `local_objectfs_cdntoken` (staging only, never
production). Extracted into this standalone repository and renamed to the
method-neutral component `local_objectfs_cdn` so it can grow beyond Method-A token
auth.

- Method-A token-auth signed-URL delivery for ObjectFS (Huawei / Alibaba / Tencent
  -style CDNs), provider-neutral; the object-storage bucket stays private.
- Subclasses `tool_objectfs` (no fork): overrides `generate_presigned_url()` and
  `initialise_external_client()` only. Includes an ObjectFS **API-drift guard** test.
- Configurable `sha256`/`md5` signing algorithm; admin-page client shim so ObjectFS
  test/check pages resolve the client class.
- GPLv3 `LICENSE`, self-contained Docker test harness (`scripts/test.sh` — Moodle 4.5
  **and** Iomad 4.5), and GitHub Actions CI (`moodle-plugin-ci`: phplint + phpunit).

> Migrating a `local_objectfs_cdntoken` install (e.g. staging)? See
> "Upgrading from local_objectfs_cdntoken" in the README.
