[framework] = System.argv()

for {format, source, target} <- Mix.Brando.Install.Templates.manifest(),
    format == :copy,
    Path.extname(target) in [".ico", ".woff2"] do
  expected = File.read!(Path.join([framework, "priv/templates/brando.install", source]))
  ^expected = File.read!(target)
end

for name <- ~w(admin_manifest.json manifest.json) do
  %{} = "priv/static/#{name}" |> File.read!() |> Jason.decode!()
end

IO.puts("Both Vite manifests and exact binary assets verified")
