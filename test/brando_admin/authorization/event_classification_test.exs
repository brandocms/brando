defmodule BrandoAdmin.Authorization.EventClassificationTest do
  # Every event an admin LiveView, LiveComponent or event hook handles has a
  # class in `BrandoAdmin.Authorization.Events`. Reads the source, so a new
  # `handle_event` clause fails here until someone has said what it does. Adding
  # one is one word in that table, and the failure names the word and the place.
  use ExUnit.Case, async: true

  alias BrandoAdmin.Authorization.Events

  # Functions that take a LiveView's or a component's events on behalf of
  # `handle_event/3`, by way of `attach_hook/4`.
  @handlers ~r/^(handle_event|handle_block_event|handle_listing_event|handle_hooks_.*_event)$/

  # Public, not admin: these take no signed-in account's events.
  @not_admin ~w(Brando.HTML.Forms.LiveForm)

  # Other modules in lib/ whose `handle_event/N` is a telemetry or event-bus callback.
  @not_liveview ~r/^Brando\.(IndexNow|Search|Webhooks|Notifications\.|Tracing\.)/

  # Events these modules take by a name built at compile time or a prefix: the
  # source shows no literal to read. An unlisted one is a write all the same.
  @dispatched %{
    "BrandoAdmin.Content.SharedLibraryLive" => ~r/^(accept_update|customize|dismiss_update|reset)$/,
    "BrandoAdmin.Reauth" => ~r/^brando:reauth:/,
    "BrandoAdmin.Sites.SiteLive" => ~r/^(activate_site|archive|delete|suspend)$/,
    "BrandoAdmin.Sites.UtilsLive" => ~r/^authorization_/
  }

  defp sources, do: Path.wildcard("lib/**/*.ex")

  defp parse(file), do: file |> File.read!() |> Code.string_to_quoted!()

  # `{module, event}` for every literal event in a clause head or its guard.
  defp events do
    for file <- sources(),
        {module, body} <- modules(parse(file)),
        module not in @not_admin,
        not (module =~ @not_liveview),
        event <- module_events(body),
        uniq: true,
        do: {module, event}
  end

  defp modules(ast) do
    {_, found} =
      Macro.prewalk(ast, [], fn
        {:defmodule, _, [{:__aliases__, _, parts}, [do: body]]} = node, acc ->
          {node, [{Enum.join(parts, "."), body} | acc]}

        node, acc ->
          {node, acc}
      end)

    found
  end

  defp module_events(body) do
    attributes = attributes(body)

    {_, found} =
      Macro.prewalk(body, [], fn
        {:defmodule, _, _}, acc ->
          {nil, acc}

        {kind, _, [head | _]} = node, acc when kind in [:def, :defp] ->
          {node, head_events(head, attributes) ++ acc}

        node, acc ->
          {node, acc}
      end)

    found
  end

  defp head_events({:when, _, [{name, _, [event | _]}, guard]}, attributes) when is_atom(name) do
    if handler?(name), do: List.wrap(literal(event)) ++ guard_events(event, guard, attributes), else: []
  end

  defp head_events({name, _, [event | _]}, _attributes) when is_atom(name) do
    if handler?(name), do: List.wrap(literal(event)), else: []
  end

  defp head_events(_, _), do: []

  defp handler?(name), do: name |> Atom.to_string() |> String.match?(@handlers)

  defp literal(event) when is_binary(event), do: event
  defp literal(_), do: nil

  # `when event in [...]`, a `~w()` or an attribute holding one.
  defp guard_events({var, _, context}, guard, attributes) when is_atom(var) and is_atom(context) do
    {_, found} =
      Macro.prewalk(guard, [], fn
        {:in, _, [{^var, _, _}, list]} = node, acc -> {node, strings(list, attributes) ++ acc}
        {:==, _, [{^var, _, _}, value]} = node, acc when is_binary(value) -> {node, [value | acc]}
        node, acc -> {node, acc}
      end)

    found
  end

  defp guard_events(_event, _guard, _attributes), do: []

  defp strings(list, _attributes) when is_list(list), do: Enum.filter(list, &is_binary/1)
  defp strings({:sigil_w, _, [{:<<>>, _, [words]}, _]}, _attributes), do: String.split(words)
  defp strings({:@, _, [{name, _, _}]}, attributes), do: Map.get(attributes, name, [])
  defp strings(_, _attributes), do: []

  defp attributes(body) do
    {_, found} =
      Macro.prewalk(body, %{}, fn
        {:@, _, [{name, _, [value]}]} = node, acc ->
          {node, Map.put(acc, name, strings(value, %{}))}

        node, acc ->
          {node, acc}
      end)

    found
  end

  test "every event in lib/ has a class" do
    unclassified =
      for {module, event} <- events(), is_nil(Events.declared_class(module, event)), do: "#{module}: #{event}"

    assert unclassified == [], """
    These events have no class in BrandoAdmin.Authorization.Events. Add each to
    its module's list there: :write unless you have read what it does.

    #{Enum.join(Enum.sort(unclassified), "\n")}
    """
  end

  test "the table names no event that no longer exists" do
    current = MapSet.new(events())

    stale =
      for {module, classes} <- Events.table(),
          {class, events} <- classes,
          event <- events,
          {module, event} not in current,
          not dispatched?(module, event),
          do: "#{module}: #{event} (#{class})"

    assert stale == [], "Remove these from BrandoAdmin.Authorization.Events:\n#{Enum.join(Enum.sort(stale), "\n")}"
  end

  defp dispatched?(module, event) do
    case @dispatched do
      %{^module => pattern} -> event =~ pattern
      _ -> false
    end
  end

  test "no event has two classes" do
    twice =
      for {module, classes} <- Events.table(),
          {event, count} <- classes |> Keyword.values() |> List.flatten() |> Enum.frequencies(),
          count > 1,
          do: "#{module}: #{event}"

    assert twice == []
  end

  test "every admin LiveComponent with events is guarded" do
    {:ok, modules} = :application.get_key(:brando, :modules)

    unguarded =
      for module <- modules,
          Code.ensure_loaded?(module),
          Phoenix.LiveComponent in behaviours(module),
          function_exported?(module, :handle_event, 3),
          inspect(module) not in @not_admin,
          not function_exported?(module, :__event_guard__, 0),
          do: inspect(module)

    assert unguarded == [], "Use `use BrandoAdmin, :live_component`: #{inspect(unguarded)}"
  end

  # The admin's LiveViews get the hook from their live_session, or by themselves.
  # These are not the admin's: the sign-in steps run before there is an account
  # to authorize (`UserTwoFactorLive` too: the password was right, the session
  # is not yet), and the upload manager is a sticky view with its own checks.
  @outside_admin ~w(
    BrandoAdmin.UploadManager
    BrandoAdmin.UserForgotPasswordLive
    BrandoAdmin.UserLoginLive
    BrandoAdmin.UserLogoutLive
    BrandoAdmin.UserResetPasswordLive
    BrandoAdmin.UserTwoFactorLive
    BrandoAdmin.UserTwoFactorSetupLive
  )

  # A view with no events of its own counts: its components' guards read the
  # actor this hook sets.
  test "every admin LiveView runs under the authorization hook" do
    {:ok, modules} = :application.get_key(:brando, :modules)
    routed = routed_under_authorization()

    unguarded =
      for module <- modules,
          Code.ensure_loaded?(module),
          Phoenix.LiveView in behaviours(module),
          shipped?(module),
          inspect(module) not in @outside_admin,
          module not in routed,
          not own_authorization_hook?(module),
          do: inspect(module)

    assert unguarded == [], "No BrandoAdmin.Authorization on_mount: #{inspect(unguarded)}"
  end

  # The application's modules hold test/support too, whose views a test mounts as it likes.
  defp shipped?(module) do
    module.module_info(:compile)[:source] |> to_string() |> Path.relative_to_cwd() |> String.starts_with?("lib/")
  end

  defp behaviours(module) do
    module.module_info(:attributes)
    |> Keyword.get_values(:behaviour)
    |> List.flatten()
  end

  defp own_authorization_hook?(module) do
    %{lifecycle: %{mount: hooks}} = module.__live__()
    Enum.any?(hooks, &match?(%{id: {BrandoAdmin.Authorization, _}}, &1))
  end

  defp routed_under_authorization do
    source = File.read!("lib/brando/router.ex")

    # Each live_session's block, for those that mount BrandoAdmin.Authorization.
    source
    |> String.split("live_session ")
    |> Enum.filter(&(&1 =~ "{BrandoAdmin.Authorization, :default}"))
    |> Enum.flat_map(fn session ->
      ~r/live "[^"]*",\s+(BrandoAdmin[\w.]+)/
      |> Regex.scan(session)
      |> Enum.map(fn [_, name] -> Module.concat([name]) end)
    end)
    |> MapSet.new()
  end

  describe "at runtime" do
    test "an unclassified event of an unknown module is a write" do
      assert Events.class(Unknown.Module, "anything") == :write
      assert Events.component_class(Unknown.Module, "anything") == :write
    end

    test "a module may declare its own read-only events" do
      defmodule ProjectView do
        def __read_only_events__, do: ~w(open_tab)
      end

      assert Events.class(ProjectView, "open_tab") == :read
      assert Events.class(ProjectView, "store") == :write
    end

    test "a hook's read-only event opens no component event of that name" do
      assert Events.class(Unknown.Module, "edit_entry") == :read
      assert Events.component_class(Unknown.Module, "edit_entry") == :write
    end

    test "a picker has its helpers' events" do
      assert Events.component_class(BrandoAdmin.Components.ImagePicker, "go_root") == :read
      assert Events.component_class(BrandoAdmin.Components.ImagePicker, "create_folder") == :write
    end

    test "a write is refused to a :user only, a read to nobody" do
      assert Events.refused_to_role?(BrandoAdmin.Sites.CacheLive, "empty_caches", :user)
      refute Events.refused_to_role?(BrandoAdmin.Sites.CacheLive, "empty_caches", :editor)
      refute Events.refused_to_role?(BrandoAdmin.Sites.UtilsLive, "refresh", :user)
    end

    test "no actor, nothing refused: no legacy admin view mounted in this process" do
      refute Events.component_refused?(BrandoAdmin.Components.ImagePicker, "create_folder")
    end
  end
end
