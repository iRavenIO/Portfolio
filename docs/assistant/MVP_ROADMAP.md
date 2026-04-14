# Assistant MVP Roadmap

## MVP (current foundation)

- Assistant UI page (`/assistant`)
- Hosted assistant API (chat + approve + audit + health)
- Tier model and rate limiting
- Pending intent flow for sensitive actions
- Local agent with signed calls and allowlisted actions
- CV/site knowledge grounding

## Next Phase

- Replace token header auth with full OIDC session auth
- Add persistent database for sessions/intents/audit
- Integrate real calendar provider for booking
- Add structured approval UX and expiration windows

## Advanced Later

- Fine-grained policy admin UI
- Pull-mode local agent fallback
- Provider-agnostic notification channels
- richer workflow automation with policy constraints
