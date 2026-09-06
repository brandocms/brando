defmodule Mix.Tasks.Brando.Authorization.Recover do
  use Mix.Task
  @shortdoc "Restores protected Superuser membership for an existing active account"
  @moduledoc """
  Operator recovery from an application shell:

      mix brando.authorization.recover admin@example.com

  Requires shell/database access. Does not create an account, enable a disabled
  account, or change its password. The recovery is recorded in the audit log.
  """
  def run([email]) do
    Mix.Task.run("app.start")

    case Brando.Repo.get_by(Brando.Users.User, email: email) do
      nil ->
        Mix.raise("Account not found")

      user ->
        case Brando.Authorization.Migration.recover_superuser(user) do
          {:ok, :ok} -> Mix.shell().info("Protected Superuser membership restored.")
          {:error, reason} -> Mix.raise("Recovery failed: #{inspect(reason)}")
        end
    end
  end

  def run(_), do: Mix.raise("Usage: mix brando.authorization.recover EMAIL")
end
