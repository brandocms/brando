# Source-planning tests can run without starting Brando or connecting to PostgreSQL:
# MIX_ENV=test mix run --no-start scripts/test_igniter.exs
ExUnit.start()
Mix.shell(Mix.Shell.Process)

default_tests =
  Path.wildcard("test/mix/brando/{igniter,install}/**/*_test.exs") ++
    ["test/mix/tasks/brando/brando.install_test.exs"]

tests = if System.argv() == [], do: default_tests, else: System.argv()
Enum.each(tests, &Code.require_file/1)
