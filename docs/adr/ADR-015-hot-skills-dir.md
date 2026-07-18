# ADR-015: WASM skills loaded lazily from FLINT_SKILLS_DIR

## Status
Accepted

## Context
Flint must fit the Deepiri bus (Sugar Glider + ModelKit topics) without becoming another Redis client farm.

## Decision
WASM skills loaded lazily from FLINT_SKILLS_DIR.

## Consequences
- Aligns with Cyrex / Helox / LIS stream contracts
- Keeps the runtime small and operable
