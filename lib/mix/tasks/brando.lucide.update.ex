defmodule Mix.Tasks.Brando.Lucide.Update do
  use Mix.Task

  @shortdoc "Vendors a Lucide release into priv/lucide/icons.json"

  @moduledoc """
  Vendors a [Lucide](https://lucide.dev) release into `priv/lucide/icons.json`.

      $ mix brando.lucide.update 1.52.0

  Downloads the GitHub tag tarball for `lucide-icons/lucide@VERSION`, reads
  `icons/*.svg` and `icons/*.json`, and writes one JSON file holding the
  version, every icon body, the deprecated aliases and the search tags.

  Each icon sits on its own line, so a version bump diffs cleanly. Stroke
  attributes are stripped from the icon elements, so the stroke width is set
  by CSS (`Brando.Icons`).

  This is a maintainer task for Brando itself. Applications never run it.
  """

  @output "priv/lucide/icons.json"
  @tarball_url "https://codeload.github.com/lucide-icons/lucide/tar.gz/refs/tags/"

  @impl Mix.Task
  def run([version]) do
    Application.ensure_all_started([:req])

    Mix.shell().info("Downloading Lucide #{version}…")
    %{status: 200, body: tarball} = Req.get!(@tarball_url <> version, decode_body: false)

    {:ok, files} = :erl_tar.extract({:binary, tarball}, [:memory, :compressed])

    icons =
      for {path, contents} <- files,
          [_root, "icons", file] <- [Path.split(to_string(path))],
          reduce: %{} do
        acc -> collect(acc, file, contents)
      end

    output = encode(version, icons)
    File.mkdir_p!(Path.dirname(@output))
    File.write!(@output, output)

    Mix.shell().info("Wrote #{map_size(icons)} icons to #{@output}")
  end

  def run(_args), do: Mix.raise("Usage: mix brando.lucide.update VERSION")

  defp collect(acc, file, contents) do
    case Path.extname(file) do
      ".svg" ->
        name = Path.basename(file, ".svg")
        Map.update(acc, name, %{body: body(contents)}, &Map.put(&1, :body, body(contents)))

      ".json" ->
        name = Path.basename(file, ".json")
        meta = Jason.decode!(contents)
        Map.update(acc, name, %{meta: meta}, &Map.put(&1, :meta, meta))

      _ ->
        acc
    end
  end

  # The inner markup of the `<svg>` root, one element after the other, with
  # per-element stroke attributes removed.
  defp body(svg) do
    svg
    |> String.replace(~r/\A.*?<svg[^>]*>/s, "")
    |> String.replace(~r{</svg>\s*\z}s, "")
    |> String.replace(~r/\s+stroke(-[a-z]+)?="[^"]*"/, "")
    |> String.replace(~r/\s*\n\s*/, "")
    |> String.replace(~r/\s+\/>/, "/>")
  end

  defp encode(version, icons) do
    names = icons |> Map.keys() |> Enum.filter(&icons[&1][:body]) |> Enum.sort()

    aliases =
      for name <- names,
          alias <- get_in(icons, [name, :meta, "aliases"]) || [],
          do: {alias_name(alias), name}

    tags = for name <- names, do: {name, get_in(icons, [name, :meta, "tags"]) || []}

    Enum.join(
      [
        "{",
        ~s(  "version": #{Jason.encode!(version)},),
        section("icons", Enum.map(names, &{&1, icons[&1].body})) <> ",",
        section("aliases", Enum.sort(aliases)) <> ",",
        section("tags", tags),
        "}\n"
      ],
      "\n"
    )
  end

  defp alias_name(%{"name" => name}), do: name
  defp alias_name(name) when is_binary(name), do: name

  defp section(key, entries) do
    lines = Enum.map_join(entries, ",\n", fn {k, v} -> "    #{Jason.encode!(k)}: #{Jason.encode!(v)}" end)
    ~s(  "#{key}": {\n#{lines}\n  })
  end
end
