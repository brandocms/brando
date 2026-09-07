# This fixture file was created by customize.exs in the same disposable app.
expected = File.read!(".igniter-smoke-customized") |> :erlang.binary_to_term([:safe])

Enum.each(expected, fn {path, digest} ->
  ^digest = :crypto.hash(:sha256, File.read!(path))
end)

:preserved = IgniterSmoke.Catalog.custom_marker()
:preserved = Application.fetch_env!(:igniter_smoke, :legacy_marker)
true = Process.alive?(Process.whereis(IgniterSmoke.LegacySupervisor))
IO.puts("Existing files, context function, configuration and supervised process preserved")
