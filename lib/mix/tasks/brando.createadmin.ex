defmodule Mix.Tasks.Brando.Createadmin do
  use Mix.Task
  alias Brando.Users.Model.User

  @shortdoc "Generates admin for Brando."

  @moduledoc """
  Creates a user with admin rights.
  """

  @doc """
  Create admin. Parses `args` for us.
  """
  def run(args) do
    {opts, args, _} = OptionParser.parse(args)
    run(args, opts)
  end
  @doc """
  See run/1
  """
  def run([], []) do
    Mix.raise """
    brando.createadmin expects --email, --username, --password and --fullname options.

        mix brando.createadmin --email=my@email.com --username=user --password=asdf1234 --fullname="Roger Wilco"

    """
  end
  @doc """
  See run/1
  """
  def run(_args, opts) do
    Brando.get_repo.start_link
    :bcrypt.start
    email = Keyword.fetch!(opts, :email)
    username = Keyword.fetch!(opts, :username)
    password = Keyword.fetch!(opts, :password)
    full_name = Keyword.fetch!(opts, :fullname)
    ret = User.create(%{"email" => email, "username" => username,
                  "password" => password, "full_name" => full_name,
                  "role" => ["1", "2", "4"]})
    case ret do
      {:ok, _user} ->
        Mix.shell.info """
        ------------------------------------------------------------------
        Created new admin #{username} / #{email}
        ------------------------------------------------------------------
        """
      {:error, errs} ->
        Mix.shell.info """
        ------------------------------------------------------------------
        Error creating admin.
        #{inspect(errs)}
        ------------------------------------------------------------------
        """
    end

  end
end