#!/usr/bin/env bash
# Run the local_objectfs_cdn PHPUnit suite against Moodle 4.5 or Iomad 4.5 in a
# throwaway Docker image + ephemeral Postgres. The test DB is separate and
# ephemeral; nothing touches a production database.
#
# Usage (from repo root):
#   bash scripts/test.sh                 # Moodle 4.5 (default)
#   bash scripts/test.sh moodle          # Moodle 4.5
#   bash scripts/test.sh iomad           # Iomad 4.5 (IOMAD_405_STABLE)
#   bash scripts/test.sh moodle --filter test_methoda_authkey   # pass phpunit args
#
# Override the Iomad source with IOMAD_REPO / IOMAD_BRANCH env vars.
set -euo pipefail
cd "$(dirname "$0")/.."

TARGET="${1:-moodle}"
[ $# -gt 0 ] && shift || true

IOMAD_REPO="${IOMAD_REPO:-https://github.com/iomad/iomad.git}"
IOMAD_BRANCH="${IOMAD_BRANCH:-IOMAD_405_STABLE}"

case "$TARGET" in
  moodle)
    IMAGE=ofcdn-test-moodle
    BUILD_ARGS=()
    ;;
  iomad)
    IMAGE=ofcdn-test-iomad
    BUILD_ARGS=(--build-arg "IOMAD_REPO=${IOMAD_REPO}" --build-arg "IOMAD_BRANCH=${IOMAD_BRANCH}")
    ;;
  *)
    echo "usage: $0 [moodle|iomad] [phpunit args...]" >&2
    exit 2
    ;;
esac

NET="ofcdn-test-net-${TARGET}"
PG="ofcdn-test-pg-${TARGET}"
WWW=/var/www/html

cleanup() {
  docker rm -f "$PG" >/dev/null 2>&1 || true
  docker network rm "$NET" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "==> [$TARGET] build test image"
docker build -f scripts/Dockerfile.test ${BUILD_ARGS[@]+"${BUILD_ARGS[@]}"} -t "$IMAGE" .

echo "==> [$TARGET] start ephemeral Postgres"
docker network create "$NET" >/dev/null
docker run -d --name "$PG" --network "$NET" \
  -e POSTGRES_USER=moodle -e POSTGRES_PASSWORD=moodle -e POSTGRES_DB=moodle_test \
  postgres:16-alpine >/dev/null

echo "==> [$TARGET] wait for Postgres"
for _ in $(seq 1 60); do
  docker exec "$PG" pg_isready -U moodle -d moodle_test >/dev/null 2>&1 && break
  sleep 1
done

# admin/tool/phpunit/cli/init.php performs a full schema install of Moodle/Iomad
# AND every installed plugin — including local_objectfs_cdn. A clean init is the
# registration/upgrade.php smoke test; PHPUnit then exercises the signer logic +
# the ObjectFS API-drift guard.
echo "==> [$TARGET] init test DB (installs core + all plugins incl. local_objectfs_cdn) + run PHPUnit"
docker run --rm --network "$NET" -e PGHOST="$PG" --entrypoint /bin/sh "$IMAGE" -euc '
cat > '"$WWW"'/config.php <<PHP
<?php  // Moodle/Iomad test configuration (ephemeral).
unset(\$CFG);
global \$CFG;
\$CFG = new stdClass();
\$CFG->dbtype    = "pgsql";
\$CFG->dblibrary = "native";
\$CFG->dbhost    = getenv("PGHOST");
\$CFG->dbname    = "moodle_test";
\$CFG->dbuser    = "moodle";
\$CFG->dbpass    = "moodle";
\$CFG->prefix    = "mdl_";
\$CFG->dboptions = ["dbpersist" => 0, "dbport" => 5432, "dbsocket" => ""];
\$CFG->wwwroot   = "http://localhost";
\$CFG->dataroot  = "/var/www/moodledata-test";
\$CFG->admin     = "admin";
\$CFG->directorypermissions = 02777;
\$CFG->phpunit_prefix   = "t_";
\$CFG->phpunit_dataroot = "/var/www/phpunit_dataroot";
require_once(__DIR__ . "/lib/setup.php");
PHP
mkdir -p /var/www/moodledata-test /var/www/phpunit_dataroot
chmod -R 0777 /var/www/moodledata-test /var/www/phpunit_dataroot
php '"$WWW"'/admin/tool/phpunit/cli/init.php
cd '"$WWW"'
vendor/bin/phpunit -c local/objectfs_cdn '"$*"'
'
echo "==> [$TARGET] PASSED"
