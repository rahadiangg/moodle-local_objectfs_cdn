# local_objectfs_cdn — CDN signed-URL delivery for ObjectFS

A small, **provider-neutral** Moodle **local plugin** that makes [Catalyst
ObjectFS](https://github.com/catalyst/moodle-tool_objectfs) deliver files through a
**CDN** that signs URLs with a token the edge validates ("Method A" token
authentication), while the object-storage bucket stays **private**.

It does **not** fork or modify ObjectFS. It subclasses two ObjectFS classes and
overrides **one** method; everything else (upload, verify, streaming, presigned
gating) is inherited unchanged. ObjectFS is installed vanilla alongside it.

- **Component:** `local_objectfs_cdn`
- **Requires:** Moodle 4.5 LTS, and `tool_objectfs` (hard dependency, installed separately)
- **License:** GPL-3.0-or-later
- Works on stock **Moodle 4.5** and the **Iomad 4.5** distribution.

> Renaming note: this plugin was previously `local_objectfs_cdntoken`. If you ran
> that version, see [Upgrading from local_objectfs_cdntoken](#upgrading-from-local_objectfs_cdntoken).

## Why this exists

Moodle gates every file behind a capability check in `pluginfile.php`. ObjectFS can
offload the *bytes* to S3-compatible storage and **redirect** the browser to a
time-limited **presigned URL** so files don't stream through PHP. That works — but a
presigned URL is **unique per request** (signature + expiry in the query string), so
a CDN in front of it gets a distinct cache key for every user → ~100% cache miss → no
edge caching and no origin-egress savings. Telling the CDN to ignore the signature for
the cache key would serve the object to **anyone** with the path → access control
broken.

**The fix:** sign the redirect with the **CDN's own token authentication** (Method A:
`auth_key=timestamp-rand-uid-hash`). The CDN validates the token at the edge, and its
cache key is configured to **ignore `auth_key`** — so per-user URLs share one cached
object (real offload) while expiry + tamper-protection stay enforced at the edge, and
the bucket stays private (the CDN pulls via origin auth). ObjectFS's only built-in
"custom delivery domain" is **CloudFront** (AWS-specific RSA signing); this plugin
fills the gap for Huawei / Alibaba / Tencent-style token-auth CDNs.

## How it works

```
user ──GET pluginfile.php/...──▶ Moodle web node
                                  │  capability check (enrolled? allowed?)   ← access control here
                                  │  302 Location: https://<cdn>/<key>?auth_key=ts-rand-uid-HASH
                                  ▼
user ──follows 302───────────▶ CDN edge
                                  │  validate auth_key (HASH + not expired) → 403 if bad
                                  │  cache HIT?  → serve from edge
                                  │  cache MISS? → pull from PRIVATE bucket via origin auth
                                  ▼
                               object storage (private)
```

**Method A format:**

```
auth_key = "<ts>-<rand>-<uid>-" + HASH("<uri>-<ts>-<rand>-<uid>-<key>")   # HASH = sha256 (default) or md5
URL      = "<scheme>://<cdn-domain><uri>?<authParam>=<auth_key>"
```

where `<uri>` is the object key path (`/<key_prefix><aa>/<bb>/<sha1>`) and `<key>` is
the shared signing key configured on both Moodle and the CDN.

The plugin subclasses `\tool_objectfs\s3_file_system` (swapping in its own client via
`initialise_external_client()`) and `\tool_objectfs\local\store\s3\client` (overriding
`generate_presigned_url()` to emit the CDN URL). On any misconfiguration the signer
throws; ObjectFS catches it and falls back to streaming the file through PHP —
downloads degrade, they don't hard-fail.

## Which CDNs does it work with?

| CDN | Supported | Notes |
|---|---|---|
| **Huawei Cloud CDN** | ✅ | Signing Method A. Built and tested against this. |
| **Alibaba Cloud CDN** | ✅ | "URL authentication Type A" — identical algorithm. |
| **Tencent Cloud CDN** & other A-type schemes | ⚠️ likely | Verify the **param name** (set via `authparam`) and that the hash field order is `uri-ts-rand-uid-key`. If a provider orders fields differently, add a method (see [Extending](#extending-to-another-cdn-scheme)). |
| **AWS CloudFront** | ❌ use ObjectFS `cf` | CloudFront uses RSA key-pair signing — ObjectFS supports it natively via `signingmethod=cf`. Don't use this plugin for CloudFront. |
| **BunnyCDN / Cloudflare / Akamai / Fastly** | ❌ not yet | Each has its own token scheme (different inputs / HMAC). Add a method to support. |

So: **provider-neutral within the Method-A token-auth family**, not Huawei-specific.

## Installation

### Prerequisite: install ObjectFS first

This plugin is a **companion to ObjectFS, not a bundle**. A Moodle plugin cannot
contain another plugin, so install both:

1. Install **[`tool_objectfs`](https://github.com/catalyst/moodle-tool_objectfs)**
   (branch `MOODLE_404_STABLE`) and its AWS SDK dependency
   **[`local_aws`](https://github.com/catalyst/moodle-local_aws)**, with an
   S3-compatible bucket configured.
2. Then install this plugin. Moodle's installer will **block** it with a
   "missing dependency: tool_objectfs" error if ObjectFS isn't present first.

### Install this plugin

Any standard method works:

- **Copy the folder** into `local/objectfs_cdn/` of your Moodle/Iomad tree, then
  visit *Site administration → Notifications* to run the upgrade.
- **Git:** `git clone https://github.com/rahadiangg/moodle-local_objectfs_cdn.git local/objectfs_cdn`
- **Bake into a container image** (recommended for Kubernetes — a dashboard ZIP
  upload writes to one ephemeral pod and is lost on restart): `git clone` it into
  `local/objectfs_cdn/` at image build time, pinned to a release tag.

## Configuration — three layers

### Layer 1 — Configure ObjectFS (the prerequisite)

*Site administration → Plugins → Admin tools → Object storage file system.* Set the
bucket (`s3_key`, `s3_secret`, `s3_bucket`, `s3_region`, `s3_base_url`) and **enable
presigned redirects** (`enablepresignedurls = 1`). This plugin rides on that redirect
path. Keep the bucket **private**.

### Layer 2 — Configure this plugin

*Site administration → Plugins → Local plugins → ObjectFS CDN signed URLs*
(component `local_objectfs_cdn`):

| Setting | Meaning |
|---|---|
| `enabled` | master on/off |
| `cdndomain` | CDN/acceleration domain host, e.g. `cdn.example.com` |
| `cdnscheme` | `https` (default) or `http` |
| `signingmethod` | `tokenA` (only option today) |
| `algorithm` | `sha256` (recommended) or `md5` — must match the CDN's "Encryption Algorithm" |
| `signingkey` | shared secret, identical to the CDN's token-auth key |
| `authparam` | query-param name the CDN expects (default `auth_key`) |
| `validity` | seconds; **must equal** the CDN-configured validity window |
| `uid` | Method-A uid field (usually `0`) |

### Layer 3 — Activate it

Point Moodle's file system at this plugin's class in **`config.php`** (the standard
ObjectFS activation pattern, with this plugin's class instead of the stock one):

```php
// in config.php, above the lib/setup.php require:
$CFG->alternative_file_system_class = '\local_objectfs_cdn\file_system';
```

Make sure ObjectFS presigned redirects are enabled (Layer 1). That's the only
non-UI step.

> Deploying with Kubernetes/Helm? A deployment project can drive all three layers
> from values instead of clicking — but that lives in your infra repo, not here.

## CDN-side requirements (any provider; Huawei shown)

On your acceleration domain:

1. **Origin** = the same object-storage bucket ObjectFS writes to. Enable origin
   pull authentication (e.g. Huawei "OBS Pull Authentication") so the CDN can read
   the **private** bucket; keep the bucket private.
2. **HTTPS** — bind a certificate and force HTTPS (recommended).
3. **Token Authentication → Signing Method A:**
   - **Signing key** — identical to the plugin's `signingkey` (Huawei: 6–32 chars,
     letters and digits only).
   - **Encryption algorithm** — SHA256 (recommended) or MD5; **must match**
     `algorithm` exactly, or every request 403s.
   - **Authentication parameter** = matches `authparam` (default `auth_key`).
   - **Validity period** — **must equal** `validity`.
   - **Time format** = Decimal.
4. **Cache → URL parameter filtering** = **ignore** the `auth_key` parameter. This is
   the single most important setting — without it the cache is defeated.
5. **Cache TTL** — long (e.g. 30 days); content-hash objects are immutable.

> Config changes propagate to edge PoPs over ~1 minute.

## Verify

**Plumbing, no Moodle (hand-signed `curl`):**

```bash
DOMAIN=cdn.example.com; URI=/<aa>/<bb>/<sha1>; KEY=<signing-key>; TS=$(date +%s)
HASH=$(printf '%s' "$URI-$TS-0-0-$KEY" | shasum -a 256 | awk '{print $1}')   # md5: openssl md5 -r
curl -sS -D- -o /dev/null "https://$DOMAIN$URI?auth_key=$TS-0-0-$HASH"
#  expect: 200 (and a cache miss→hit on a second request);
#  expired/tampered/no-token -> 403 ;  Range (curl -r 0-9) -> 206
```

**Deployed plugin:** confirm the active filesystem class:

```bash
cd /path/to/moodle && php admin/cli/cfg.php --component=tool_objectfs --name=filesystem
#  or via moosh: moosh -n config-get tool_objectfs filesystem
#  expect: \local_objectfs_cdn\file_system
```

## Requirements & limitations

- Requires `tool_objectfs` (hard dependency) with an S3-compatible store, plus its
  `local_aws` SDK dependency.
- Pinned to ObjectFS branch **`MOODLE_404_STABLE`** (Moodle 4.5) — the subclass relies
  on `s3\client::generate_presigned_url()` (public) and
  `object_file_system::initialise_external_client()` (protected). The PHPUnit suite
  includes an **API-drift guard** (`test_class_wiring_against_objectfs`) that fails
  loudly if a future ObjectFS release changes these signatures.
- Under token auth there is no per-request `Content-Disposition` override, so downloads
  are named by their content hash unless the stored object carries a
  `Content-Disposition` (set at upload time on the bucket).
- On any misconfiguration the signer throws; ObjectFS falls back to streaming the file
  through PHP — downloads degrade, they don't break.

## Extending to another CDN scheme

The signing math is isolated, so adding a provider is small and needs **no fork**:

1. Add an option to the `signingmethod` select in `settings.php`
   (e.g. `'bunnytoken' => 'BunnyCDN token'`).
2. Add a static helper next to `methoda_authkey()` in `classes/client.php`.
3. Branch on the method in `generate_presigned_url()`.
4. Add an edge-case test mirroring `tests/client_test.php`.

## Tests

The suite covers the pure signing math, the real `generate_presigned_url()` path
(constructor bypassed via reflection — no AWS SDK/network), and the ObjectFS
API-drift guard. See [`tests/README.md`](tests/README.md).

Run the full suite in a throwaway Docker image + ephemeral Postgres (from the repo
root) — against **Moodle 4.5** and **Iomad 4.5**:

```bash
bash scripts/test.sh            # Moodle 4.5 (default)
bash scripts/test.sh iomad      # Iomad 4.5 (IOMAD_405_STABLE)
bash scripts/test.sh moodle --filter test_methoda_authkey   # pass phpunit args
```

CI (GitHub Actions, `moodle-plugin-ci`) runs phplint + phpunit on Moodle 4.5 with
`tool_objectfs` + `local_aws` added as dependencies.

## Upgrading from local_objectfs_cdntoken

The component was renamed `local_objectfs_cdntoken` → `local_objectfs_cdn`. Moodle
treats this as a **new** plugin (the component string is its identity), so after
switching:

- Re-enter this plugin's settings under the new component, and re-point activation to
  `\local_objectfs_cdn\file_system` (config.php and ObjectFS's `filesystem` setting).
- The old `local_objectfs_cdntoken` plugin shows as "missing from disk" in the admin
  plugin overview once its code is gone — uninstall it there to clear the orphaned
  config rows. File serving is unaffected (the new class takes over).
- A clean re-install (no prior `cdntoken` data) needs none of this.

## License

GPL-3.0-or-later — see [LICENSE](LICENSE). Matches Moodle core.
