import { cp, mkdtemp, readdir, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawn } from "node:child_process";

function run(command, args, cwd) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, { cwd, stdio: "inherit" });
    child.once("error", reject);
    child.once("exit", (code, signal) => {
      if (code === 0) resolve();
      else reject(new Error(`${command} exited with ${code ?? signal}`));
    });
  });
}

const sourceRoot = new URL("..", import.meta.url);
const temporaryRoot = await mkdtemp(join(tmpdir(), "aic-account-worker-tests-"));

try {
  for (const entry of ["src", "test", "migrations", "package.json", "package-lock.json", "tsconfig.json"]) {
    await cp(new URL(entry, sourceRoot), join(temporaryRoot, entry), { recursive: true });
  }
  // Vite/esbuild parse the literal '?' in the founder's workspace path as a URL query.
  // Run an exact source mirror from a safe temporary path instead of renaming the workspace.
  await run("npm", ["ci", "--ignore-scripts", "--no-audit", "--no-fund"], temporaryRoot);
  const tests = (await readdir(join(temporaryRoot, "test")))
    .filter((name) => name.endsWith(".test.ts"))
    .sort()
    .map((name) => join("test", name));
  await run(
    process.execPath,
    [join(temporaryRoot, "node_modules", "tsx", "dist", "cli.mjs"), "--test", ...tests],
    temporaryRoot,
  );
} finally {
  await rm(temporaryRoot, { recursive: true, force: true });
}
