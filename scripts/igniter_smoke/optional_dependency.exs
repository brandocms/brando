[mode] = System.argv()
line = "      {:igniter, \"~> 0.8.0\", only: [:dev, :test]},\n"
mix = File.read!("mix.exs")

case mode do
  "remove" ->
    true = String.contains?(mix, line)
    File.write!("mix.exs", String.replace(mix, line, "", global: false))

  "add" ->
    marker = "defp deps do\n    [\n"
    true = String.contains?(mix, marker)
    File.write!("mix.exs", String.replace(mix, marker, marker <> line, global: false))
end
