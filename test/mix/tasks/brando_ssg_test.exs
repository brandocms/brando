defmodule BrandoIntegrationWeb.SSG do
  import Brando.SSG

  urls :pages do
    ["/"]
  end
end

defmodule Mix.Tasks.Brando.SsgTest do
  use Brando.ConnCase

  setup do
    put_test_env(:tenancy_mode, :none)
    Mix.Task.reenable("brando.ssg")
    Mix.Task.reenable("run")
    :ok
  end

  test "retains a non-tenant, non-interactive dry-run workflow" do
    output = Path.join(System.tmp_dir!(), "brando-ssg-task-#{System.unique_integer([:positive])}")
    refute File.exists?(output)

    assert :ok =
             Mix.Tasks.Brando.Ssg.run([
               "--force",
               "--dry-run",
               "--output",
               output
             ])

    refute File.exists?(output)
  end
end
