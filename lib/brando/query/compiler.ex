defmodule Brando.Query.Compiler do
  @moduledoc """
  Compiles query and mutation functions into Brando contexts without depending on
  the runtime query engine.

  Use this module in context definitions:

      use Brando.Query.Compiler
  """

  @default_callback {:fn, [], [{:->, [], [[{:entry, [], nil}], {:ok, {:entry, [], nil}}]}]}

  @doc "Imports the focused query compiler and query helper macros."
  defmacro __using__(_opts), do: build_use()

  @doc "Defines list or single-entry query functions for a Blueprint schema."
  defmacro query(kind, module, do: block) when kind in [:list, :single] do
    build_query(kind, module, block, __CALLER__)
  end

  @doc "Defines generated create, update, delete, or duplicate mutation functions."
  defmacro mutation(operation, module) when operation in [:create, :update, :delete, :duplicate] do
    build_mutation(operation, module, nil, __CALLER__)
  end

  defmacro mutation(operation, module, do: callback)
           when operation in [:create, :update, :delete] do
    build_mutation(operation, module, callback, __CALLER__)
  end

  @doc "Defines a context's list-query filter reducer."
  defmacro filters(module, do: block), do: build_reducer(:filters, module, block, __CALLER__)

  @doc "Defines a context's single-query match reducer."
  defmacro matches(module, do: block), do: build_reducer(:matches, module, block, __CALLER__)

  @doc "Builds an Ecto fragment that matches any JSON object value case-insensitively."
  defmacro jsonb_contains_any_value_ilike(field, value), do: build_jsonb_contains(field, value)

  @doc "Builds the imports used by the focused and compatibility `use` macros."
  def build_use do
    quote do
      import Brando.Query.Compiler
      import Brando.Query.Helpers
    end
  end

  @doc "Builds a generated list or single-entry query for compatibility macros."
  def build_query(kind, module, block, caller) do
    module = expand_module(module, caller, {:query, 3})

    case kind do
      :list -> query_list(module, block)
      :single -> query_single(module, block)
    end
  end

  @doc "Builds a generated context mutation for compatibility macros."
  def build_mutation(operation, {module, opts}, callback, caller) do
    module = expand_module(module, caller, {:mutation, 2})
    build_mutation_ast(operation, {module, opts}, callback)
  end

  def build_mutation(operation, module, callback, caller) do
    module = expand_module(module, caller, {:mutation, 2})
    build_mutation_ast(operation, module, callback)
  end

  @doc "Builds a generated filter or match reducer for compatibility macros."
  def build_reducer(kind, module, block, caller) do
    module = expand_module(module, caller, {kind, 2})

    case kind do
      :filters -> filter_query(module, block)
      :matches -> match_query(module, block)
    end
  end

  @doc "Builds the JSONB value-matching fragment for compatibility macros."
  def build_jsonb_contains(field, value) do
    quote do
      fragment(
        "EXISTS (SELECT 1 FROM jsonb_each_text(?) AS t(key, value) WHERE LOWER(t.value) LIKE LOWER(?))",
        unquote(field),
        ^("%" <> unquote(value) <> "%")
      )
    end
  end

  defp expand_module(module, caller, function) do
    Macro.expand_literals(module, %{caller | function: function})
  end

  defp build_mutation_ast(:create, module, callback), do: mutation_create(module, callback)
  defp build_mutation_ast(:update, module, callback), do: mutation_update(module, callback)
  defp build_mutation_ast(:delete, module, callback), do: mutation_delete(module, callback)
  defp build_mutation_ast(:duplicate, module, nil), do: mutation_duplicate(module)

  defp mutation_engine_ast, do: quote(do: Brando.Query.Mutations)

  defp query_list(module, block) do
    source = module.__schema__(:source)
    pluralized_schema = module.__naming__().plural

    quote do
      def unquote(:"list_#{pluralized_schema}!")(args \\ %{}, stream \\ false) do
        {:ok, entries} = unquote(:"list_#{pluralized_schema}")(args, stream)
        entries
      end

      def unquote(:"list_#{pluralized_schema}")(args \\ %{}, stream \\ false) do
        initial_query = unquote(block).(unquote(module))

        Brando.Query.handle_list_query(
          __MODULE__,
          {:list, unquote(source), args},
          args,
          initial_query,
          unquote(module),
          stream
        )
      end
    end
  end

  defp query_single(module, block) do
    source = module.__schema__(:source)
    singular_schema = module.__naming__().singular
    singular_schema_atom = String.to_atom(singular_schema)

    quote do
      unquote(query_single_safe(module, block, source, singular_schema, singular_schema_atom))
      unquote(query_single_bang(module, block, singular_schema))
    end
  end

  defp query_single_safe(module, block, source, singular_schema, singular_schema_atom) do
    quote do
      @spec unquote(:"get_#{singular_schema}")(nil | integer | binary | map()) ::
              {:ok, any} | {:error, {unquote(singular_schema_atom), :not_found}}
      def unquote(:"get_#{singular_schema}")(nil),
        do: {:error, {unquote(singular_schema_atom), :not_found}}

      def unquote(:"get_#{singular_schema}")(id) when is_binary(id) or is_integer(id) do
        query = unquote(block).(unquote(module)) |> where([t], t.id == ^id)

        case Brando.Repo.one(query) do
          nil -> {:error, {unquote(singular_schema_atom), :not_found}}
          result -> {:ok, result}
        end
      end

      def unquote(:"get_#{singular_schema}")(args) when is_map(args) do
        Brando.Query.handle_single_query(
          __MODULE__,
          {:single, unquote(source), args},
          args,
          unquote(module),
          unquote(block),
          unquote(singular_schema_atom)
        )
      end
    end
  end

  defp query_single_bang(module, block, singular_schema) do
    quote do
      @spec unquote(:"get_#{singular_schema}!")(integer | binary | map()) :: any | no_return
      def unquote(:"get_#{singular_schema}!")(id) when is_binary(id) or is_integer(id) do
        unquote(block).(unquote(module))
        |> where([t], t.id == ^id)
        |> Brando.Repo.one!()
      end

      def unquote(:"get_#{singular_schema}!")(args) when is_map(args) do
        __MODULE__
        |> Brando.Query.run_single_query_reducer(args, unquote(module))
        |> unquote(block).()
        |> limit(1)
        |> Brando.Repo.one!()
      end
    end
  end

  defp filter_query(module, block) do
    quote do
      def with_filter(query, unquote(module), filter) do
        Enum.reduce(filter, query, unquote(block))
      rescue
        _e in FunctionClauseError ->
          reraise Brando.Exception.QueryFilterClauseError,
                  [
                    message: """


                    Could not find a matching query filter clause

                    Filter: #{inspect(filter)}
                    Context: #{inspect(unquote(module).__modules__().context)}
                    """
                  ],
                  __STACKTRACE__

        e ->
          reraise e, __STACKTRACE__
      end
    end
  end

  defp match_query(module, block) do
    quote do
      def with_match(query, unquote(module), match) do
        Enum.reduce(match, query, unquote(block))
      rescue
        _e in FunctionClauseError ->
          reraise Brando.Exception.QueryMatchClauseError,
                  [
                    message: """


                    Could not find a matching query match clause

                    Matches: #{inspect(match)}
                    Context: #{inspect(unquote(module).__modules__().context)}
                    """
                  ],
                  __STACKTRACE__

        e ->
          reraise e, __STACKTRACE__
      end
    end
  end

  defp mutation_create(module, callback_block)

  defp mutation_create({module, opts}, callback_block) do
    singular_schema = module.__naming__().singular

    callback_block = callback_block || @default_callback
    do_mutation_create(module, singular_schema, callback_block, opts)
  end

  defp mutation_create(module, callback_block) do
    singular_schema = module.__naming__().singular

    callback_block = callback_block || @default_callback
    do_mutation_create(module, singular_schema, callback_block)
  end

  defp do_mutation_create(module, singular_schema, callback_block, opts \\ []) do
    mutation_engine = mutation_engine_ast()

    quote generated: true do
      def unquote(:"create_#{singular_schema}")(params, user, opts \\ [])

      def unquote(:"create_#{singular_schema}")(%Ecto.Changeset{} = changeset, user, opts) do
        unquote(mutation_engine).create_with_changeset(
          unquote(module),
          changeset,
          user,
          unquote(callback_block),
          opts ++ unquote(opts)
        )
      end

      def unquote(:"create_#{singular_schema}")(params, user, opts) when is_map(params) do
        unquote(mutation_engine).create(
          unquote(module),
          params,
          user,
          unquote(callback_block),
          opts ++ unquote(opts)
        )
      end
    end
  end

  defp mutation_update(module, callback_block)

  defp mutation_update({module, opts}, callback_block) do
    singular_schema = module.__naming__().singular
    callback_block = callback_block || @default_callback
    do_mutation_update(module, singular_schema, callback_block, opts)
  end

  defp mutation_update(module, callback_block) do
    singular_schema = module.__naming__().singular
    callback_block = callback_block || @default_callback
    do_mutation_update(module, singular_schema, callback_block)
  end

  defp do_mutation_update(module, singular_schema, callback_block, opts \\ []) do
    preloads = Keyword.get(opts, :preload)
    mutation_engine = mutation_engine_ast()

    quote do
      def unquote(:"update_#{singular_schema}")(%Ecto.Changeset{} = changeset, user) do
        unquote(mutation_engine).update_with_changeset(
          unquote(module),
          changeset,
          user,
          unquote(preloads),
          unquote(callback_block),
          []
        )
      end

      def unquote(:"update_#{singular_schema}")(%Ecto.Changeset{} = changeset, user, opts) do
        unquote(mutation_engine).update_with_changeset(
          unquote(module),
          changeset,
          user,
          unquote(preloads),
          unquote(callback_block),
          opts
        )
      end

      def unquote(:"update_#{singular_schema}")(%{id: id}, params, user) do
        unquote(mutation_engine).update(
          __MODULE__,
          unquote(module),
          unquote(singular_schema),
          id,
          params,
          user: user,
          preloads: unquote(preloads),
          callback: unquote(callback_block),
          changeset: nil,
          notify?: true
        )
      end

      def unquote(:"update_#{singular_schema}")(%{id: id}, params, user, opts) do
        unquote(mutation_engine).update(
          __MODULE__,
          unquote(module),
          unquote(singular_schema),
          id,
          params,
          user: user,
          preloads: unquote(preloads),
          callback: unquote(callback_block),
          changeset: Keyword.get(opts, :changeset),
          notify?: Keyword.get(opts, :show_notification, true)
        )
      end

      def unquote(:"update_#{singular_schema}")(id, params, user) do
        unquote(mutation_engine).update(
          __MODULE__,
          unquote(module),
          unquote(singular_schema),
          id,
          params,
          user: user,
          preloads: unquote(preloads),
          callback: unquote(callback_block),
          changeset: nil,
          notify?: true
        )
      end

      def unquote(:"update_#{singular_schema}")(id, params, user, opts) do
        unquote(mutation_engine).update(
          __MODULE__,
          unquote(module),
          unquote(singular_schema),
          id,
          params,
          user: user,
          preloads: unquote(preloads),
          callback: unquote(callback_block),
          changeset: Keyword.get(opts, :changeset),
          notify?: Keyword.get(opts, :show_notification, true)
        )
      end
    end
  end

  defp mutation_duplicate({module, opts}), do: do_mutation_duplicate(module, opts)
  defp mutation_duplicate(module), do: do_mutation_duplicate(module, [])

  defp do_mutation_duplicate(module, opts) do
    singular_schema = module.__naming__().singular
    mutation_engine = mutation_engine_ast()

    quote do
      def unquote(:"duplicate_#{singular_schema}")(id, user, override_opts \\ []) do
        unquote(mutation_engine).duplicate(
          __MODULE__,
          unquote(module),
          unquote(singular_schema),
          id,
          user: user,
          duplicate_opts: unquote(opts),
          override_opts: override_opts
        )
      end
    end
  end

  defp mutation_delete(module, callback_block)

  defp mutation_delete({module, opts}, callback_block) do
    singular_schema = module.__naming__().singular
    callback_block = callback_block || @default_callback
    do_mutation_delete(module, singular_schema, callback_block, opts)
  end

  defp mutation_delete(module, callback_block) do
    singular_schema = module.__naming__().singular
    callback_block = callback_block || @default_callback

    do_mutation_delete(module, singular_schema, callback_block)
  end

  defp do_mutation_delete(module, singular_schema, callback_block, opts \\ []) do
    preloads = Keyword.get(opts, :preload)
    mutation_engine = mutation_engine_ast()

    quote do
      def unquote(:"delete_#{singular_schema}")(id, user \\ :system) do
        unquote(mutation_engine).delete(
          __MODULE__,
          unquote(module),
          unquote(singular_schema),
          id,
          user: user,
          preloads: unquote(preloads),
          callback: unquote(callback_block)
        )
      end
    end
  end
end
