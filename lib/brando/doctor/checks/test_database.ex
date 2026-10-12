defmodule Brando.Doctor.Checks.TestDatabase do
  @moduledoc """
  Whether `mix test` would use the development database. The test
  configuration (`config/config.exs` and `config/runtime.exs`, read for
  `:test` in this shell's environment) is compared with the Repo the doctor
  runs with. A `runtime.exs` that reads the Repo URL from an environment
  variable in every environment makes them the same, and a `test` alias that
  runs `ecto.migrate` then migrates the development database.

  Runs in development only, and reads the source tree's config files, so it
  is skipped in a release.
  """
  use Brando.Doctor.Check
  use Gettext, backend: Brando.Gettext

  alias Brando.Doctor.Context
  alias Config.Reader

  @impl true
  def id, do: "test_database"

  @impl true
  def label, do: dgettext("doctor", "Test database")

  @impl true
  def needs_source?, do: true

  @impl true
  def run(%Context{root: root}) do
    if Brando.env() == :dev do
      repo = Brando.repo()

      case test_repo_config(root, Brando.otp_app(), repo) do
        {:ok, test_config} -> evaluate(test_config, repo.config())
        {:error, reason} -> skipped(reason)
      end
    else
      skipped(dgettext("doctor", "checked in development"))
    end
  end

  @doc """
  The Repo's settings for `:test`, read from the config files under `root`
  in this shell's environment.
  """
  def test_repo_config(root, otp_app, repo) do
    config = Path.join(root, "config/config.exs")
    runtime = Path.join(root, "config/runtime.exs")

    cond do
      not File.exists?(config) ->
        {:error, dgettext("doctor", "no config/config.exs")}

      Enum.any?(Path.wildcard(Path.join(root, "config/*.exs")), &(File.read!(&1) =~ "Mix.env")) ->
        {:error, dgettext("doctor", "the config files read Mix.env(), which cannot be read for :test from here")}

      true ->
        read = Reader.read!(config, env: :test, target: :host)

        read =
          if File.exists?(runtime),
            do: Reader.merge(read, Reader.read!(runtime, env: :test, target: :host, imports: :disabled)),
            else: read

        {:ok, read |> Keyword.get(otp_app, []) |> Keyword.get(repo, [])}
    end
  rescue
    exception ->
      {:error, dgettext("doctor", "could not read the test config: %{error}", error: Exception.message(exception))}
  end

  @doc "Compares the test Repo settings with the development Repo's."
  def evaluate(test_config, dev_config) do
    test = database(test_config)
    dev = database(dev_config)

    cond do
      is_nil(elem(test, 2)) or is_nil(elem(dev, 2)) ->
        skipped(dgettext("doctor", "no database name to compare"))

      test == dev ->
        warning(dgettext("doctor", "mix test would use the development database %{database}", database: elem(dev, 2)),
          fix:
            dgettext(
              "doctor",
              "read the Repo url: in config/runtime.exs only outside tests, inside if config_env() != :test do … end"
            ),
          items: [dgettext("doctor", "test and development both connect to %{database}", database: describe(dev))]
        )

      true ->
        ok(dgettext("doctor", "%{database}, not the development database", database: elem(test, 2)))
    end
  end

  # `{hostname, port, database}`; a `url:` wins over the separate settings.
  defp database(config) do
    config = Keyword.merge(config, url_settings(config[:url]))
    {config[:hostname] || "localhost", port(config[:port]), config[:database]}
  end

  defp url_settings(url) when is_binary(url) and url != "" do
    uri = URI.parse(url)
    database = uri.path && String.trim_leading(uri.path, "/")

    [hostname: uri.host, port: uri.port, database: database]
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
  end

  defp url_settings(_url), do: []

  defp port(nil), do: 5432
  defp port(port) when is_binary(port), do: String.to_integer(port)
  defp port(port), do: port

  defp describe({hostname, port, database}), do: "#{database} on #{hostname}:#{port}"
end
