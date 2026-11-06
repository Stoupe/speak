# Speak usage stats endpoint

The Cloudflare Worker behind `https://speak-telemetry.stoupe.dev/v1/report`, which receives Speak's optional,
anonymous daily usage report (see the main README's "Usage stats" section for what is sent and why).

- `src/report.ts` accepts exactly the report's fields, with types and ranges checked; anything else gets a 400.
- `src/index.ts` stores a valid report in D1 with the UTC date it arrived. It never reads the IP address or other
  headers, logging and traces are off (`cloudflare.config.ts`), and each insert deletes reports older than 13 months.
- `migrations/` is the D1 schema. The database is `speak-telemetry` (`8113e4ab-d7f9-4164-b537-239207213d89`).

Uses the `cf` CLI (`npm i -g cf`, then `cf auth login`), not Wrangler. From this folder:

```sh
npm install
npm test                 # report validation
npm run typecheck
cf deploy --dry-run      # build and check without uploading
cf deploy                # publish; also attaches speak-telemetry.stoupe.dev
npm run db:migrate       # apply new files in migrations/ to the live database
```

`Tools/stats.sh` (repo root) prints a summary of what has been received.
