defmodule Mix.Tasks.Brando.MigrateToTenant do
  @shortdoc "Copies an existing public-schema installation into a new tenant site"

  @moduledoc """
  Migrates existing public content into a new site's Production schema, then
  creates Staging as a complete copy.

      mix brando.migrate_to_tenant --site-key=my-site
      mix brando.migrate_to_tenant --site-key=my-site --name="My Site" --creator-email=admin@example.com

  Global users, sessions, tenant registry rows, Oban jobs, and asset-set
  metadata remain in `public` and are never copied into the tenant schema.

  Content is copied by default, which leaves the original rows in `public` as a
  rollback window. Pass `--move` to relocate the tables instead:

      mix brando.migrate_to_tenant --site-key=my-site --move

  Moving is a catalog operation, so it does not rewrite table data and is
  therefore constant-time regardless of installation size. It leaves no legacy
  rows behind, so take a restorable backup first.

  In `:multi`, media is copied into `media/{site_key}` and the original tree is
  kept for rollback, so the copy needs as much free space again. The task
  reports the size first and asks before copying a large tree; `--yes` skips
  that question for scripted runs. `:single` keeps using the existing media
  root and copies nothing.
  """

  use Mix.Task

  import Ecto.Query, only: [from: 2]

  alias Brando.Tenant.PublicDataMigrator
  alias Brando.Users.User

  @switches [
    site_key: :string,
    name: :string,
    creator_email: :string,
    move: :boolean,
    yes: :boolean
  ]

  # Below this, the copy is quick enough not to be worth interrupting for.
  @large_media_bytes 1_000_000_000

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")
    {opts, _remaining, invalid} = OptionParser.parse(args, strict: @switches)

    if invalid != [], do: Mix.raise("Invalid options: #{inspect(invalid)}")

    site_key = opts[:site_key] || Mix.raise("--site-key is required")
    name = opts[:name] || site_key |> String.replace("-", " ") |> String.capitalize()
    creator = creator!(opts[:creator_email])
    languages = configured_languages()
    default_language = Brando.config(:default_language) |> to_string()

    attrs = %{
      name: name,
      key: site_key,
      languages: languages,
      default_language: default_language,
      status: :active,
      delivery_mode: :dynamic
    }

    confirm_media_copy!(opts)

    case Brando.Tenant.Migration.migrate_public(attrs, creator, migration_opts(opts)) do
      {:ok, site} ->
        Mix.shell().info("#{verb(opts)} public content into site #{site.key} with Production and Staging environments")

      {:error, reason} ->
        Mix.raise("Tenant migration failed: #{inspect(reason)}")
    end
  end

  # Only `:multi` copies media; `:single` keeps using the existing media root,
  # so there is nothing to duplicate and nothing to warn about.
  defp confirm_media_copy!(opts) do
    if Brando.Tenant.mode() == :multi do
      media_path = Brando.config(:media_path)
      bytes = directory_size(media_path)

      Mix.shell().info("""

      Media at #{media_path} is #{format_bytes(bytes)}.
      It will be COPIED into media/#{opts[:site_key]}, so that much free disk
      space is needed. The original tree is left untouched for rollback.
      """)

      if bytes >= @large_media_bytes, do: confirm_large_media!(opts)
    end
  end

  defp confirm_large_media!(opts) do
    cond do
      opts[:yes] ->
        :ok

      Mix.shell().yes?("Continue and copy this media tree?") ->
        :ok

      true ->
        Mix.raise("Aborted before copying media")
    end
  end

  @doc false
  # Public so the size reporting can be tested without running a migration.
  def directory_size(path) do
    case File.stat(path) do
      {:ok, %{type: :directory}} ->
        path
        |> File.ls!()
        |> Enum.reduce(0, &(directory_size(Path.join(path, &1)) + &2))

      {:ok, %{size: size}} ->
        size

      {:error, _reason} ->
        0
    end
  end

  @doc false
  def format_bytes(bytes) when bytes >= 1_000_000_000,
    do: "#{Float.round(bytes / 1_000_000_000, 1)} GB"

  def format_bytes(bytes) when bytes >= 1_000_000,
    do: "#{Float.round(bytes / 1_000_000, 1)} MB"

  def format_bytes(bytes), do: "#{bytes} B"

  defp migration_opts(opts) do
    if opts[:move], do: [public_data_migrator: PublicDataMigrator.Move], else: []
  end

  defp verb(opts), do: if(opts[:move], do: "Moved", else: "Copied")

  defp creator!(nil) do
    from(user in User,
      where: user.role == :superuser and user.active,
      order_by: [asc: user.id],
      limit: 1
    )
    |> Brando.Repo.one(prefix: "public")
    |> case do
      %User{} = user -> user
      nil -> Mix.raise("No active superuser exists; pass --creator-email")
    end
  end

  defp creator!(email) do
    from(user in User, where: user.email == ^email and user.active)
    |> Brando.Repo.one(prefix: "public")
    |> case do
      %User{} = user -> user
      nil -> Mix.raise("No active user found for --creator-email=#{email}")
    end
  end

  defp configured_languages do
    Brando.config(:languages)
    |> List.wrap()
    |> Enum.map(fn
      options when is_list(options) -> options[:value]
      %{value: value} -> value
      language -> language
    end)
    |> Enum.map(&to_string/1)
    |> Enum.uniq()
    |> case do
      [] -> [Brando.config(:default_language) |> to_string()]
      languages -> languages
    end
  end
end
