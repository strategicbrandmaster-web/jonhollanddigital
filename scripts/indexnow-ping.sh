#!/usr/bin/env bash
# Submit every URL in the live sitemap to IndexNow (Bing, Yandex, Seznam, Naver, etc.).
# The key is public by design; it's served at https://jonhollanddigital.com/7bc7ceaca6984f11ff59c8bb4b0df809.txt
# Usage: scripts/indexnow-ping.sh            # ping
#        DRY_RUN=1 scripts/indexnow-ping.sh  # print the payload only
set -euo pipefail

HOST="${INDEXNOW_HOST:-jonhollanddigital.com}"
KEY="${INDEXNOW_KEY:-7bc7ceaca6984f11ff59c8bb4b0df809}"
SITE="${INDEXNOW_SITE:-https://${HOST}}"
KEY_LOCATION="https://${HOST}/${KEY}.txt"
KEY_CHECK_URL="${SITE}/${KEY}.txt"
ENDPOINT="https://api.indexnow.org/indexnow"

# Make sure the key file is live and correct; IndexNow rejects pings otherwise.
served="$(curl -fsS --retry 3 --retry-delay 5 "${KEY_CHECK_URL}")"
if [ "${served}" != "${KEY}" ]; then
  echo "Key file at ${KEY_LOCATION} doesn't match the key; not pinging." >&2
  exit 1
fi

# Pull <loc> URLs from the live sitemap.
urls="$(curl -fsS --retry 3 --retry-delay 5 "${SITE}/sitemap.xml" | grep -o '<loc>[^<]*</loc>' | sed -e 's#<loc>##' -e 's#</loc>##')"
if [ -z "${urls}" ]; then
  echo "No URLs found in ${SITE}/sitemap.xml; not pinging." >&2
  exit 1
fi

payload="$(printf '%s\n' "${urls}" | python3 -c '
import json, sys
host, key, loc = sys.argv[1:4]
urls = [u.strip() for u in sys.stdin if u.strip()]
print(json.dumps({"host": host, "key": key, "keyLocation": loc, "urlList": urls}))
' "${HOST}" "${KEY}" "${KEY_LOCATION}")"

echo "${payload}"
if [ "${DRY_RUN:-0}" = "1" ]; then
  echo "DRY_RUN=1, not sending."
  exit 0
fi

code="$(curl -sS -o /tmp/indexnow-response.txt -w '%{http_code}' -X POST "${ENDPOINT}" \
  -H 'Content-Type: application/json; charset=utf-8' --data "${payload}")"
echo "IndexNow responded HTTP ${code}"
cat /tmp/indexnow-response.txt 2>/dev/null || true
# 200 = OK, 202 = accepted (key validation pending). Anything else is a failure.
case "${code}" in 200|202) exit 0 ;; *) exit 1 ;; esac
