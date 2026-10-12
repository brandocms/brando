if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.SourceUpgrade.BuiltinActions do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @moduledoc false
    # 0.53 generators declared a listing's edit, duplicate and delete actions
    # (`[label: gettext("Edit post"), event: "edit_entry"]`). A listing's
    # `default_actions` (true unless set) brings the same three, so every row
    # menu offered each twice. An `action` naming one of their events is
    # removed when the listing keeps the defaults; with `default_actions false`
    # it is how the listing puts that one back, and stays. An action with
    # options beyond a label and a confirmation is listed instead.

    alias Igniter.Project.Module, as: ProjectModule
    alias Mix.Brando.Igniter.SourceUpgrade
    alias Rewrite.Source
    alias Sourceror.Zipper

    @events ~w(edit_entry duplicate_entry delete_entry)
    @options [:label, :event, :confirm]

    @doc """
    Removes listing `action`s that repeat a built-in action the listing
    already has, and lists them in a notice. Run it after the Blueprint
    rewrite, which turns 0.53 `actions [...]` lists into `action` calls.
    """
    def remove(igniter) do
      {igniter, blueprints} = SourceUpgrade.find_blueprints(igniter)

      {igniter, removed, kept} =
        Enum.reduce(blueprints, {igniter, [], []}, fn module, {igniter, removed, kept} ->
          {igniter, found, left} = remove_from_module(igniter, module)
          {igniter, removed ++ Enum.map(found, &{module, &1}), kept ++ left}
        end)

      igniter
      |> add_notice(removed)
      |> add_warning(kept)
    end

    defp remove_from_module(igniter, module) do
      {:ok, {igniter, source, zipper}} = ProjectModule.find_module(igniter, module)
      path = Source.get(source, :path)
      {ast, {found, left}} = Macro.prewalk(Zipper.node(zipper), {[], []}, &remove_from_listing(&1, &2, path))

      igniter =
        if found == [],
          do: igniter,
          else: Igniter.update_elixir_file(igniter, path, fn _zipper -> {:ok, Zipper.replace(zipper, ast)} end)

      {igniter, Enum.reverse(found), Enum.reverse(left)}
    end

    defp remove_from_listing({:listing, meta, [_ | _] = args} = node, acc, path) do
      {arguments, [block]} = Enum.split(args, -1)

      with [{{:__block__, _, [:do]} = do_key, body}] <- block,
           statements = statements(body),
           false <- Enum.any?(statements, &default_actions_off?/1) do
        {statements, acc} = Enum.flat_map_reduce(statements, acc, &remove_action(&1, &2, path))
        {{:listing, meta, arguments ++ [[{do_key, {:__block__, block_meta(body), statements}}]]}, acc}
      else
        _ -> {node, acc}
      end
    end

    defp remove_from_listing(node, acc, _path), do: {node, acc}

    defp statements({:__block__, _, statements}) when is_list(statements), do: statements
    defp statements(statement), do: [statement]

    defp block_meta({:__block__, meta, statements}) when is_list(statements), do: meta
    defp block_meta(_statement), do: []

    defp default_actions_off?({:default_actions, _, [{:__block__, _, [false]}]}), do: true
    defp default_actions_off?(_statement), do: false

    defp remove_action({:action, meta, [options]} = statement, {removed, kept}, path) when is_list(options) do
      options = keyword(options)

      case literal(options[:event]) do
        {:ok, event} when event in @events ->
          if Enum.all?(Keyword.keys(options), &(&1 in @options)),
            do: {[], {[label(options) | removed], kept}},
            else: {[statement], {removed, ["#{path}:#{meta[:line]}: #{event}" | kept]}}

        _other ->
          {[statement], {removed, kept}}
      end
    end

    defp remove_action(statement, acc, _path), do: {[statement], acc}

    defp keyword(options) do
      for {{:__block__, _, [key]}, value} <- options, is_atom(key), do: {key, value}
    end

    defp literal({:__block__, _, [value]}), do: {:ok, value}
    defp literal(_value), do: :error

    defp label(options) do
      case options[:label] do
        nil -> "(no label)"
        label -> Sourceror.to_string(label)
      end
    end

    defp add_notice(igniter, []), do: igniter

    defp add_notice(igniter, removed) do
      Igniter.add_notice(igniter, """
      Listing actions that repeat a built-in were removed. A listing's
      `default_actions` (on unless `default_actions false`) already offers
      edit, duplicate and delete, so each row menu showed them twice:

      #{Enum.map_join(removed, "\n", fn {module, label} -> "  #{inspect(module)}: #{label}" end)}
      """)
    end

    defp add_warning(igniter, []), do: igniter

    defp add_warning(igniter, kept) do
      Igniter.add_warning(igniter, """
      These listing actions run a built-in event the listing already offers
      through `default_actions`, but have options of their own, so they were
      kept. Remove each, or set `default_actions false` in its listing to keep
      only the listing's own actions (guides/blueprint_listings.md#row-actions):

      #{Enum.map_join(kept, "\n", &("  " <> &1))}
      """)
    end
  end
end
