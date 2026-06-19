# Tests — local_objectfs_cdn

`client_test.php` validates the CDN Method-A signer:
- pure signing math (`methoda_authkey`, `normalize_filename`) + edge cases;
- the real `generate_presigned_url()` path (constructor bypassed via reflection,
  so no AWS SDK / network needed) — URL shape, expiry, custom params, throws-on-misconfig;
- an **API-drift guard** (`test_class_wiring_against_objectfs`) that fails loudly if
  a future ObjectFS upgrade renames/privatizes the methods we subclass.

## Running

Tests run via a throwaway **test image** (Moodle/Iomad 4.5 + `tool_objectfs` +
`local_aws` + composer dev deps) plus an ephemeral Postgres. From the repo root:

```bash
bash scripts/test.sh            # Moodle 4.5 (default)
bash scripts/test.sh iomad      # Iomad 4.5 (IOMAD_405_STABLE)
```

That builds the image (`scripts/Dockerfile.test`), starts Postgres, runs Moodle's
`admin/tool/phpunit/cli/init.php` (a full install of core + all plugins, which
doubles as the registration smoke test), then `vendor/bin/phpunit -c local/objectfs_cdn`,
and tears everything down. Exit code is non-zero on any failure.

> The test database (`$CFG->phpunit_*`) is separate and ephemeral — it never
> touches a production database.
