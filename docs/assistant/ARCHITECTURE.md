# kousha.dev Assistant Architecture (MVP Foundation)

## Objective

Provide a production-minded assistant foundation that supports:

1. public profile/site Q&A,
2. authenticated and privileged assistant sessions,
3. appointment workflow intents,
4. constrained local Hermes actions over private networking.

## Components

1. **Web UI** (`/assistant`)
   - static frontend page on kousha.dev
   - sends requests to hosted assistant API

2. **Assistant API** (`services/assistant-api`)
   - tier resolution (public/authenticated/privileged/high-trust)
   - message handling and intent creation
   - explicit approval endpoint for sensitive actions
   - local bridge calls with signed requests
   - audit logging

3. **Local Agent** (`services/local-agent`)
   - receives only signed requests
   - replay protections (nonce + timestamp)
   - strict action allowlist
   - Hermes adapter boundary

4. **Knowledge sources**
   - `content/site.yaml`
   - `content/cv.md`

## Data Flow

1. User sends chat message.
2. Assistant API classifies request.
3. If informational: answer from CV/site knowledge context.
4. If sensitive action (booking/notify/local): create `pending` intent.
5. Privileged approval is required via `/v1/approve`.
6. Approved local intents are signed and sent to local agent.
7. Local agent validates and executes allowlisted Hermes action.
8. Audit records are written at each stage.

## Why this shape

- Keeps public web surface separate from local-machine privileges.
- Enables least privilege and explicit confirmation by default.
- Supports future expansion (calendar, email, reminders) without changing trust boundaries.
