# GitHub code reviewer

A CLI service that polls repositories owned by `anishs1207` (or `GITHUB_OWNER`) that the GitHub token can see. It inventories open issues and PRs, reviews each non-draft PR head using an OpenAI-compatible model, and posts one advisory GitHub review per head commit. Findings appear on added diff lines; the review body records the head SHA and a deduplication marker. A new commit gets a new review.

This is separate from the factory's issue-stage reviewer in `agents/`. It does not set `factory:*` labels, approve PRs, request changes as a GitHub gate, run untrusted PR code, or merge. Human review remains necessary.

## Setup

Requires Node.js 20+ and a model endpoint that supports `/chat/completions` with JSON object response format.

```sh
cd code-review
npm ci
npm run build
cp .env.example .env
# Fill .env with your credentials, then load it into your shell.
node --env-file=.env dist/cli.js once --dry-run
node --env-file=.env dist/cli.js run
```

With PowerShell, use `node --env-file=.env` on Node 20.6+ after filling `.env`. Keep the file private; it is ignored by Git. `npm run once` and `npm start` work when the variables are already exported in the environment.

`GH_TOKEN` is required. A classic PAT needs `repo` for private repos; a fine-grained PAT must select the repositories and allow repository metadata, issues (read), pull requests (read and write), and contents (read). GitHub only exposes repositories granted to the token. `REVIEW_API_KEY` is separate from the GitHub token. `REVIEW_BASE_URL` and `REVIEW_MODEL` select an OpenAI-compatible provider. `REVIEW_REPOS=owner/repo,owner/another` limits the scan. `POLL_SECONDS` defaults to 300 and must be at least 30. `once --dry-run` calls the model but prints the proposed review instead of posting it.

The reviewer reads `README.md`, `AGENTS.md`, and `CONTRIBUTING.md` from the PR's base commit, plus the PR description, open issues linked with `Fixes #N`/`Closes #N`/`Resolves #N`, and changed-file patches. Inputs are capped to control model cost. For large diffs, the review notes that context was truncated. Binary files and changes without a GitHub patch cannot receive inline findings. Each repository is scanned independently; a failure is logged and the next poll retries. GitHub reviews act as persistent state across restarts.

Run as a long-lived process under your preferred service manager. For a Linux user service, set `WorkingDirectory` to this directory and `ExecStart` to the absolute Node path followed by `--env-file=/absolute/path/code-review/.env /absolute/path/code-review/dist/cli.js run`; use `Restart=on-failure` and keep the environment file readable only by the service user.

## Review quality

The prompt asks for concrete failure paths and practical fixes, suppresses style comments, and treats repository text as untrusted. A review cannot establish safety or verify runtime behavior. Before trusting it as a gate, collect past incident PRs and expected bugs, run `once --dry-run` against those cases, and measure whether it finds the actual failures. Keep human review and CI in place. A separate sandbox with no GitHub or model credentials would be needed to execute PR code or browser tests safely.

GitHub REST endpoint details: [authenticated repositories](https://docs.github.com/en/rest/repos/repos#list-repositories-for-the-authenticated-user), [PR reviews](https://docs.github.com/en/rest/pulls/reviews#create-a-review-for-a-pull-request), [PR files](https://docs.github.com/en/rest/pulls/pulls#list-pull-requests-files).
