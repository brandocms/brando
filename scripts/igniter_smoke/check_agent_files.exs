# The installer copies Brando's site skills and links its usage rules.
[framework] = System.argv()
skills = Path.join(framework, "usage-rules/skills")

copied =
  for source <- Path.wildcard(Path.join(skills, "**/*")), File.regular?(source) do
    target = Path.join(".claude/skills", Path.relative_to(source, skills))
    ^target = if File.read!(target) == File.read!(source), do: target, else: raise("#{target} differs")
  end

true = copied != []
agents = File.read!("AGENTS.md")
true = String.contains?(agents, "<!-- brando-start -->") and String.contains?(agents, "(deps/brando/usage-rules.md)")

IO.puts("#{length(copied)} skill files and the AGENTS.md usage-rules link verified")
