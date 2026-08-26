/**
 * Runs the bundled mock Mailtea API for test.sh.
 *
 * Prints the server URL on stdout, then on SIGTERM writes every request it
 * received to the file given as argv[2], one per line, tab separated:
 *
 *     METHOD \t PATH \t AUTHORIZATION \t COMPACT-JSON-BODY
 *
 * Bash can assert against that with `read` and `[ ... ]`, which keeps the test
 * free of jq and of any JSON parsing in shell.
 */
import { writeFileSync } from "node:fs";
import { startMockMailtea } from "./mock-mailtea.mjs";

const outFile = process.argv[2];
if (!outFile) {
  console.error("usage: node test/mock-server.mjs <requests-output-file>");
  process.exit(1);
}

const server = await startMockMailtea();
process.stdout.write(`${server.url}\n`);

const dumpAndExit = () => {
  const lines = server.requests.map((request) =>
    [
      request.method,
      request.path,
      request.authorization ?? "",
      JSON.stringify(request.body)
    ].join("\t")
  );
  writeFileSync(outFile, lines.length ? `${lines.join("\n")}\n` : "");
  process.exit(0);
};

process.on("SIGTERM", dumpAndExit);
process.on("SIGINT", dumpAndExit);
