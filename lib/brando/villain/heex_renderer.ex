defmodule Brando.Villain.HeexRenderer do
  @moduledoc """
  Compiles HEEx template strings into dynamic modules and renders them.

  Uses an ETS cache keyed by `{id, :erlang.phash2(code)}` to avoid
  recompilation when the template hasn't changed. The generated module name
  includes the code hash as well, so two cached code versions for the same
  content module cannot point at whichever version happened to compile last.
  """

  @ets_table :brando_heex_cache

  @doc """
  Initialize the ETS cache table. Called during application startup.
  """
  @spec init_cache :: :ok
  def init_cache do
    :ets.new(@ets_table, [:named_table, :public, :set, read_concurrency: true])
    :ok
  end

  @doc """
  Compile a HEEx template string into a dynamic module.

  The module is created as `Brando.DynamicTemplate.Module_<id>_<code_hash>`
  and defines a `render/1` function component that renders the given HEEx code.

  Returns the module atom.
  """
  @spec compile_module!(integer() | binary(), String.t()) :: module()
  def compile_module!(id, code_string) do
    module_name = module_name_for(id, code_string)
    preprocessed = preprocess_heex(code_string)

    # Purge if already exists to allow recompilation
    :code.purge(module_name)
    :code.delete(module_name)

    quoted =
      quote do
        use Phoenix.Component
        import Brando.Villain.Components

        def render(var!(assigns)) do
          unquote(
            Phoenix.LiveView.TagEngine.compile(preprocessed,
              tag_handler: Phoenix.LiveView.HTMLEngine,
              caller: __ENV__
            )
          )
        end
      end

    {:module, ^module_name, _binary, _} = Module.create(module_name, quoted, Macro.Env.location(__ENV__))

    module_name
  end

  @doc """
  Get a compiled module from cache or compile it if needed.

  Cache key is `{id, :erlang.phash2(code)}`, so a changed template
  triggers recompilation automatically.

  Returns the module atom.
  """
  @spec get_or_compile!(integer() | binary(), String.t()) :: module()
  def get_or_compile!(id, code_string) do
    hash = :erlang.phash2(code_string)
    key = {id, hash}

    case ets_lookup(key) do
      {:ok, module_name} ->
        module_name

      :miss ->
        module_name = compile_module!(id, code_string)
        :ets.insert(@ets_table, {key, module_name})
        module_name
    end
  end

  @doc """
  Compile (or fetch from cache) and render a HEEx template to an HTML string.

  Assigns are passed to the compiled `render/1` function component.
  """
  @spec render_to_string(integer() | binary(), String.t(), map()) :: String.t()
  def render_to_string(id, code_string, assigns) do
    module_name = get_or_compile!(id, code_string)
    assigns = Map.put(assigns, :__changed__, %{})

    module_name.render(assigns)
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
  end

  @doc """
  Invalidate all cached modules for a given id (any code hash).
  """
  @spec invalidate(integer() | binary()) :: :ok
  def invalidate(id) do
    :ets.match_delete(@ets_table, {{id, :_}, :_})
    :ok
  end

  @doc """
  Invalidate all cached modules.
  """
  @spec invalidate_all :: :ok
  def invalidate_all do
    :ets.delete_all_objects(@ets_table)
    :ok
  end

  @doc """
  Preprocess HEEx code to inject renderer-owned assigns into Villain component
  calls.

  This allows the `ref` component to receive admin context (refs_field, target, etc.)
  and `<.content />` to receive multi-module/container children transparently,
  without the template author needing to pass internal assigns explicitly.
  """
  def preprocess_heex(code_string) do
    code_string
    |> String.replace(
      ~r/<\.ref(?![^>]*\b_heex_ctx=)(?=\s|\/>)/,
      "<.ref _heex_ctx={@_heex_ctx}"
    )
    |> String.replace(
      ~r/<\.content(?![^>]*\bcontent=)(?=\s|\/>)/,
      "<.content content={@content}"
    )
  end

  defp module_name_for(id, code_string) do
    hash = :erlang.phash2(code_string)
    Module.concat(Brando.DynamicTemplate, "Module_#{id}_#{hash}")
  end

  defp ets_lookup(key) do
    case :ets.lookup(@ets_table, key) do
      [{^key, module_name}] -> {:ok, module_name}
      [] -> :miss
    end
  rescue
    ArgumentError -> :miss
  end
end
