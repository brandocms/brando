# The installer copies Brando's site skills and links its usage rules, naming
# the package's files where this application has the dependency.
[framework] = System.argv()
skills = Path.join(framework, "usage-rules/skills")
agents = File.read!("AGENTS.md")

link =
  case Regex.run(~r{^\[brando usage rules\]\((.+)/usage-rules\.md\)}m, agents) do
    [_, link] -> link
    nil -> raise "AGENTS.md has no brando usage rules link"
  end

true = File.regular?(Path.join(link, "usage-rules.md")) or raise("#{link}/usage-rules.md does not exist")

copied =
  for source <- Path.wildcard(Path.join(skills, "**/*")), File.regular?(source) do
    target = Path.join(".claude/skills", Path.relative_to(source, skills))
    expected = String.replace(File.read!(source), "deps/brando/", link <> "/")
    ^target = if File.read!(target) == expected, do: target, else: raise("#{target} differs")
  end

true = copied != []
true = String.contains?(agents, "<!-- brando-start -->")

IO.puts("#{length(copied)} skill files and the AGENTS.md usage-rules link (#{link}) verified")
