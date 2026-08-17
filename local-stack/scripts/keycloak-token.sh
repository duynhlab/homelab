#!/usr/bin/env bash
# Mint a Keycloak realm access token from the shell — headless Authorization
# Code + PKCE, no browser.
#
# WHY THIS EXISTS
# After the RFC-0024 P3 identity cutover the platform's tokens come from the
# `duynhlab` realm, and the realm's SPA clients have Direct Access Grants
# DISABLED (`directAccessGrantsEnabled: false` in keycloak/duynhlab-realm.json).
# So `curl -d grant_type=password` cannot mint a token, and the E2E audit's old
# "POST /auth/v1/public/auth/login" step no longer produces a token the edge
# will accept. This script replays the browser's flow with curl and a cookie
# jar instead: authorize -> login form -> redirect with ?code= -> token.
#
# The point is that the LOCAL REALM STAYS BYTE-IDENTICAL TO THE CLUSTER's. The
# alternative — a dev-only client with Direct Access Grants enabled — is three
# lines of realm JSON and would make token acquisition trivial, but it also
# makes local-stack stop proving that the real client works. If this flow ever
# turns brittle (a Keycloak upgrade changes the login page markup, or an
# authenticator/OTP step is added to the browser flow), that is the escape
# hatch: add a `local-audit` client with DAG on, and say so in the audit.
#
# USAGE
#   ./scripts/keycloak-token.sh                      # alice's access token
#   USERNAME=bob ./scripts/keycloak-token.sh         # another demo user
#   KC_OUTPUT=json ./scripts/keycloak-token.sh       # full token response
#                                                    # (refresh_token lives here)
#
# ENV (all defaulted for local-stack)
#   KC_URL        http://localhost:8081      published Keycloak origin. Must be
#                                            the origin the token's `iss` should
#                                            carry — start-dev derives `iss`
#                                            from the request host, and the edge
#                                            SecurityPolicy pins exactly
#                                            http://localhost:8081/realms/duynhlab
#   KC_REALM      duynhlab
#   KC_CLIENT_ID  customer-spa               public client, PKCE S256 required
#   KC_REDIRECT   http://localhost:3001/     must match the client's redirectUris
#   USERNAME      alice
#   PASSWORD      password123
#   KC_OUTPUT     token | json
#   KC_CACERT     (unset)                    CA bundle to verify an HTTPS
#                                            Keycloak against — needed on a
#                                            cluster edge, whose cert comes
#                                            from the self-signed homelab-ca
#   KC_INSECURE   (unset)                    set to any value to skip TLS
#                                            verification instead (curl -k)
#
# Cluster example (Kind), where KC_URL is HTTPS and the CA is self-signed:
#   KC_URL=https://id.duynh.me KC_INSECURE=1 ./scripts/keycloak-token.sh
#
# Requires: bash, curl, openssl, python3.
set -euo pipefail

KC_URL=${KC_URL:-http://localhost:8081}
KC_REALM=${KC_REALM:-duynhlab}
KC_CLIENT_ID=${KC_CLIENT_ID:-customer-spa}
KC_REDIRECT=${KC_REDIRECT:-http://localhost:3001/}
USERNAME=${USERNAME:-alice}
PASSWORD=${PASSWORD:-password123}
KC_OUTPUT=${KC_OUTPUT:-token}

# TLS trust. Compose serves Keycloak over plain HTTP, so neither of these is
# needed there and both default to empty. A cluster edge serves it over HTTPS
# with a certificate from the self-signed `homelab-ca`, which curl will not
# verify out of the box — without one of these the very first request fails
# and the whole PKCE flow dies before a code is ever issued.
#   KC_CACERT=/path/ca.crt  verify against that CA (preferred)
#   KC_INSECURE=1           skip verification entirely (curl -k)
KC_CACERT=${KC_CACERT:-}
KC_INSECURE=${KC_INSECURE:-}
CURL_TLS=()
if [[ -n "$KC_CACERT" ]]; then
  CURL_TLS=(--cacert "$KC_CACERT")
elif [[ -n "$KC_INSECURE" ]]; then
  CURL_TLS=(-k)
fi
# Each curl below expands this as ${CURL_TLS[@]+"${CURL_TLS[@]}"} so an empty
# array adds no argument — a bare "${CURL_TLS[@]}" aborts under `set -u` on
# bash < 4.4.

BASE="$KC_URL/realms/$KC_REALM/protocol/openid-connect"
JAR=$(mktemp -t kc-cookies.XXXXXX)
PAGE=$(mktemp -t kc-login.XXXXXX)
trap 'rm -f "$JAR" "$PAGE"' EXIT

die() { printf 'keycloak-token: %s\n' "$1" >&2; exit 1; }

# PKCE pair. The verifier must be 43-128 unreserved characters; the challenge is
# base64url(sha256(verifier)) with the padding stripped. `openssl rand -hex`
# rather than the usual `tr -dc … </dev/urandom | head -c N`: that idiom kills
# `tr` with SIGPIPE, and under `set -o pipefail` the 141 fails the script.
VERIFIER=$(openssl rand -hex 32)
CHALLENGE=$(printf '%s' "$VERIFIER" \
  | openssl dgst -binary -sha256 \
  | openssl base64 \
  | tr -d '\n' | tr '+/' '-_' | tr -d '=')
STATE=$(openssl rand -hex 8)

# 1. Authorization request. Answers 200 with the login page and sets the
#    AUTH_SESSION_ID / KC_RESTART cookies the form POST needs. `--get
#    --data-urlencode` lets curl build (and escape) the query string.
curl -sS ${CURL_TLS[@]+"${CURL_TLS[@]}"} -c "$JAR" -o "$PAGE" --get "$BASE/auth" \
  --data-urlencode "client_id=$KC_CLIENT_ID" \
  --data-urlencode "redirect_uri=$KC_REDIRECT" \
  --data-urlencode "response_type=code" \
  --data-urlencode "scope=openid" \
  --data-urlencode "state=$STATE" \
  --data-urlencode "code_challenge=$CHALLENGE" \
  --data-urlencode "code_challenge_method=S256" \
  || die "authorization request to $BASE/auth failed (is Keycloak up on $KC_URL?)"

# 2. The login form's action URL is per-attempt (session_code, execution,
#    tab_id). It is HTML-escaped in the page, so &amp; has to come back to &.
ACTION=$(grep -o 'action="[^"]*login-actions/authenticate[^"]*"' "$PAGE" \
  | head -1 | sed -e 's/^action="//' -e 's/"$//' -e 's/&amp;/\&/g')
[ -n "$ACTION" ] || die "no login form in the authorization response — realm '$KC_REALM' or client '$KC_CLIENT_ID' may not exist"

# 3. Submit the credentials. Success is a 302 to the redirect URI carrying the
#    authorization code; a failure re-renders the form with 200, which is why
#    this reads the Location header rather than the status.
LOCATION=$(curl -sS ${CURL_TLS[@]+"${CURL_TLS[@]}"} -b "$JAR" -c "$JAR" -o /dev/null -D - "$ACTION" \
  --data-urlencode "username=$USERNAME" \
  --data-urlencode "password=$PASSWORD" \
  --data-urlencode "credentialId=" \
  | tr -d '\r' | awk 'tolower($1) == "location:" { print $2 }' | head -1)
[ -n "$LOCATION" ] || die "login rejected for user '$USERNAME' (no redirect issued — wrong password, disabled user, or an extra authenticator in the browser flow)"

CODE=$(printf '%s' "$LOCATION" | sed -n 's/.*[?&]code=\([^&]*\).*/\1/p')
[ -n "$CODE" ] || die "redirect carried no authorization code: $LOCATION"

# 4. Exchange the code. A public client authenticates with the PKCE verifier
#    alone — no client secret exists.
RESP=$(curl -sS ${CURL_TLS[@]+"${CURL_TLS[@]}"} -X POST "$BASE/token" \
  --data-urlencode "grant_type=authorization_code" \
  --data-urlencode "client_id=$KC_CLIENT_ID" \
  --data-urlencode "redirect_uri=$KC_REDIRECT" \
  --data-urlencode "code=$CODE" \
  --data-urlencode "code_verifier=$VERIFIER")

if [ "$KC_OUTPUT" = json ]; then
  printf '%s\n' "$RESP"
  exit 0
fi

printf '%s' "$RESP" | python3 -c '
import json, sys
d = json.load(sys.stdin)
if "access_token" not in d:
    sys.exit("keycloak-token: token endpoint returned no access_token: %s" % d)
print(d["access_token"])
'
