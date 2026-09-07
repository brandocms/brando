defmodule SmokeFingerprint do
  @ignored ~w(_build deps .git node_modules .yalc .elixir_ls)

  def files(directory) do
    directory
    |> File.ls!()
    |> Enum.reject(&(&1 in @ignored))
    |> Enum.flat_map(fn name ->
      path = Path.join(directory, name)
      if File.dir?(path), do: files(path), else: [path]
    end)
  end
end

"."
|> SmokeFingerprint.files()
|> Enum.sort()
|> Enum.map(&{&1, File.read!(&1)})
|> :erlang.term_to_binary([:deterministic])
|> then(&:crypto.hash(:sha256, &1))
|> Base.encode16(case: :lower)
|> IO.puts()
