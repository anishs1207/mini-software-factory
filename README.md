# Confer Briefing

Next.js app serving on localhost:3000.

## Dev

```bash
npm install
npm run dev
```

## Build

```bash
npm run build
npm start
```


## Data persistence

`FACTORY_DATA_DIR` must point at persistent VM data across releases so run history and comparison state survive release.

## Concurrency and recovery

- `.run-lock` is treated as stale and removed when its PID is dead or non-positive, when its stored PID is not a finite positive integer, or when the file mtime exceeds the 5-minute lock timeout.
- `POST /api/runs` requests while locked return 409 before any rate check; requests from the same client within 30 seconds return 429.
- `.run-lock` and `.rate-limit.json` persist under `FACTORY_DATA_DIR` and survive restarts so manual and scheduled runs can recover after a crash.
- overlapping requests cannot both acquire the lock; the acquired lock is released on 429 and on normal completion.
