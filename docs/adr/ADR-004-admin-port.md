# ADR-004: Expose /healthz and /metrics on FLINT_ADMIN_PORT

## Status
Accepted

## Context
Flint must fit the Deepiri bus (Sugar Glider + ModelKit topics) without becoming another Redis client farm.

## Decision
Expose /healthz and /metrics on FLINT_ADMIN_PORT.

## Consequences
- Aligns with Cyrex / Helox / LIS stream contracts
- Keeps the runtime small and operable
