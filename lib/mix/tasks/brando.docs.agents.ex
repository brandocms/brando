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
      `<!-- usage-rules:start -->` and `<!-- usage-rules:end -->`. It ships in
      the Hex package, where `usage_rules` and similar tools find it;
    * `llms.txt` and `llms-full.txt` in the docs output directory (`doc/`):
      an index of the guides with a one-line description each, and all guides
      joined. `mix docs` runs this task after ExDoc, replacing ExDoc's own
      `llms.txt`.

  Options:

    * `--check` writes nothing and exits with status 1 when `usage-rules.md`
      is out of date, for CI.
    * `--only rules` or `--only llms` writes one of the two.
    * `--output DIR` writes the llms files to `DIR` instead of the docs output
      directory.

  An Elixir example inside a region is compiled by a test. Put
  `<!-- usage-rules:no-compile -->` on the line before a fence that cannot be.
  A guide's description in `llms.txt` is its first sentence, or the text of a
  `<!-- llms-description: ... -->` comment in the guide.
  """

  use Mix.Task

  alias Mix.Brando.Docs.Agents

  @switches [check: :boolean, only: :string, output: :string]
  @rules "usage-rules.md"

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
    current = if File.exists?(@rules), do: File.read!(@rules), else: ""

    if current == Agents.usage_rules(guides) do
      Mix.shell().info("#{@rules} is up to date.")
    else
      Mix.raise("#{@rules} is out of date. Run mix brando.docs.agents and commit the result.")
    end
  end

  defp write_all(guides, opts) do
    write_rules(guides)
    write_llms(guides, opts)
  end

  defp write_rules(guides) do
    write(@rules, Agents.usage_rules(guides))
  end

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
