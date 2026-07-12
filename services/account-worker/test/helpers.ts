import { readFile, readdir } from "node:fs/promises";
import { Miniflare } from "miniflare";

export async function createTestDatabase(): Promise<{ mf: Miniflare; db: D1Database }> {
  const mf = new Miniflare({
    compatibilityDate: "2026-07-10",
    d1Databases: { DB: "test-account-db" },
    modules: true,
    script: "export default { fetch() { return new Response('ok') } }",
  });
  try {
    const db = (await mf.getD1Database("DB")) as unknown as D1Database;
    const migrationDirectory = new URL("../migrations/", import.meta.url);
    const migrationFiles = (await readdir(migrationDirectory))
      .filter((name) => name.endsWith(".sql"))
      .sort();
    for (const migrationFile of migrationFiles) {
      const migration = await readFile(new URL(migrationFile, migrationDirectory), "utf8");
      const statements = migration
        .split(";")
        .map((statement) => statement.trim())
        .filter(Boolean)
        .map((statement) => db.prepare(statement));
      await db.batch(statements);
    }
    return { mf, db };
  } catch (error) {
    await mf.dispose();
    throw error;
  }
}

export async function seedAccount(db: D1Database, id: string, now = 1_700_000_000): Promise<void> {
  await db
    .prepare(
      `INSERT INTO accounts
       (id, apple_subject_hash, deletion_subject_hash, status, created_at, updated_at)
       VALUES (?, ?, ?, 'active', ?, ?)`,
    )
    .bind(id, `subject-${id}`, `deletion-subject-${id}`, now, now)
    .run();
}
