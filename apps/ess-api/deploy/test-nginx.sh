#!/usr/bin/env bash
# Runs configure-nginx.sh against a real nginx in a throwaway container, with
# sudo, systemctl and certbot stubbed, through every scenario the deploy can
# meet: a fresh server, a re-run, certbot failing, a broken file of ours, a
# broken file of another site's, and host names that must be refused.
#
# CI runs it (.github/workflows/ci.yml). To run it locally, from the repository root:
#   docker run --rm -v "$PWD:/work:ro" nginx:1.24-alpine sh -c \
#     "apk add --no-cache bash openssl curl > /dev/null && bash /work/apps/ess-api/deploy/test-nginx.sh"
#
# Never run it on a real server: it rewrites the container's nginx set-up.
set -uo pipefail

if [ ! -f /.dockerenv ] && [ -z "${ALLOW_NGINX_TEST:-}" ]; then
  echo "This rewrites nginx's configuration. Run it only inside a throwaway container."
  exit 2
fi

# Work on a copy, so the scenarios that break a template never touch the checkout.
rm -rf /tmp/deploy && cp -r "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" /tmp/deploy
SRC=/tmp/deploy
FAILS=0
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; FAILS=$((FAILS + 1)); }

mkdir -p /stubs
cat > /stubs/sudo <<'EOF'
#!/bin/sh
exec "$@"
EOF
cat > /stubs/systemctl <<'EOF'
#!/bin/sh
# systemctl reload nginx -> nginx -s reload
[ "$1" = "reload" ] && [ "$2" = "nginx" ] && exec nginx -s reload
echo "systemctl stub: unexpected $*" >&2; exit 1
EOF
cat > /stubs/certbot <<'EOF'
#!/bin/sh
# Records its arguments, then issues a self-signed lineage unless told to fail.
echo "$*" >> /tmp/certbot.calls
[ -n "${FAIL_CERTBOT:-}" ] && { echo "certbot stub: failing on purpose" >&2; exit 1; }
name=""; prev=""
for a in "$@"; do [ "$prev" = "--cert-name" ] && name="$a"; prev="$a"; done
mkdir -p "/etc/letsencrypt/live/$name"
openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj "/CN=$name" \
  -keyout "/etc/letsencrypt/live/$name/privkey.pem" \
  -out "/etc/letsencrypt/live/$name/fullchain.pem" 2>/dev/null
EOF
cat > /stubs/getent <<'EOF'
#!/bin/sh
[ "$1" = "hosts" ] && [ "$2" = "team-api.example.org" ] && { echo "203.0.113.10 $2"; exit 0; }
exit 2
EOF
chmod +x /stubs/*
export PATH="/stubs:$PATH"

# The server's layout: sites-enabled included from nginx.conf, and the
# Scheduler's own site already there.
mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled /etc/letsencrypt
rm -f /etc/nginx/conf.d/default.conf
sed -i 's#include /etc/nginx/conf.d/\*.conf;#include /etc/nginx/conf.d/*.conf;\n    include /etc/nginx/sites-enabled/*;#' /etc/nginx/nginx.conf
cat > /etc/nginx/sites-available/scheduler <<'EOF'
server {
    listen 80;
    server_name scheduler.rvmcad.org;
    location / { return 200 "scheduler"; }
}
EOF
ln -sf /etc/nginx/sites-available/scheduler /etc/nginx/sites-enabled/scheduler
cat > /etc/letsencrypt/options-ssl-nginx.conf <<'EOF'
ssl_session_cache shared:le_nginx_SSL:10m;
ssl_session_timeout 1440m;
ssl_protocols TLSv1.2 TLSv1.3;
ssl_prefer_server_ciphers off;
EOF
openssl dhparam -dsaparam -out /etc/letsencrypt/ssl-dhparams.pem 2048 2>/dev/null
nginx -t 2>/dev/null || { echo "baseline nginx config is broken"; exit 1; }
nginx

reset_state() {
  rm -rf /etc/letsencrypt/live /root/.team-rvm /var/www/team-rvm-acme /tmp/certbot.calls
  rm -f /etc/nginx/sites-available/team-rvm /etc/nginx/sites-enabled/team-rvm
}
# The ESS's port as the deploy passes it (from ecosystem.config.cjs), unless a
# scenario gives another.
PORT=3740
run() { ESS_HOST="$1" ESS_PORT="${2-$PORT}" bash "$SRC/configure-nginx.sh" > /tmp/out.txt 2>&1; echo $?; }

# A stand-in for the ESS on its port: it echoes the path, the forwarded-for
# chain and the host it was given, so the proxy settings can be checked.
cat > /etc/nginx/conf.d/stand-in-ess.conf <<EOF
server {
    listen 127.0.0.1:${PORT};
    location /api/ess/ {
        default_type application/json;
        return 200 '{"path":"\$request_uri","xff":"\$http_x_forwarded_for","host":"\$http_host"}';
    }
}
EOF
nginx -s reload

# 1. Fresh server, certbot succeeds: ends on the HTTPS file, enabled, nginx valid.
reset_state
rc=$(run team-api.example.org)
if [ "$rc" = 0 ] && grep -q 'listen 443 ssl' /etc/nginx/sites-available/team-rvm \
   && [ -L /etc/nginx/sites-enabled/team-rvm ] && nginx -t 2>/dev/null \
   && grep -q -- '--cert-name team-api.example.org' /tmp/certbot.calls \
   && grep -q -- '-w /var/www/team-rvm-acme' /tmp/certbot.calls \
   && cmp -s /etc/nginx/sites-available/team-rvm /root/.team-rvm/nginx-team-rvm.last-good.conf \
   && grep -q "proxy_pass         http://127.0.0.1:${PORT};" /etc/nginx/sites-available/team-rvm \
   && ! grep -q '__ESS_' /etc/nginx/sites-available/team-rvm; then
  pass "fresh server: HTTP stage, certificate, then HTTPS on port ${PORT}"
else fail "fresh server (rc=$rc)"; cat /tmp/out.txt; fi

# Port 80 redirects, but still serves the challenge directory for renewals.
# On 443 the API path reaches the ESS unchanged, with nginx's own address as
# the last forwarded-for entry (the one the ESS trusts), and any other path
# gets the JSON 404. nginx -s reload returns before the old workers have gone,
# so give them a moment.
sleep 1
expect() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (got '$2')"; fi; }
H='Host: team-api.example.org'
R443='--resolve team-api.example.org:443:127.0.0.1'
expect "port 80 redirects to HTTPS" \
  "$(curl -s -o /dev/null -w '%{http_code}' -H "$H" http://127.0.0.1/api/ess/health)" 301
mkdir -p /var/www/team-rvm-acme/.well-known/acme-challenge
echo token-123 > /var/www/team-rvm-acme/.well-known/acme-challenge/probe
expect "challenge path served on port 80" \
  "$(curl -s -H "$H" http://127.0.0.1/.well-known/acme-challenge/probe)" token-123
# shellcheck disable=SC2086
expect "443 /api/ess/ reaches the ESS port with the path unchanged" \
  "$(curl -sk $R443 https://team-api.example.org/api/ess/health?x=1)" \
  '{"path":"/api/ess/health?x=1","xff":"127.0.0.1","host":"team-api.example.org"}'
# shellcheck disable=SC2086
expect "a forged X-Forwarded-For stays to the left of nginx's own entry" \
  "$(curl -sk $R443 -H 'X-Forwarded-For: 203.0.113.99' https://team-api.example.org/api/ess/me)" \
  '{"path":"/api/ess/me","xff":"203.0.113.99, 127.0.0.1","host":"team-api.example.org"}'
# shellcheck disable=SC2086
expect "443 other paths: JSON 404" \
  "$(curl -sk $R443 https://team-api.example.org/anything)" '{"error":"Not found","code":"NOT_FOUND"}'
expect "the Scheduler's site still answers" \
  "$(curl -s -H 'Host: scheduler.rvmcad.org' http://127.0.0.1/)" scheduler

# 2. Re-run with the certificate present: straight to HTTPS, certbot not called.
rm -f /tmp/certbot.calls
rc=$(run team-api.example.org)
if [ "$rc" = 0 ] && [ ! -f /tmp/certbot.calls ] && grep -q 'listen 443 ssl' /etc/nginx/sites-available/team-rvm; then
  pass "re-run: certificate kept, no certbot call"
else fail "re-run (rc=$rc)"; cat /tmp/out.txt; fi

# 3. Fresh server, certbot fails: HTTP set-up page stays, deploy not failed.
reset_state
rc=$(FAIL_CERTBOT=1 run team-api.example.org)
if [ "$rc" = 0 ] && grep -q 'return 503' /etc/nginx/sites-available/team-rvm \
   && ! grep -q 'listen 443' /etc/nginx/sites-available/team-rvm && nginx -t 2>/dev/null \
   && grep -q 'certbot could not issue' /tmp/out.txt; then
  pass "certbot failure: HTTP stage kept, exit 0 with a warning"
else fail "certbot failure (rc=$rc)"; cat /tmp/out.txt; fi

# 4. A broken HTTPS template: test fails, last good file restored, nginx still valid.
reset_state
run team-api.example.org > /dev/null
good=$(cat /etc/nginx/sites-available/team-rvm)
cp "$SRC/nginx/team-rvm.https.conf" /tmp/https.orig
echo 'this is not nginx;' >> "$SRC/nginx/team-rvm.https.conf"
rc=$(run team-api.example.org)
cp /tmp/https.orig "$SRC/nginx/team-rvm.https.conf"
if [ "$rc" != 0 ] && [ "$(cat /etc/nginx/sites-available/team-rvm)" = "$good" ] \
   && [ -L /etc/nginx/sites-enabled/team-rvm ] && nginx -t 2>/dev/null; then
  pass "broken template: refused, last good file back, nginx valid"
else fail "broken template (rc=$rc)"; cat /tmp/out.txt; fi

# 5. Broken template on a fresh server (no last good file): link removed.
reset_state
mkdir -p /etc/letsencrypt/live/team-api.example.org
openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj "/CN=x" \
  -keyout /etc/letsencrypt/live/team-api.example.org/privkey.pem \
  -out /etc/letsencrypt/live/team-api.example.org/fullchain.pem 2>/dev/null
echo 'this is not nginx;' >> "$SRC/nginx/team-rvm.https.conf"
rc=$(run team-api.example.org)
cp /tmp/https.orig "$SRC/nginx/team-rvm.https.conf"
if [ "$rc" != 0 ] && [ ! -e /etc/nginx/sites-enabled/team-rvm ] && nginx -t 2>/dev/null; then
  pass "broken template, nothing to restore: link removed, nginx valid"
else fail "broken template without last good (rc=$rc)"; cat /tmp/out.txt; fi

# 6. Another site's file is broken: ours is switched off, exit non-zero.
reset_state
cp /etc/nginx/sites-available/scheduler /tmp/scheduler.orig
echo 'broken;' >> /etc/nginx/sites-available/scheduler
rc=$(run team-api.example.org)
cp /tmp/scheduler.orig /etc/nginx/sites-available/scheduler
if [ "$rc" != 0 ] && [ ! -e /etc/nginx/sites-enabled/team-rvm ] && grep -q "another site's file is broken" /tmp/out.txt; then
  pass "another site broken: ours switched off, deploy fails loudly"
else fail "another site broken (rc=$rc)"; cat /tmp/out.txt; fi
nginx -t 2>/dev/null || fail "baseline not restored after scenario 6"

# 7. Names refused before anything is written.
for bad in "" "not a host" "team-api.example.org;evil" "../etc" "scheduler.rvmcad.org" "STUDENT.rvmcad.org"; do
  reset_state
  rc=$(run "$bad")
  if [ "$rc" != 0 ] && [ ! -e /etc/nginx/sites-available/team-rvm ]; then
    pass "refused host name '$bad'"
  else fail "accepted host name '$bad' (rc=$rc)"; cat /tmp/out.txt; fi
done

# 8. A name another enabled site already serves is refused; a longer name
#    that merely ends with it is not.
cat > /etc/nginx/sites-available/other <<'EOF'
server {
    listen 80;
    server_name  shop.example.org   www.shop.example.org;
    location / { return 200 "other"; }
}
EOF
ln -sf /etc/nginx/sites-available/other /etc/nginx/sites-enabled/other
reset_state
rc=$(run www.shop.example.org)
if [ "$rc" != 0 ] && grep -q 'already served by other' /tmp/out.txt; then
  pass "name served by another site refused"
else fail "duplicate name accepted (rc=$rc)"; cat /tmp/out.txt; fi
reset_state
rc=$(FAIL_CERTBOT=1 run api.shop.example.org)
if [ "$rc" = 0 ]; then pass "similar but different name accepted"
else fail "similar name refused (rc=$rc)"; cat /tmp/out.txt; fi
rm -f /etc/nginx/sites-enabled/other /etc/nginx/sites-available/other

# 9. Ports refused before anything is written: empty, not digits, the
#    Scheduler's 3000, below 1000, above 65535, and an attempt to inject text.
for bad in "" "abc" "3000" "80" "70000" "3740;evil" "3740 x"; do
  reset_state
  rc=$(run team-api.example.org "$bad")
  if [ "$rc" != 0 ] && [ ! -e /etc/nginx/sites-available/team-rvm ]; then
    pass "refused port '$bad'"
  else fail "accepted port '$bad' (rc=$rc)"; cat /tmp/out.txt; fi
done

nginx -s quit 2>/dev/null
echo
[ "$FAILS" = 0 ] && echo "ALL SCENARIOS PASSED" || echo "$FAILS SCENARIO(S) FAILED"
exit "$FAILS"
