# ADR-009: CI builds with -Dcpu=baseline for WSL portability

## Status
Accepted

## Context
Flint must fit the Deepiri bus (Sugar Glider + ModelKit topics) without becoming another Redis client farm.

## Decision
CI builds with -Dcpu=baseline for WSL portability.

## Consequences
- Aligns with Cyrex / Helox / LIS stream contracts
- Keeps the runtime small and operable
