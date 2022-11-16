defmodule Mix.Tasks.Brando.Gen.Admin do
  use Mix.Task

  @shortdoc "Generate new admin user"

  @moduledoc """
  Generate new admin user
  """
  @spec run([]) :: no_return
  def run([]) do
    Application.put_env(:logger, :level, :error)

    Mix.Tasks.Run.run([])

    Mix.shell().info("""

    ---------------------------------
    % Brando Generate Admin Superuser
    ---------------------------------
    """)

    email = prompt_with_default("Email address:", "admin@brandocms.com")
    name = prompt_with_default("Name:", "Brando CMS")
    password = password_get("Account password:", true) |> String.trim()

    Mix.shell().info([
      :blue,
      """
      ==> Creating superuser

      Email....: #{email}
      Name.....: #{name}
      Password.: <redacted>

      """
    ])

    # insert admin user
    hashed_password = Bcrypt.hash_pwd_salt(password)

    user = %Brando.Users.User{
      name: name,
      email: email,
      password: hashed_password,
      avatar: nil,
      role: :superuser,
      language: :en
    }

    Brando.repo().insert!(user)

    Mix.shell().info([:green, "\n==> Done.\n"])
  end

  defp prompt_with_default(prompt, default) do
    case Mix.shell().prompt("+ #{prompt} [#{default}]") |> String.trim("\n") do
      "" -> default
      ret -> ret
    end
  end

  # Password prompt that hides input by every 1ms
  # clearing the line with stderr
  def password_get(prompt, false) do
    IO.gets(prompt <> " ")
  end

  def password_get(prompt, true) do
    pid = spawn_link(fn -> loop(prompt) end)
    ref = make_ref()
    value = IO.gets(prompt <> " ")

    send(pid, {:done, self(), ref})
    receive do: ({:done, ^pid, ^ref} -> :ok)

    value
  end

  defp loop(prompt) do
    receive do
      {:done, parent, ref} ->
        send(parent, {:done, self(), ref})
        IO.write(:standard_error, "\e[2K\r")
    after
      1 ->
        IO.write(:standard_error, "\e[2K\r#{prompt} ")
        loop(prompt)
    end
  end
end
