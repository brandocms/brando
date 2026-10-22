defmodule BrandoAdmin.Components.PickerHandoverContractTest do
  # A picker hands what was picked or uploaded to the component that opened it,
  # its `event_target`: by `send_update/2`, received in the opener's `update/2`
  # (or `update_many/1`), or by a client push, received in its `handle_event/3`.
  # An opener without a clause for a message falls into its general
  # `update/2`, which crashes the entry form. That shipped for
  # `video_created_from_url` and again for `select_video`.
  #
  # Pickers, their messages and their openers are all read from `lib/`, so a
  # new message or a new opener is checked without editing this test. What the
  # parser cannot follow fails here and names what to add.
  use ExUnit.Case, async: true

  @root Path.expand("../../..", __DIR__)

  # Client hooks a picker renders with `data-event-target={@event_target}`,
  # and the events each pushes to that target. Read from JavaScript, so listed
  # by hand; the tests below fail when a picker or a hook disagrees with it.
  @hook_pushes %{
    "Brando.ImagePickerGrid" => {"assets/src/hooks/ImagePickerGrid/index.js", ["select_image"]}
  }

  setup_all do
    modules =
      [@root, "lib", "**", "*.ex"]
      |> Path.join()
      |> Path.wildcard()
      |> Enum.flat_map(&modules_in/1)

    pickers = Enum.filter(modules, &picker?/1)
    picker_names = MapSet.new(pickers, & &1.name)

    contracts =
      Map.new(pickers, fn picker ->
        {picker.name, %{messages: messages(picker), pushes: Enum.uniq(pushes(picker) ++ hook_pushes(picker))}}
      end)

    openings =
      modules
      |> Enum.flat_map(&openings(&1, picker_names))
      |> Enum.reject(&is_nil(&1.receiver))

    %{modules: modules, pickers: pickers, contracts: contracts, openings: openings}
  end

  test "finds the pickers, what they hand over, and who opens them", ctx do
    names = MapSet.new(ctx.pickers, & &1.name)

    for picker <- [
          BrandoAdmin.Components.ImagePicker,
          BrandoAdmin.Components.VideoPicker,
          BrandoAdmin.Components.FilePicker
        ] do
      assert picker in names, "#{inspect(picker)} is not recognised as a picker"
    end

    for {picker, %{messages: messages, pushes: pushes}} <- ctx.contracts do
      assert messages != [] or pushes != [], "#{inspect(picker)} hands its event_target nothing"

      assert Enum.any?(ctx.openings, &(&1.picker == picker)),
             "nothing opens #{inspect(picker)} with an event_target"
    end
  end

  test "every component that opens a picker has a clause for each message it hands over", ctx do
    by_name = Map.new(ctx.modules, &{&1.name, &1})

    missing =
      for %{receiver: receiver, picker: picker} <- Enum.uniq_by(ctx.openings, &{&1.receiver, &1.picker}),
          %{messages: messages, pushes: pushes} <- [ctx.contracts[picker]],
          problem <-
            Enum.reject(messages, &receives_update?(by_name[receiver], &1)) ++
              Enum.reject(pushes, &receives_push?(by_name[receiver], &1)) do
        "#{inspect(receiver)} opens #{inspect(picker)} but has no #{describe(problem)}"
      end

    assert missing == [], Enum.join(missing, "\n")
  end

  test "every event_target handed to a picker is one this test follows", ctx do
    picker_names = MapSet.new(ctx.pickers, & &1.name)

    unfollowed =
      for module <- ctx.modules,
          not MapSet.member?(picker_names, module.name),
          problem <- unfollowed(module, picker_names) do
        "#{inspect(module.name)}: #{problem}"
      end

    assert unfollowed == [], Enum.join(unfollowed, "\n")
  end

  test "the hand-listed hook pushes match the pickers and the hooks", ctx do
    rendered =
      ctx.pickers
      |> Enum.flat_map(&event_target_hooks/1)
      |> MapSet.new()

    assert rendered == MapSet.new(Map.keys(@hook_pushes)),
           "hooks rendered with data-event-target: #{inspect(MapSet.to_list(rendered))}; @hook_pushes lists #{inspect(Map.keys(@hook_pushes))}"

    for {hook, {path, events}} <- @hook_pushes do
      source = File.read!(Path.join(@root, path))

      pushed =
        ~r/pushEventTo\(\s*([^,]+?)\s*,\s*['"]([\w:-]+)['"]/
        |> Regex.scan(source, capture: :all_but_first)
        |> Enum.reject(fn [target, _] -> target == "this.targetComponent" end)
        |> MapSet.new(fn [_, event] -> event end)

      assert pushed == MapSet.new(events),
             "#{hook} (#{path}) pushes #{inspect(MapSet.to_list(pushed))} to the event target; @hook_pushes lists #{inspect(events)}"
    end
  end

  # --- Source ---

  defp modules_in(path) do
    path
    |> File.read!()
    |> Code.string_to_quoted!(file: path)
    |> collect_modules(nil, path)
  end

  defp collect_modules({:defmodule, _, [{:__aliases__, _, parts}, [do: body]]}, parent, path) do
    name = if parent, do: Module.concat([parent | parts]), else: Module.concat(parts)
    {nested, own} = split_nested(body)
    aliases = aliases(own, name)

    code = unpipe(own) ++ Enum.map(heex(own), &unpipe/1)

    [%{name: name, path: path, code: code, heex: Enum.join(heex_text(own), "\n"), aliases: aliases}] ++
      Enum.flat_map(nested, &collect_modules(&1, name, path))
  end

  defp collect_modules({:__block__, _, exprs}, parent, path), do: Enum.flat_map(exprs, &collect_modules(&1, parent, path))
  defp collect_modules(_, _, _), do: []

  # A module's own code, with the modules nested in it set aside.
  defp split_nested(body) do
    exprs =
      case body do
        {:__block__, _, exprs} -> exprs
        expr -> [expr]
      end

    Enum.split_with(exprs, &match?({:defmodule, _, _}, &1))
  end

  # `use BrandoAdmin` aliases `Phoenix.LiveView.JS` for every component.
  defp aliases(exprs, module) do
    Enum.reduce(exprs, %{__MODULE__: module, JS: Phoenix.LiveView.JS}, fn
      {:alias, _, [{:__aliases__, _, parts}, [as: {:__aliases__, _, [as]}]]}, acc ->
        Map.put(acc, as, resolve_parts(parts, acc))

      {:alias, _, [{:__aliases__, _, parts}]}, acc ->
        Map.put(acc, alias_name(parts), resolve_parts(parts, acc))

      {:alias, _, [{{:., _, [{:__aliases__, _, base}, :{}]}, _, children}]}, acc ->
        Enum.reduce(children, acc, fn {:__aliases__, _, parts}, acc ->
          Map.put(acc, alias_name(parts), resolve_parts(base ++ parts, acc))
        end)

      _, acc ->
        acc
    end)
  end

  defp alias_name(parts), do: parts |> Enum.reverse() |> hd()

  defp resolve({:__aliases__, _, parts}, aliases), do: resolve_parts(parts, aliases)
  defp resolve({:__MODULE__, _, _}, aliases), do: aliases[:__MODULE__]
  defp resolve(_, _), do: nil

  defp resolve_parts([{:__MODULE__, _, _} | rest], aliases), do: Module.concat([aliases[:__MODULE__] | rest])

  defp resolve_parts([head | rest], aliases) do
    case aliases do
      %{^head => module} -> Module.concat([module | rest])
      _ -> Module.concat([head | rest])
    end
  end

  # `a |> f(b)` as `f(a, b)`, so a piped `JS.push/2` reads like any other.
  defp unpipe(ast) do
    Macro.prewalk(ast, fn
      {:|>, _, [left, {fun, meta, args}]} when is_list(args) -> {fun, meta, [left | args]}
      {:|>, _, [left, {fun, meta, _}]} -> {fun, meta, [left]}
      other -> other
    end)
  end

  defp heex_text(ast) do
    ast
    |> Macro.prewalk([], fn
      {:sigil_H, _, [{:<<>>, _, parts}, _]} = node, acc -> {node, [Enum.join(parts) | acc]}
      node, acc -> {node, acc}
    end)
    |> elem(1)
    |> Enum.reverse()
    |> Enum.map(&String.replace(&1, ~r/<%!--.*?--%>/s, ""))
  end

  # The expressions in a template's attributes, `attr={...}`, parsed.
  defp heex(ast) do
    for text <- heex_text(ast), expression <- attribute_expressions(text) do
      case Code.string_to_quoted(expression) do
        {:ok, quoted} -> quoted
        {:error, error} -> flunk("cannot parse template attribute #{inspect(expression)}: #{inspect(error)}")
      end
    end
  end

  defp attribute_expressions(text) do
    ~r/=\{/
    |> Regex.scan(text, return: :index)
    |> Enum.map(fn [{start, length}] -> close_brace(text, start + length, 1, false, []) end)
  end

  defp close_brace(text, at, depth, in_string?, acc) do
    case binary_part(text, at, 1) do
      "\\" when in_string? -> close_brace(text, at + 2, depth, true, [binary_part(text, at, 2) | acc])
      "\"" -> close_brace(text, at + 1, depth, not in_string?, ["\"" | acc])
      "{" when not in_string? -> close_brace(text, at + 1, depth + 1, false, ["{" | acc])
      "}" when not in_string? and depth == 1 -> acc |> Enum.reverse() |> IO.iodata_to_binary()
      "}" when not in_string? -> close_brace(text, at + 1, depth - 1, false, ["}" | acc])
      char -> close_brace(text, at + 1, depth, in_string?, [char | acc])
    end
  end

  defp find(code, fun) do
    code
    |> Macro.prewalk([], fn node, acc ->
      case fun.(node) do
        nil -> {node, acc}
        found -> {node, [found | acc]}
      end
    end)
    |> elem(1)
    |> Enum.reverse()
  end

  # --- Pickers ---

  # A picker is opened with `update(%{event_target: ...}, socket)`.
  defp picker?(module) do
    module.code
    |> clause_patterns(:update, 2)
    |> Enum.any?(fn pattern -> pattern |> map_patterns() |> Enum.any?(&Keyword.has_key?(&1, :event_target)) end)
  end

  # `send_update(target, %{event: "...", ...})` to anything but a named module:
  # in a picker, that is its event_target.
  defp messages(picker) do
    picker.code
    |> find(fn
      {:send_update, _, [target, message]} ->
        if is_nil(resolve(target, picker.aliases)), do: message(picker, message)

      _ ->
        nil
    end)
    |> Enum.uniq()
  end

  defp message(picker, {:%{}, _, pairs}), do: message(picker, pairs)

  defp message(picker, pairs) when is_list(pairs) do
    case Keyword.get(pairs, :event) do
      event when is_binary(event) ->
        {:update, event, pairs |> Keyword.keys() |> Enum.sort()}

      other ->
        flunk("#{inspect(picker.name)} sends its event_target an event this test cannot read: #{Macro.to_string(other)}")
    end
  end

  defp message(picker, other),
    do: flunk("#{inspect(picker.name)} sends its event_target a message this test cannot read: #{Macro.to_string(other)}")

  # `JS.push("...", target: @event_target)`, piped or not.
  defp pushes(picker) do
    unfollowed = Regex.scan(~r/phx-target=\{@event_target\}/, picker.heex)

    assert unfollowed == [],
           "#{inspect(picker.name)} renders phx-target={@event_target}, which this test does not follow; push with JS.push(..., target: @event_target)"

    picker.code
    |> find(fn
      {{:., _, [js, :push]}, _, args} ->
        if resolve(js, picker.aliases) == Phoenix.LiveView.JS and Enum.any?(args, &event_target_option?/1),
          do: push(picker, args)

      _ ->
        nil
    end)
    |> Enum.uniq()
  end

  defp push(picker, args) do
    case Enum.find(args, &is_binary/1) do
      nil -> flunk("#{inspect(picker.name)} pushes an event this test cannot read to its event_target")
      event -> {:push, event}
    end
  end

  defp event_target_option?(opts) when is_list(opts), do: opts |> Keyword.get(:target) |> event_target?()
  defp event_target_option?(_), do: false

  defp event_target?({:@, _, [{:event_target, _, _}]}), do: true
  defp event_target?({{:., _, [_, :event_target]}, _, []}), do: true
  defp event_target?(_), do: false

  defp hook_pushes(picker) do
    for hook <- event_target_hooks(picker),
        {_path, events} <- [Map.get(@hook_pushes, hook, {nil, []})],
        event <- events do
      {:push, event}
    end
  end

  # The phx-hook of each element rendered with `data-event-target`.
  defp event_target_hooks(picker) do
    ~r/data-event-target=/
    |> Regex.scan(picker.heex, return: :index)
    |> Enum.map(fn [{at, _}] ->
      before = binary_part(picker.heex, 0, at)
      tag = before |> String.split("<") |> List.last()

      case Regex.run(~r/phx-hook="([^"]+)"/, tag, capture: :all_but_first) do
        [hook] -> hook
        nil -> flunk("#{inspect(picker.name)} renders data-event-target without a phx-hook before it in the tag")
      end
    end)
  end

  # --- Openers ---

  # Openers passing `event_target: nil` (the AI assistant) receive nothing:
  # their openings come back with no receiver.
  defp openings(module, picker_names), do: find(module.code, &opening(&1, module, picker_names))

  defp opening({:send_update, _, [target, opts]} = call, module, picker_names) do
    picker = resolve(target, module.aliases)
    opts = with {:%{}, _, pairs} <- opts, do: pairs

    with true <- MapSet.member?(picker_names, picker),
         true <- is_list(opts),
         {:ok, event_target} <- Keyword.fetch(opts, :event_target) do
      cond do
        is_nil(event_target) -> %{receiver: nil, picker: picker, call: call}
        self_target?(event_target) -> %{receiver: module.name, picker: picker, call: call}
        true -> nil
      end
    else
      _ -> nil
    end
  end

  defp opening(_, _, _), do: nil

  defp self_target?({:@, _, [{:myself, _, _}]}), do: true
  defp self_target?({:myself, _, context}) when is_atom(context), do: true
  defp self_target?({{:., _, [{{:., _, [_, :assigns]}, _, []}, :myself]}, _, []}), do: true
  defp self_target?(_), do: false

  # `event_target` anywhere outside an opening read above.
  defp unfollowed(module, picker_names) do
    followed = module |> openings(picker_names) |> MapSet.new(& &1.call)

    in_code =
      module.code
      |> Macro.prewalk(fn node -> if MapSet.member?(followed, node), do: :followed, else: node end)
      |> find(fn
        {:event_target, value} -> "event_target: #{Macro.to_string(value)}"
        _ -> nil
      end)

    in_templates =
      ~r/event_target=\{[^}]*\}/
      |> Regex.scan(module.heex)
      |> List.flatten()

    in_code ++ in_templates
  end

  # --- Receivers ---

  defp receives_update?(module, {:update, event, keys}) do
    if defines?(module, :update_many, 1) do
      event in update_many_events(module)
    else
      module.code
      |> clause_patterns(:update, 2)
      |> Enum.flat_map(&map_patterns/1)
      |> Enum.any?(fn pairs ->
        Keyword.get(pairs, :event) == event and Enum.all?(Keyword.keys(pairs), &(&1 in keys))
      end)
    end
  end

  defp receives_update?(_module, {:push, _}), do: true

  defp receives_push?(module, {:push, event}) do
    module.code
    |> clause_patterns(:handle_event, 3)
    |> Enum.any?(&(&1 == event))
  end

  defp receives_push?(_module, {:update, _, _}), do: true

  defp describe({:update, event, keys}),
    do: "update/2 clause for %{event: #{inspect(event)}} (sent with #{inspect(keys)})"

  defp describe({:push, event}), do: "handle_event/3 clause for #{inspect(event)}"

  # Events `update_many/1` picks out: `assigns[:event] == "..."`, `assigns.event in [...]`.
  defp update_many_events(module) do
    module.code
    |> find(fn
      {:def, _, [{:update_many, _, [_]}, body]} -> body
      _ -> nil
    end)
    |> find(fn
      {:==, _, [left, event]} when is_binary(event) -> if event_access?(left), do: [event]
      {:in, _, [left, events]} when is_list(events) -> if event_access?(left), do: Enum.filter(events, &is_binary/1)
      _ -> nil
    end)
    |> List.flatten()
  end

  defp event_access?({{:., _, [Access, :get]}, _, [_, :event]}), do: true
  defp event_access?({{:., _, [_, :event]}, _, []}), do: true
  defp event_access?(_), do: false

  defp defines?(module, name, arity), do: clause_patterns(module.code, name, arity) != []

  # The first argument of each `def name/arity` clause.
  defp clause_patterns(code, name, arity) do
    code
    |> find(fn
      {:def, _, [{:when, _, [{^name, _, args}, _]} | _]} -> args
      {:def, _, [{^name, _, args} | _]} when is_list(args) -> args
      _ -> nil
    end)
    |> Enum.filter(&(Enum.count(&1) == arity))
    |> Enum.map(&hd/1)
  end

  # The map patterns in a clause head, either side of `=`.
  defp map_patterns({:=, _, [left, right]}), do: map_patterns(left) ++ map_patterns(right)
  defp map_patterns({:%{}, _, pairs}) when is_list(pairs), do: [pairs]
  defp map_patterns(_), do: []
end
