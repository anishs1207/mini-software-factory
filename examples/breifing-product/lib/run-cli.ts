import { runBriefing } from "./runner";

async function main(): Promise<void> {
  const r = await runBriefing();
  console.log(JSON.stringify(r));
  process.exit(r.success ? 0 : 1);
}

main().catch(function (e: unknown) {
  console.error(e);
  process.exit(1);
});