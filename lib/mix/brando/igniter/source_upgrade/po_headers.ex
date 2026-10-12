if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.SourceUpgrade.PoHeaders do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @moduledoc false
    # A .po header is one string, its lines ended by `\n`. Older Poedit
    # releases wrote `"Plural-Forms: nplurals=2; plural=(n != 1);"` without
    # the `\n`, so the next header joins it:
    # `Plural-Forms: nplurals=2; plural=(n != 1);X-Generator: Poedit 3.0.1`.
    # Gettext 1.0 cannot parse that rule and warns once per catalog per
    # compile. The header is read with Expo; when its Plural-Forms line holds
    # a complete rule followed by more text, the rule gets a line of its own.
    # The text after it is kept as a header line of its own unless it is not
    # one (`3.0.1;`) or a later line sets the same header; text with no header
    # name standing on a line of its own goes too.

    alias Expo.PluralForms
    alias Rewrite.Source

    @header_name ~r/\A([A-Za-z][\w-]*):/
    @header_block ~r/^msgid ""\nmsgstr ""\n((?:"(?:[^"\\]|\\.)*"[ \t]*\n)*)/m

    @doc "Splits joined header lines in `priv/gettext/**/*.po` and lists the files."
    def split_joined_lines(igniter) do
      igniter = Igniter.include_glob(igniter, "priv/gettext/**/*.po")

      {igniter, fixed} =
        igniter.rewrite
        |> Rewrite.sources()
        |> Enum.map(&Source.get(&1, :path))
        |> Enum.filter(&(String.starts_with?(&1, "priv/gettext/") and Path.extname(&1) == ".po"))
        |> Enum.sort()
        |> Enum.reduce({igniter, []}, fn path, {igniter, fixed} ->
          content = igniter.rewrite |> Rewrite.source!(path) |> Source.get(:content)

          case normalize(content) do
            {:ok, updated, removed} ->
              {Igniter.update_file(igniter, path, &Source.update(&1, :content, updated)), fixed ++ [{path, removed}]}

            :unchanged ->
              {igniter, fixed}
          end
        end)

      notice(igniter, fixed)
    end

    @doc """
    `{:ok, content, removed}` with the header's lines split, and the text
    it removed, or `:unchanged`.
    """
    def normalize(content) do
      with {:ok, %Expo.Messages{headers: [_ | _] = headers}} <- Expo.PO.parse_string(content),
           lines = headers |> IO.iodata_to_binary() |> String.split("\n", trim: true),
           {split, removed} = split_lines(lines),
           true <- split != lines,
           [_, block] <- Regex.run(@header_block, content) do
        written = Enum.map_join(split, &(~s(") <> escape(&1) <> ~s(\\n"\n)))
        {:ok, String.replace(content, block, written, global: false), removed}
      else
        _ -> :unchanged
      end
    end

    defp split_lines(lines) do
      lines
      |> Enum.with_index()
      |> Enum.reduce({[], []}, fn {line, index}, {kept, removed} ->
        later = lines |> Enum.drop(index + 1) |> Enum.map(&header_name/1)

        case split_plural_forms(line) do
          {:split, plural_forms, rest} ->
            if header_name(rest) in [nil | later],
              do: {kept ++ [plural_forms], removed ++ [rest]},
              else: {kept ++ [plural_forms, rest], removed}

          :keep ->
            if header_name(line) == nil and String.trim(line) != "",
              do: {kept, removed ++ [line]},
              else: {kept ++ [line], removed}
        end
      end)
    end

    defp header_name(line) do
      case Regex.run(@header_name, line) do
        [_, name] -> String.downcase(name)
        nil -> nil
      end
    end

    # `{:split, "Plural-Forms: <rule>", rest}` when the line holds a complete
    # rule followed by other text.
    defp split_plural_forms("Plural-Forms:" <> value) do
      value = String.trim_leading(value)

      with {:error, _} <- PluralForms.parse(value),
           {rule, rest} when rest != "" <- complete_rule(value) do
        {:split, "Plural-Forms: " <> rule, String.trim(rest)}
      else
        _ -> :keep
      end
    end

    defp split_plural_forms(_line), do: :keep

    # The shortest prefix ending in `;` that is a complete rule.
    defp complete_rule(value) do
      ~r/;/
      |> Regex.scan(value, return: :index)
      |> Enum.find_value(fn [{index, 1}] ->
        rule = binary_part(value, 0, index + 1)

        if rule =~ "plural=" and match?({:ok, _}, PluralForms.parse(rule)),
          do: {rule, binary_part(value, index + 1, byte_size(value) - index - 1)}
      end)
    end

    defp escape(line), do: line |> String.replace("\\", "\\\\") |> String.replace("\"", "\\\"")

    defp notice(igniter, []), do: igniter

    defp notice(igniter, fixed) do
      Igniter.add_notice(igniter, """
      These catalogs' Plural-Forms header ran into the next header line (a
      header line without its `\\n`, as older Poedit releases wrote it), so
      Gettext could not read the rule. The task gave the rule a line of its
      own and dropped the text that was not a header of its own:

      #{Enum.map_join(fixed, "\n", fn {path, removed} -> "  #{path}#{removed_text(removed)}" end)}
      """)
    end

    defp removed_text([]), do: ""
    defp removed_text(removed), do: " (removed #{Enum.map_join(removed, ", ", &inspect/1)})"
  end
else
  defmodule Mix.Brando.Igniter.SourceUpgrade.PoHeaders do
    @moduledoc false
    # Revisit this source when the optional dependency becomes available.
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
  end
end
