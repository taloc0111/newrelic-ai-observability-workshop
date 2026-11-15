#!/usr/bin/env bash
# Capture the New Relic account id and keys with no-echo prompts into ~/.nr-keys (chmod 600). Nothing lands in history.
# Every later script does:  source ~/.nr-keys
#
# Two keys, two jobs (Step 1 of the guide):
#   License key  (40 chars, ends in NRAL)  = INGEST. Goes into the cluster (nri-bundle, agent injection, Lab 7 pod).
#   User key     (NRAK-...)                = CONTROL PLANE. NerdGraph: policies, conditions, workflows, issues, change tracking.
trim() { local s="$1"; s="${s//$'\r'/}"; s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; printf '%s' "$s"; }   # strip CR and surrounding whitespace (pasted values often carry one)
read -rp  "Account id (digits, top right of one.newrelic.com > account menu): " ACC; ACC="$(trim "$ACC")"
[[ "$ACC" =~ ^[0-9]+$ ]] || { echo "account id must be digits only, got '$ACC'"; exit 1; }
read -rp  "Region [US/EU] (EU = data centre eu01, api.eu.newrelic.com): " REGION; REGION="$(trim "$REGION")"
REGION="${REGION:-US}"; REGION="${REGION^^}"
case "$REGION" in US|EU) ;; *) echo "region must be US or EU, got '$REGION'"; exit 1 ;; esac
read -srp "License key (ingest, ends in NRAL): " LIC; echo; LIC="$(trim "$LIC")"
[[ ${#LIC} -eq 40 && "$LIC" == *NRAL ]] || { echo "license key should be 40 characters ending in NRAL (got ${#LIC} characters) - copy the Ingest - License key, not the User key"; exit 1; }
read -srp "User API key (NRAK-...): " USR; echo; USR="$(trim "$USR")"
[[ "$USR" == NRAK-* ]] || { echo "user key must start with NRAK- - create a key of type User"; exit 1; }
{
  printf 'export NEW_RELIC_ACCOUNT_ID="%s"\n' "$ACC"
  printf 'export NEW_RELIC_REGION="%s"\n' "$REGION"
  printf 'export NEW_RELIC_LICENSE_KEY="%s"\n' "$LIC"
  printf 'export NEW_RELIC_API_KEY="%s"\n' "$USR"
  if [ "$REGION" = "EU" ]; then
    printf 'export NEW_RELIC_HOST="collector.eu01.nr-data.net"\n'
    printf 'export NR_UI="https://one.eu.newrelic.com"\n'
  else
    printf 'export NR_UI="https://one.newrelic.com"\n'
  fi
} > ~/.nr-keys
chmod 600 ~/.nr-keys; unset LIC USR
echo "saved to ~/.nr-keys  ->  source ~/.nr-keys"
echo ">> check the User key:  source ~/.nr-keys && python3 ~/nr-training/labs/lib/nerdgraph.py ~/nr-training/labs/03-newrelic/whoami.graphql"
