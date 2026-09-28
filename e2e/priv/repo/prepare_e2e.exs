# Invoked by test_e2e.sh after compilation, before the application starts.
# Keep all database tasks in the same VM; only the final seed needs the server.
{opts, [], []} =
  OptionParser.parse(System.argv(), strict: [reset: :boolean, check_migrations: :boolean])

if opts[:reset] do
  Mix.shell().info("Resetting database with seed data...")
  Mix.Task.run("ecto.drop", ["--quiet"])
end

Mix.Task.run("ecto.create", ["--quiet"])
Mix.Task.run("ecto.migrate", ["--quiet"])

if opts[:check_migrations] do
  Mix.shell().info("Validating post-baseline migration rollback and forward execution...")
  # --to is inclusive: preserve the monolithic baseline and roll back its successors.
  Mix.Task.run("ecto.rollback", ["--to", "20250528084352", "--quiet"])
  Mix.Task.reenable("ecto.migrate")
  Mix.Task.run("ecto.migrate", ["--quiet"])
end

Mix.Task.run("app.start")
Code.eval_file(Path.join(__DIR__, "ensure_e2e_seeds.exs"))
