#!/usr/bin/env bash
# Puts the ESS behind its own nginx server block on the Scheduler's server
# (ADR-0019). Run on the server by .github/workflows/deploy-ess.yml, after
# the ESS process is up:
#
#   ESS_HOST=team-api.example.org ESS_PORT=3740 bash apps/ess-api/deploy/configure-nginx.sh
#
# ESS_PORT is the port pm2 gives the ESS (apps/ess-api/ecosystem.config.cjs),
# which the deploy reads from that file, so the port is set in one place.
#
# nginx is shared with the Scheduler, and the Scheduler's deploy stops when
# `nginx -t` fails for any site. So a broken file from here would block the
# Scheduler's deploys. That is why every change is tested before nginx is
# reloaded, and the last good file is put back when a test fails.
#
# Only these paths are ever written:
#   /etc/nginx/sites-available/team-rvm and its link in sites-enabled
#   /var/www/team-rvm-acme (certbot's challenge directory)
#   the certbot lineage named after ESS_HOST
#   ~/.team-rvm (the last good copy of the file)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF=/etc/nginx/sites-available/team-rvm
LINK=/etc/nginx/sites-enabled/team-rvm
ACME_ROOT=/var/www/team-rvm-acme
STATE_DIR="$HOME/.team-rvm"
LAST_GOOD="$STATE_DIR/nginx-team-rvm.last-good.conf"

ESS_HOST="${ESS_HOST:-}"
ESS_HOST="$(printf '%s' "$ESS_HOST" | tr '[:upper:]' '[:lower:]')"
ESS_PORT="${ESS_PORT:-}"

# Both values go into the nginx file, and the host name into a certbot command
# too, so the WHOLE value must match: grep would pass a value with a line break
# if any one of its lines matched.

# The port: digits only, and never the Scheduler's 3000.
if ! [[ $ESS_PORT =~ ^[1-9][0-9]{3,4}$ ]] || [ "$ESS_PORT" -gt 65535 ] || [ "$ESS_PORT" = 3000 ]; then
  echo "::error::ESS_PORT '${ESS_PORT}' is not a usable port (1000 to 65535, and not the Scheduler's 3000)."
  exit 1
fi

# The host: a plain host name.
if ! [[ $ESS_HOST =~ ^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$ ]]; then
  echo "::error::ESS_HOST '${ESS_HOST}' is not a host name. Set the repository variable ESS_HOST, for example team-api.rvmcad.org."
  exit 1
fi

# The Scheduler's own host names are never served from here.
case "$ESS_HOST" in
  scheduler.rvmcad.org|student.rvmcad.org)
    echo "::error::ESS_HOST is ${ESS_HOST}, which belongs to the Scheduler. The ESS needs a host name of its own (ADR-0019)."
    exit 1 ;;
esac
for f in /etc/nginx/sites-enabled/*; do
  [ -e "$f" ] || continue
  [ "$(basename "$f")" = "team-rvm" ] && continue
  # Every name in every server_name line, one per line, compared exactly.
  if grep -Eos 'server_name[^;]*;' "$f" | tr ';' ' ' | tr -s '[:space:]' '\n' | grep -Fxq "$ESS_HOST"; then
    echo "::error::${ESS_HOST} is already served by $(basename "$f"). Pick another host name for the ESS."
    exit 1
  fi
done

mkdir -p "$STATE_DIR"
sudo mkdir -p "$ACME_ROOT"

# Writes one stage of the file, tests the whole server, and reloads nginx only
# when the test passes. On a failed test the last good file goes back, or the
# link is removed when there is none, so the server is as it was before.
#
# The files read with `<` belong to the deploy user; only tee's write needs root.
# shellcheck disable=SC2024
install_conf() {
  local template="$1" rendered
  rendered="$(mktemp)"
  sed -e "s/__ESS_HOST__/${ESS_HOST}/g" -e "s/__ESS_PORT__/${ESS_PORT}/g" "$template" > "$rendered"
  sudo tee "$CONF" > /dev/null < "$rendered"
  sudo ln -sf "$CONF" "$LINK"
  if sudo nginx -t; then
    sudo systemctl reload nginx
    cp "$rendered" "$LAST_GOOD"
    rm -f "$rendered"
    return 0
  fi
  rm -f "$rendered"
  echo "::error::nginx -t failed with the new team-rvm file. Putting the last good one back."
  if [ -f "$LAST_GOOD" ]; then
    sudo tee "$CONF" > /dev/null < "$LAST_GOOD"
  else
    sudo rm -f "$LINK"
  fi
  if ! sudo nginx -t; then
    # Still failing without our change, so another site's file is broken.
    # Switch ours off too, so nothing from here stands in the way of a fix.
    echo "::error::nginx -t still fails, so another site's file is broken. The team-rvm file is switched off."
    sudo rm -f "$LINK"
    sudo nginx -t || true
  fi
  return 1
}

cert="/etc/letsencrypt/live/${ESS_HOST}/fullchain.pem"

if ! sudo test -f "$cert"; then
  echo "No certificate for ${ESS_HOST} yet. Serving the HTTP set-up page so certbot can issue one."
  install_conf "$HERE/nginx/team-rvm.http.conf"

  if getent hosts "$ESS_HOST" > /dev/null; then
    echo "  ${ESS_HOST} resolves to: $(getent hosts "$ESS_HOST" | awk '{print $1}' | sort -u | tr '\n' ' ')"
  else
    echo "::warning::${ESS_HOST} does not resolve yet. Add its DNS record (an A record for this server) and deploy again."
  fi

  # --cert-name pins the lineage to the path the HTTPS file reads. Without it,
  # a lineage that already holds this name under another name would answer
  # "not due for renewal" and the file nginx expects would never appear.
  if ! sudo certbot certonly --webroot -w "$ACME_ROOT" \
      -d "$ESS_HOST" --cert-name "$ESS_HOST" \
      --non-interactive --agree-tos \
      --deploy-hook "systemctl reload nginx"; then
    # Not fatal: the ESS process is running, and the next deploy tries again.
    echo "::warning::certbot could not issue a certificate for ${ESS_HOST}. The host keeps the HTTP set-up page until a later deploy succeeds."
    exit 0
  fi
fi

install_conf "$HERE/nginx/team-rvm.https.conf"
echo "nginx: ${ESS_HOST} now serves the ESS over HTTPS."
