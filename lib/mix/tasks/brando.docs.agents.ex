defmodule Mix.Tasks.Brando.Docs.Agents do
  @shortdoc "Generates usage-rules.md, llms.txt and llms-full.txt from the guides"

  @moduledoc """
  Generates the documentation that coding agents read, from Brando's
  `guides/*.md`. For Brando's own repository; it does nothing useful in an
  application.

      mix brando.docs.agents
      mix brando.docs.agents --check
      mix brando.docs.agents --only llms

  It writes:

    * `usage-rules.md`, from the regions of each guide between
      `<!-- usage-rules:start -->` and `<!-- usage-rules:end -->`: the core
      rules for building a site, and an index of the topic files;
    * `usage-rules/<topic>.md`, from regions that name a topic,
      `<!-- usage-rules:start topic="seo" -->`. The topics are listed in
      `lib/mix/brando/docs/agents.ex`. Both ship in the Hex package, where
      `usage_rules` finds them (the topics as `brando:<topic>`);
    * `llms.txt` and `llms-full.txt` in the docs output directory (`doc/`):
      an index of the guides with a one-line description each, and all guides
      joined. `mix docs` runs this task after ExDoc, replacing ExDoc's own
      `llms.txt`.

  Options:

    * `--check` writes nothing and exits with status 1 when a rules file is
      out of date or no longer generated, for CI.
    * `--only rules` or `--only llms` writes one of the two.
    * `--output DIR` writes the llms files to `DIR` instead of the docs output
      directory.

  An Elixir example inside a region is compiled by a test. Put
  `<!-- usage-rules:no-compile -->` on the line before a fence that cannot be.
  Links in the rules point at `deps/brando/guides/`, where the guides are in
  an application that depends on the Hex package or a git checkout. With a
  `path:` dependency they don't resolve; the guides are in the Brando
  checkout instead.

  A guide's description in `llms.txt` is its first sentence, or the text of a
  `<!-- llms-description: ... -->` comment in the guide.
  """

  use Mix.Task

  alias Mix.Brando.Docs.Agents

  @switches [check: :boolean, only: :string, output: :string]

  @impl Mix.Task
  def run(args) do
    {opts, _positional} = OptionParser.parse!(args, strict: @switches)

    if Mix.Project.config()[:app] != :brando do
      Mix.raise("mix brando.docs.agents generates Brando's own documentation and only runs in Brando's repository.")
    end

    guides = Agents.guides()

    cond do
      opts[:check] -> check!(guides)
      opts[:only] == "rules" -> write_rules(guides)
      opts[:only] == "llms" -> write_llms(guides, opts)
      is_nil(opts[:only]) -> write_all(guides, opts)
      true -> Mix.raise("--only must be rules or llms, got: #{opts[:only]}")
    end
  end

  defp check!(guides) do
    expected = Agents.rules_files(guides)
    stale = Enum.reject(generated_files(), &Map.has_key?(expected, &1))
    outdated = for {path, contents} <- expected, read(path) != contents, do: path

    case Enum.sort(outdated ++ stale) do
      [] -> Mix.shell().info("#{map_size(expected)} rules files are up to date.")
      paths -> Mix.raise("Out of date: #{Enum.join(paths, ", ")}. Run mix brando.docs.agents and commit the result.")
    end
  end

  defp write_all(guides, opts) do
    write_rules(guides)
    write_llms(guides, opts)
  end

  defp write_rules(guides) do
    expected = Agents.rules_files(guides)

    for path <- generated_files(), not Map.has_key?(expected, path) do
      File.rm!(path)
      Mix.shell().info("Removed #{path}")
    end

    File.mkdir_p!("usage-rules")
    for {path, contents} <- Enum.sort(expected), do: write(path, contents)
  end

  # Topic files from earlier runs. Skills, in usage-rules/skills, are not generated.
  defp generated_files, do: Path.wildcard("usage-rules/*.md")

  defp read(path), do: if(File.exists?(path), do: File.read!(path), else: nil)

  defp write_llms(guides, opts) do
    output = opts[:output] || Mix.Project.config()[:docs][:output] || "doc"
    File.mkdir_p!(output)
    write(Path.join(output, "llms.txt"), Agents.llms_txt(guides))
    write(Path.join(output, "llms-full.txt"), Agents.llms_full_txt(guides))
  end

  defp write(path, contents) do
    File.write!(path, contents)
    Mix.shell().info("Wrote #{path} (#{byte_size(contents)} bytes)")
  end
end
