# Production

1. Set `FLINT_SUGAR_GLIDER_URL` to the in-cluster Sugar Glider service
2. Mount tinder ConfigMap at `/config/tinder.json`
3. Set unique `FLINT_CONSUMER_NAME` per replica
4. Probe `/healthz` on `FLINT_ADMIN_PORT`
5. Scrape `/metrics`
