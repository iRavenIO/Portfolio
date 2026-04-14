# Assistant Security and Trust Model

## Trust Boundaries

1. **Public visitors**: untrusted, anonymous traffic.
2. **Authenticated users**: trusted identity, limited permissions.
3. **Privileged/high-trust users**: explicit sensitive approvals.
4. **Hosted assistant API**: policy enforcement boundary.
5. **Local agent + Hermes on Mac**: highest sensitivity boundary.

## Core Principles

- Deny by default.
- Least privilege for tools and users.
- No arbitrary command execution in MVP.
- Explicit approval for sensitive actions.
- Immutable-ish append audit logs.
- Fast disable controls (kill switches).

## Permission Tiers

- **public**: informational chat only.
- **authenticated**: richer context, may request appointment intent.
- **privileged**: approve protected actions.
- **high_trust**: operational/audit endpoints.

## Action Classes

- `safe_read`: profile/site answers.
- `sensitive_write`: booking + notification.
- `local_privileged`: Hermes/local actions.

`sensitive_write` and `local_privileged` require pending intent + approval.

## Local Bridge Security Controls

1. Signed requests (`x-assistant-signature`) with HMAC.
2. Timestamp freshness requirement.
3. Nonce replay prevention.
4. Allowlisted action names only.
5. `AGENT_LOCKDOWN=true` emergency shutdown.
6. `LOCAL_TOOLS_ENABLED=false` backend-side kill switch.

## Threats and Mitigations

- **Prompt/tool abuse**: strict allowlist + approval gate.
- **Replay attack**: nonce + timestamp checks.
- **Privilege escalation**: tier checks per endpoint + per-intent.
- **Backend compromise blast radius**: local agent still requires signed requests and allowlisted actions.
- **Data leakage**: narrow response payloads + log redaction discipline.

## Operational Requirements

- Rotate shared secret periodically.
- Keep local agent non-public and reachable only through private network.
- Monitor audit logs for repeated denied attempts.
