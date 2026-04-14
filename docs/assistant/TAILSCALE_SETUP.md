# Tailscale Setup for Hosted Assistant API ↔ Local Mac Agent

## Goal

Allow hosted assistant API to reach local agent privately without exposing the Mac to the public internet.

## Node Identities

- Hosted assistant API node: `tag:assistant-backend`
- Mac local agent node: `tag:assistant-mac`

## Access Policy (example)

Use a deny-by-default policy and permit only required traffic.

```json
{
  "tagOwners": {
    "tag:assistant-backend": ["autogroup:admin"],
    "tag:assistant-mac": ["autogroup:admin"]
  },
  "acls": [
    {
      "action": "accept",
      "src": ["tag:assistant-backend"],
      "dst": ["tag:assistant-mac:7443"]
    }
  ],
  "tests": [
    {
      "src": "tag:assistant-backend",
      "accept": ["tag:assistant-mac:7443"],
      "deny": ["tag:assistant-mac:22", "tag:assistant-mac:80", "tag:assistant-mac:443"]
    }
  ]
}
```

## Runtime Recommendations

1. Bind local agent to Tailscale interface or protected host.
2. Use MagicDNS for stable addressing where possible.
3. Keep app-layer request signing enabled even on private network.
4. Do not use Tailscale Funnel for local agent endpoint.

## Compromise Containment

If public app is compromised:

- disable local bridge with `LOCAL_TOOLS_ENABLED=false` on backend,
- set `AGENT_LOCKDOWN=true` on local agent,
- rotate `BACKEND_LOCAL_SHARED_SECRET`.
