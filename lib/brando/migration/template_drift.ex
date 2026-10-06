defmodule Brando.Migration.TemplateDrift do
  @moduledoc """
  Finds copies of Brando's upgrade migrations that have not run yet and no
  longer match Brando's templates.

  `mix brando.gen.migrations` matches copies by name, so a copy made months
  ago stays as it was even after the template is fixed. That is right for a
  migration that has already run: it is history. A copy that has not run
  yet, though, would replay the old version, bug included.

  Copies are compared as code: formatting and comments do not count.

    * `{:outdated, path, template}`: a pending copy whose code differs from
      its template.
    * `{:renumbered, path, template}`: a pending copy of a template that has
      since been renumbered; `mix brando.gen.migrations` copies it again
      under the new number, so the old copy should go.
  """

  @type finding :: {:outdated | :renumbered, Path.t(), Path.t()}

  @doc "Brando's upgrade migration templates"
  def templates_dir do
    :brando
    |> :code.priv_dir()
    |> Path.join("templates/brando.upgrade/migrations")
  end

  @doc """
  Checks the migrations in `directory` that `repo` has not run yet.
  """
  @spec pending(Ecto.Repo.t(), Path.t()) :: [finding()]
  def pending(repo, directory \\ nil) do
    directory = directory || Ecto.Migrator.migrations_path(repo)

    pending_versions =
      for {:down, version, _name} <- Ecto.Migrator.migrations(repo, [directory]), into: MapSet.new(), do: version

    check(directory, pending_versions)
  end

  @doc """
  Checks the `brando_*` copies in `directory` whose versions are in
  `pending_versions`.
  """
  @spec check(Path.t(), MapSet.t(integer()), Path.t()) :: [finding()]
  def check(directory, pending_versions, templates_dir \\ templates_dir()) do
    templates =
      templates_dir
      |> Path.join("brando_*.exs")
      |> Path.wildcard()
      |> Map.new(&{Path.basename(&1), &1})

    templates_by_suffix = Map.new(templates, fn {name, path} -> {suffix(name), path} end)

    directory
    |> Path.join("*_brando_*.exs")
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.map(&{&1, Integer.parse(Path.basename(&1))})
    |> Enum.flat_map(fn
      {path, {version, "_" <> name}} ->
        if MapSet.member?(pending_versions, version),
          do: classify(path, name, templates, templates_by_suffix),
          else: []

      _ ->
        []
    end)
  end

  @doc """
  Replaces an outdated copy with its template.
  """
  @spec update!(finding()) :: :ok
  def update!({:outdated, path, template}), do: File.cp!(template, path)

  defp classify(path, name, templates, templates_by_suffix) do
    case Map.fetch(templates, name) do
      {:ok, template} ->
        if same_code?(path, template), do: [], else: [{:outdated, path, template}]

      :error ->
        case Map.fetch(templates_by_suffix, suffix(name)) do
          {:ok, template} -> [{:renumbered, path, template}]
          :error -> []
        end
    end
  end

  defp suffix(name), do: String.replace(name, ~r/^brando_\d+_/, "")

  defp same_code?(path, template), do: normalize(File.read!(path)) == normalize(File.read!(template))

  defp normalize(code) do
    case Code.string_to_quoted(code) do
      {:ok, quoted} -> Macro.prewalk(quoted, &Macro.update_meta(&1, fn _ -> [] end))
      {:error, _} -> code
    end
  end
end
