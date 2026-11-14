#!/usr/bin/env python3
"""Tiny NerdGraph client for the lab scripts. No dependencies beyond the standard library.

Usage:  python3 nerdgraph.py <file.graphql> [key=value ...] [--raw]
  - reads NEW_RELIC_API_KEY (User key, NRAK-...) and NEW_RELIC_REGION (US|EU) from the environment
    (every script does `source ~/.nr-keys` first; see labs/03-newrelic/save-keys.sh)
  - key=value pairs become GraphQL variables. A value is sent as Int only when the query declares that
    variable as Int (accountId: Int!), everything else as String (a policy id declared String! stays "123").
    Prefix a key with '@' to read the value from a file.
  - prints the JSON response (pretty). Exits 1 on HTTP errors or a top-level "errors" array.
"""
import json
import os
import re
import sys
import urllib.error
import urllib.request

ENDPOINT = {"US": "https://api.newrelic.com/graphql", "EU": "https://api.eu.newrelic.com/graphql"}


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    query = open(sys.argv[1], encoding="utf-8").read()
    declared = dict(re.findall(r"\$(\w+)\s*:\s*\[?\s*(\w+)", query))
    variables = {}
    for arg in sys.argv[2:]:
        if arg == "--raw" or "=" not in arg:
            continue
        key, value = arg.split("=", 1)
        if key.startswith("@"):
            key = key[1:]
            value = open(value, encoding="utf-8").read()
        if declared.get(key) == "Int" and value.lstrip("-").isdigit():
            value = int(value)
        variables[key] = value

    api_key = os.environ.get("NEW_RELIC_API_KEY", "")
    if not api_key.startswith("NRAK-"):
        print("NEW_RELIC_API_KEY missing or not a User key (NRAK-...). Run: source ~/.nr-keys", file=sys.stderr)
        return 1
    url = ENDPOINT.get(os.environ.get("NEW_RELIC_REGION", "US").upper(), ENDPOINT["US"])
    body = json.dumps({"query": query, "variables": variables}).encode()
    req = urllib.request.Request(url, data=body, headers={"Content-Type": "application/json", "API-Key": api_key})
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            data = json.loads(resp.read())
    except urllib.error.HTTPError as e:
        print("HTTP", e.code, e.read().decode(errors="replace")[:500], file=sys.stderr)
        return 1
    print(json.dumps(data, indent=2))
    return 1 if data.get("errors") else 0


if __name__ == "__main__":
    sys.exit(main())
