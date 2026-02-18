#!/usr/bin/env bash
set -euo pipefail

CFG="/data/.openclaw/openclaw.json"

# If config exists, remove bad gateway.bind and apply trusted proxies from env
if [ -f "$CFG" ]; then
  python3 - <<'PY'
import json, os

cfg_path = "/data/.openclaw/openclaw.json"
with open(cfg_path, "r") as f:
    cfg = json.load(f)

gw = cfg.get("gateway") or {}

# Remove bind completely (your logs show gateway.bind can be invalid)
if "bind" in gw:
    del gw["bind"]

# If env provides trusted proxies, write them into config
env_tp = os.getenv("OPENCLAW_GATEWAY_TRUSTED_PROXIES", "").strip()
if env_tp:
    tp = [x.strip() for x in env_tp.split(",") if x.strip()]
    # de-dupe while preserving order
    seen = set()
    tp2 = []
    for x in tp:
        if x not in seen:
            tp2.append(x); seen.add(x)
    gw["trustedProxies"] = tp2

# Only write gateway section if it has anything
if gw:
    cfg["gateway"] = gw
else:
    cfg.pop("gateway", None)

with open(cfg_path, "w") as f:
    json.dump(cfg, f, indent=2, sort_keys=True)
print("patched", cfg_path)
PY
fi

# Start OpenClaw gateway
exec node openclaw.mjs gateway --allow-unconfigured --bind lan --port "${PORT:-8080}"

