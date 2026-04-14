# Assistant Setup Guide (MVP Foundation)

## 1) Install dependencies

From repo root:

```bash
npm install
```

## 2) Configure assistant API

```bash
cp services/assistant-api/.env.example services/assistant-api/.env.local
```

Set at minimum:

- `ASSISTANT_USER_TOKEN`
- `ASSISTANT_PRIVILEGED_TOKEN`
- `ASSISTANT_HIGH_TRUST_TOKEN`
- `BACKEND_LOCAL_SHARED_SECRET`
- `LOCAL_TOOLS_ENABLED=true` (only when local agent is running)

## 3) Configure local agent

```bash
cp services/local-agent/.env.example services/local-agent/.env.local
```

Set:

- `BACKEND_LOCAL_SHARED_SECRET` (must match assistant-api)
- optional `HERMES_ENDPOINT` and `HERMES_API_KEY`

## 4) Start services

Terminal A:

```bash
npm run assistant:local
```

Terminal B:

```bash
npm run assistant:api
```

Terminal C (web):

```bash
NEXT_PUBLIC_ASSISTANT_API_BASE=http://localhost:8787/v1 npm run dev
```

Open: `http://localhost:3000/assistant`

## 5) Basic test flow

1. Ask profile question (public).
2. Ask appointment question with privileged token set.
3. Click **Approve Pending Action**.
4. Verify local-agent and assistant-api logs in:
   - `services/assistant-api/data/assistant-audit.log`
   - `services/local-agent/data/local-agent-audit.log`

## Security Notes

- Do not expose local agent publicly.
- Keep shared secret out of git.
- Use Tailscale policy restrictions from `docs/assistant/TAILSCALE_SETUP.md`.
