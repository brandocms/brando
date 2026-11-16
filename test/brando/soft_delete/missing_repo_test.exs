defmodule Brando.SoftDelete.MissingRepoTest do
  use Brando.ConnCase

  alias Brando.Doctor.Checks.SoftDeleteRepo
  alias Brando.Doctor.Result

  defmodule PlainRepo do
    @moduledoc false
    use Ecto.Repo, otp_app: :brando, adapter: Ecto.Adapters.Postgres
  end

  @line "use Brando.SoftDelete.Repo"

  test "a soft delete through a repo without the functions names what is missing" do
    user = Brando.Factory.insert(:random_user)
    fragment = Brando.Factory.insert(:fragment, creator: user)
    put_test_env(:repo_module, PlainRepo)

    for call <- [
          fn -> Brando.Repo.soft_delete(fragment) end,
          fn -> Brando.Repo.soft_delete!(fragment) end,
          fn -> Brando.Repo.soft_delete_all(Brando.Pages.Fragment) end,
          fn -> Brando.Repo.restore(fragment) end,
          fn -> Brando.Repo.restore!(fragment) end
        ] do
      error = assert_raise Brando.Exception.ConfigError, call
      assert error.message =~ "#{inspect(PlainRepo)} lacks Brando's soft-delete functions"
      assert error.message =~ @line
      refute error.message =~ "not available"
    end
  end

  test "boot fails with the same message" do
    put_test_env(:repo_module, PlainRepo)

    error = assert_raise Brando.Exception.ConfigError, fn -> Brando.System.run_checks() end
    assert error.message =~ "lacks Brando's soft-delete functions"
    assert error.message =~ @line
  end

  test "the System check reports it as an error, naming the line to add" do
    assert %Result{status: :ok} = SoftDeleteRepo.run(Brando.Doctor.Context.new([]))

    assert %Result{status: :error, summary: summary, fix: fix} = SoftDeleteRepo.evaluate(PlainRepo)
    assert summary =~ "lacks Brando's soft-delete functions"
    assert fix == "add use Brando.SoftDelete.Repo to #{inspect(PlainRepo)}, after use Ecto.Repo"
  end

  test "the doctor runs it" do
    assert SoftDeleteRepo in Brando.Doctor.checks()
  end
end
