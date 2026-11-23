# Empties a migrated test database and seeds it, as a new one would be:
# scripts/test-partitions runs it on each partition's database before its
# tests. A run that was killed leaves the rows its tests had committed (a
# Site, a Superuser) and the schemas they made, which fail the next run's
# tests. Faster than dropping the database, which waits for a checkpoint.
alias BrandoIntegration.Repo

{:ok, _} = Repo.start_link()

reset = """
DO $$
DECLARE name text;
BEGIN
  FOR name IN
    SELECT nspname FROM pg_namespace
    WHERE nspname NOT IN ('public', 'information_schema') AND nspname NOT LIKE 'pg\\_%'
  LOOP
    EXECUTE format('DROP SCHEMA %I CASCADE', name);
  END LOOP;

  EXECUTE (
    SELECT 'TRUNCATE ' || string_agg(format('%I', tablename), ', ') || ' RESTART IDENTITY CASCADE'
    FROM pg_tables
    WHERE schemaname = 'public' AND tablename <> 'schema_migrations'
  );
END $$
"""

# Dropping the schemas a killed run left can take long on a busy server
Repo.query!(reset, [], timeout: :infinity)

Code.eval_file("priv/repo/seeds.exs")
