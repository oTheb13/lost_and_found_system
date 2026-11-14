#!/usr/bin/env bash
# Usage: ./db/build.sh            (user root, no password)
#        DB_USER=me DB_PASS=secret ./db/build.sh
set -e
cd "$(dirname "$0")"
for f in 0*.sql; do
  echo "Running $f"
  if [ -n "$DB_PASS" ]; then mysql -u"${DB_USER:-root}" -p"$DB_PASS" < "$f"
  else mysql -u"${DB_USER:-root}" < "$f"; fi
done
echo "Done: database 'lfms' rebuilt."
