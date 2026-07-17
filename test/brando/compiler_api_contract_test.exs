defmodule Brando.CompilerAPIContractTest do
  use ExUnit.Case, async: true

  @query_macros [
    __using__: 1,
    filters: 2,
    jsonb_contains_any_value_ilike: 2,
    matches: 2,
    mutation: 2,
    mutation: 3,
    query: 3
  ]

  @query_functions [
    delete: 1,
    get_entry: 2,
    handle_list_query: 5,
    handle_list_query: 6,
    handle_single_query: 6,
    hash_query: 1,
    insert: 1,
    insert: 2,
    maybe_build_pagination_meta: 2,
    order_string_to_list: 1,
    run_list_query_reducer: 4,
    run_single_query_reducer: 3,
    sanitize_ilike_pattern: 1,
    try_cache: 2,
    update: 1,
    update: 2,
    with_exclude_language: 2,
    with_join: 2,
    with_language: 2,
    with_order: 2,
    with_preload: 2,
    with_select: 2,
    with_status: 2
  ]

  test "Brando.Query retains its public macro and runtime API" do
    assert_exports(Brando.Query, @query_macros, &macro_exported?/3)
    assert_exports(Brando.Query, @query_functions, &function_exported?/3)
  end

  test "admin LiveView setup remains available through the public modules" do
    assert Code.ensure_loaded?(BrandoAdmin.LiveView.Form)
    assert macro_exported?(BrandoAdmin.LiveView.Form, :__using__, 1)
    assert function_exported?(BrandoAdmin.LiveView.Form, :on_mount, 4)

    assert Code.ensure_loaded?(BrandoAdmin.LiveView.Listing)
    assert macro_exported?(BrandoAdmin.LiveView.Listing, :__using__, 1)
    assert function_exported?(BrandoAdmin.LiveView.Listing, :hooks, 4)
    assert function_exported?(BrandoAdmin.LiveView.Listing, :update_list_entries, 1)
  end

  test "focused compiler modules remain compatible with early adopters" do
    assert_exports(Brando.Query.Compiler, @query_macros, &macro_exported?/3)

    assert Code.ensure_loaded?(BrandoAdmin.LiveView.Form.Compiler)
    assert macro_exported?(BrandoAdmin.LiveView.Form.Compiler, :__using__, 1)

    assert Code.ensure_loaded?(BrandoAdmin.LiveView.Listing.Compiler)
    assert macro_exported?(BrandoAdmin.LiveView.Listing.Compiler, :__using__, 1)
  end

  defp assert_exports(module, exports, predicate) do
    assert Code.ensure_loaded?(module)

    Enum.each(exports, fn {name, arity} ->
      assert predicate.(module, name, arity),
             "expected #{inspect(module)} to export #{name}/#{arity}"
    end)
  end
end
