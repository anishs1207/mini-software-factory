# Product delivery report

Complete this after real agent runs. Replace every TODO with observed evidence and links. Do not report estimates as measurements.

## Product and reproduction

- Selected spec and commit: TODO
- Product artifact or live URL, according to the spec: TODO
- Repository and default-branch revision: TODO
- Reproduction: configure the ignored Terraform variables and agent keys, commit/push the spec and factory, then run `python agents/setup/apply.py` or Terraform init/apply plus `manager.sh`: TODO actual commands and results

## Agent roster and contributions

| Agent | Runtime | Role | Actual model | Tools | Work | Issue/PR evidence |
| --- | --- | --- | --- | --- | --- | --- |
| manager | Hermes | Orchestrator | TODO | TODO | TODO | TODO |
| builder1 | OpenClaw | Builder | TODO | TODO | TODO | TODO |
| builder2 | OpenClaw | Builder | TODO | TODO | TODO | TODO |
| reviewer | Hermes | Reviewer | TODO | TODO | TODO | TODO |
| tester | Hermes | Tester | TODO | TODO | TODO | TODO |

## Ticket flow and quality

- Spec to issues, dependencies, and agent assignments: TODO
- PR, CI, review, test, human merge, and release or artifact handoff: TODO
- Actual failure or rejection and how it was caught and fixed; if none occurred, say so: TODO
- What to change next: TODO
- Relevant acceptance commands and results from the selected spec: TODO
- Real trace excerpts with GitHub links: TODO

Run `python3 agents/trace-report.py --output .local-evidence/trace-excerpts.md` to find real linked handoffs and any rejection or retry. Review the source comments before copying excerpts.

## Model and token report

Run `bash agents/usage-report.sh` on the VM. Record its by-issue, by-purpose, per-agent and per-model totals for planning, coding, review/test, and retries, including interactive manager requests. Save a local snapshot with `bash agents/usage-report.sh > .local-evidence/usage-summary.tsv`. Mark missing runtime usage as unknown or add a documented estimate with method; explain where tokens went.

| Agent | Model | Planning | Coding | Review/test | Retries | Method |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| manager | TODO | TODO | — | — | TODO | TODO |
| builder1 | TODO | — | TODO | — | TODO | TODO |
| builder2 | TODO | — | TODO | — | TODO | TODO |
| reviewer | TODO | — | — | TODO | TODO | TODO |
| tester | TODO | — | — | TODO | TODO | TODO |
