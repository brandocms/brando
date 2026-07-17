defmodule Brando.Blueprint.SecondaryVerifier.Listings do
  @moduledoc false

  alias Brando.Blueprint.SecondaryVerifier.Support
  alias Spark.Dsl.Verifier

  @order_directions [
    :asc,
    :asc_nulls_first,
    :asc_nulls_last,
    :desc,
    :desc_nulls_first,
    :desc_nulls_last
  ]
  @order_direction_pattern Enum.map_join(@order_directions, "|", &Atom.to_string/1)
  @order_pattern Regex.compile!("^(?:#{@order_direction_pattern}) [a-z][a-z0-9_]*(?:\\.[a-z][a-z0-9_]*)?$")
  @parameter_key_pattern ~r/^[a-z][a-z0-9_]*$/

  @doc false
  def verify(dsl_state) do
    listings = Verifier.get_entities(dsl_state, [:listings])
    listing_names = MapSet.new(listings, & &1.name)

    Support.validate_entities(listings, &verify_listing(dsl_state, listing_names, &1))
  end

  defp verify_listing(dsl_state, listing_names, listing) do
    path = [:listings, listing.name]

    with :ok <- Support.verify_key(dsl_state, path, listing, "listing", listing.name),
         :ok <- verify_listing_limit(dsl_state, path, listing),
         :ok <- verify_listing_query(dsl_state, path, listing),
         :ok <- verify_unique_listing_entities(dsl_state, listing),
         :ok <- Support.validate_entities(listing.filters, &verify_filter(dsl_state, listing, &1)),
         :ok <- Support.validate_entities(listing.sorts, &verify_sort(dsl_state, listing, &1)),
         :ok <- Support.validate_entities(listing.actions, &verify_action(dsl_state, listing, :actions, &1)),
         :ok <-
           Support.validate_entities(
             listing.selection_actions,
             &verify_action(dsl_state, listing, :selection_actions, &1)
           ),
         :ok <- Support.validate_entities(listing.exports, &verify_export(dsl_state, listing, &1)) do
      Support.validate_entities(
        listing.child_listings,
        &verify_child_listing(dsl_state, listing, listing_names, &1)
      )
    end
  end

  defp verify_listing_limit(_dsl_state, _path, %{limit: limit})
       when is_integer(limit) and limit >= 0,
       do: :ok

  defp verify_listing_limit(dsl_state, path, listing) do
    Support.error(dsl_state, path, listing, "listing limit must be zero or a positive integer")
  end

  defp verify_listing_query(_dsl_state, _path, %{query: %{filter: filters}}) when is_map(filters), do: :ok

  defp verify_listing_query(_dsl_state, _path, %{query: query}) when not is_map_key(query, :filter), do: :ok

  defp verify_listing_query(dsl_state, path, listing) do
    Support.error(dsl_state, path, listing, "listing query `:filter` must be a map")
  end

  defp verify_unique_listing_entities(dsl_state, listing) do
    checks = [
      {:filters, listing.filters, & &1.key},
      {:sorts, listing.sorts, & &1.key},
      {:exports, listing.exports, & &1.name},
      {:child_listings, listing.child_listings, & &1.name},
      {:child_listing_schemas, listing.child_listings, & &1.schema}
    ]

    Enum.reduce_while(checks, :ok, fn {section, entities, key_fun}, :ok ->
      case Support.find_duplicate(entities, key_fun) do
        nil ->
          {:cont, :ok}

        duplicate ->
          key = key_fun.(duplicate)
          entity_name = section |> Atom.to_string() |> String.trim_trailing("s")

          {:halt,
           Support.error(
             dsl_state,
             [:listings, listing.name, section, key],
             duplicate,
             "listing #{inspect(listing.name)} declares duplicate #{entity_name} #{inspect(key)}"
           )}
      end
    end)
  end

  defp verify_filter(dsl_state, listing, filter) do
    path = [:listings, listing.name, :filters, filter.key]

    with :ok <- Support.verify_non_empty_string(dsl_state, path, filter, "filter label", filter.label),
         :ok <- verify_parameter_key(dsl_state, path, filter),
         :ok <- verify_filter_options(dsl_state, path, filter) do
      verify_filter_default(dsl_state, path, filter)
    end
  end

  defp verify_parameter_key(dsl_state, path, filter) do
    if is_binary(filter.key) and Regex.match?(@parameter_key_pattern, filter.key) do
      :ok
    else
      Support.error(dsl_state, path, filter, "filter key must be a snake_case URL/query parameter")
    end
  end

  defp verify_filter_options(dsl_state, path, %{type: :select, options: options} = filter) do
    cond do
      is_function(options, 1) ->
        :ok

      is_list(options) and options != [] ->
        with :ok <- verify_unique_option_values(dsl_state, path, filter) do
          Support.validate_entities(options, &verify_option(dsl_state, path, &1))
        end

      true ->
        Support.error(
          dsl_state,
          path,
          filter,
          "select filters require static options or an arity-one options callback"
        )
    end
  end

  defp verify_filter_options(dsl_state, path, %{options: options} = filter) do
    if options in [nil, []] do
      :ok
    else
      Support.error(dsl_state, path, filter, "only select filters accept options")
    end
  end

  defp verify_unique_option_values(dsl_state, path, filter) do
    case Support.find_duplicate(filter.options, & &1.value) do
      nil -> :ok
      option -> Support.error(dsl_state, path ++ [:options], option, "select filter option values must be unique")
    end
  end

  defp verify_option(dsl_state, path, option) do
    Support.verify_non_empty_string(dsl_state, path ++ [:options], option, "select option label", option.label)
  end

  defp verify_filter_default(_dsl_state, _path, %{type: :text, default: default})
       when is_nil(default) or is_binary(default),
       do: :ok

  defp verify_filter_default(_dsl_state, _path, %{type: :boolean, default: default})
       when is_nil(default) or is_boolean(default),
       do: :ok

  defp verify_filter_default(dsl_state, path, %{type: :select, default: default} = filter)
       when is_nil(default) or is_binary(default) do
    if is_function(filter.options, 1) or is_nil(default) or Enum.any?(filter.options, &(&1.value == default)) do
      :ok
    else
      Support.error(dsl_state, path, filter, "select filter default must match one of its static option values")
    end
  end

  defp verify_filter_default(dsl_state, path, filter) do
    Support.error(dsl_state, path, filter, "filter default does not match filter type #{inspect(filter.type)}")
  end

  defp verify_sort(dsl_state, listing, sort) do
    path = [:listings, listing.name, :sorts, sort.key]

    with :ok <- Support.verify_key(dsl_state, path, sort, "sort", sort.key),
         :ok <- Support.verify_non_empty_string(dsl_state, path, sort, "sort label", sort.label) do
      verify_order(dsl_state, path, sort)
    end
  end

  defp verify_order(dsl_state, path, %{order: order} = sort) when is_binary(order) do
    order_parts = String.split(order, ",", trim: true)

    if order_parts != [] and Enum.all?(order_parts, &Regex.match?(@order_pattern, String.trim(&1))) do
      :ok
    else
      invalid_order(dsl_state, path, sort)
    end
  end

  defp verify_order(dsl_state, path, %{order: order} = sort) when is_list(order) and order != [] do
    if Enum.all?(order, &valid_order_term?/1) do
      :ok
    else
      invalid_order(dsl_state, path, sort)
    end
  end

  defp verify_order(dsl_state, path, sort), do: invalid_order(dsl_state, path, sort)

  defp invalid_order(dsl_state, path, sort) do
    Support.error(
      dsl_state,
      path,
      sort,
      "sort order must be a non-empty order string or list of `{direction, field}` tuples"
    )
  end

  defp valid_order_term?({direction, field}) when direction in @order_directions and is_atom(field), do: true

  defp valid_order_term?({direction, {association, field}})
       when direction in @order_directions and is_atom(association) and is_atom(field),
       do: true

  defp valid_order_term?(_term), do: false

  defp verify_action(dsl_state, listing, section, action) do
    path = [:listings, listing.name, section]

    with :ok <- Support.verify_non_empty_string(dsl_state, path, action, "action label", action.label),
         :ok <- verify_event(dsl_state, path, action) do
      verify_confirmation(dsl_state, path, action)
    end
  end

  defp verify_event(_dsl_state, _path, %{event: %Phoenix.LiveView.JS{}}), do: :ok
  defp verify_event(_dsl_state, _path, %{event: event}) when is_binary(event) and event != "", do: :ok

  defp verify_event(dsl_state, path, action) do
    Support.error(
      dsl_state,
      path,
      action,
      "listing actions require a non-empty event or `Phoenix.LiveView.JS` command"
    )
  end

  defp verify_confirmation(_dsl_state, _path, %{confirm: false}), do: :ok
  defp verify_confirmation(_dsl_state, _path, %{confirm: nil}), do: :ok

  defp verify_confirmation(_dsl_state, _path, %{confirm: confirm})
       when is_binary(confirm) and confirm != "",
       do: :ok

  defp verify_confirmation(dsl_state, path, action) do
    Support.error(dsl_state, path, action, "action confirmation must be false or a non-empty message")
  end

  defp verify_export(dsl_state, listing, export) do
    path = [:listings, listing.name, :exports, export.name]

    with :ok <- Support.verify_key(dsl_state, path, export, "export", export.name),
         :ok <- Support.verify_non_empty_string(dsl_state, path, export, "export label", export.label),
         :ok <- verify_export_type(dsl_state, path, export) do
      verify_export_fields(dsl_state, path, export)
    end
  end

  defp verify_export_type(_dsl_state, _path, %{type: :csv}), do: :ok

  defp verify_export_type(dsl_state, path, export) do
    Support.error(
      dsl_state,
      path,
      export,
      "unsupported export type #{inspect(export.type)}; only `:csv` is implemented"
    )
  end

  defp verify_export_fields(dsl_state, path, export) do
    fields = export.fields

    if is_list(fields) and fields != [] and length(fields) == length(Enum.uniq(fields)) do
      :ok
    else
      Support.error(dsl_state, path, export, "export fields must be a non-empty list without duplicates")
    end
  end

  defp verify_child_listing(dsl_state, listing, listing_names, child_listing) do
    path = [:listings, listing.name, :child_listings, child_listing.name]

    with :ok <- Support.verify_key(dsl_state, path, child_listing, "child listing", child_listing.name),
         :ok <- verify_child_listing_schema(dsl_state, path, child_listing) do
      if MapSet.member?(listing_names, child_listing.name) do
        :ok
      else
        Support.error(
          dsl_state,
          path,
          child_listing,
          "child listing references undeclared listing #{inspect(child_listing.name)}"
        )
      end
    end
  end

  defp verify_child_listing_schema(_dsl_state, _path, %{schema: schema})
       when is_atom(schema) and schema not in [nil, false, true],
       do: :ok

  defp verify_child_listing_schema(dsl_state, path, child_listing) do
    Support.error(dsl_state, path, child_listing, "child listing schema must be a module atom")
  end
end
