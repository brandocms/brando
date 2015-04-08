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
    Mix.Brando.logo
    Mix.shell.info "--------------------------------------------"
    Mix.shell.info "% Create administrator"
    Mix.shell.info "--------------------------------------------"

    email = Mix.shell.prompt("Email:") |> String.strip
    username = Mix.shell.prompt("Username:") |> String.strip
    fullname = Mix.shell.prompt("Full Name:") |> String.strip
    password = Mix.shell.prompt("Password:") |> String.strip

    Brando.get_repo.start_link
    :bcrypt.start
    ret = User.create(%{"email" => email, "username" => username,
                  "password" => password, "full_name" => fullname,
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