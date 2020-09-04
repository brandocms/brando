defmodule Brando.Generators.GraphQL do
  def before_copy(binding) do
    binding
    |> add_gql_query_fields()
    |> add_gql_types()
    |> add_gql_inputs()
  end

  def after_copy(binding) do
    add_to_files(binding)
  end

  defp add_to_files(binding) do
    ## GQL SCHEMA

    Mix.Brando.add_to_file(
      "lib/#{Mix.Brando.otp_app()}/graphql/schema.ex",
      "dataloader",
      "  |> Dataloader.add_source(#{binding[:base]}.#{binding[:domain]}, #{binding[:base]}.#{
        binding[:domain]
      }.data())",
      singular: true
    )

    Mix.Brando.add_to_file(
      "lib/#{Mix.Brando.otp_app()}/graphql/schema.ex",
      "queries",
      "import_fields :#{binding[:singular]}_queries"
    )

    Mix.Brando.add_to_file(
      "lib/#{Mix.Brando.otp_app()}/graphql/schema.ex",
      "mutations",
      "import_fields :#{binding[:singular]}_mutations"
    )

    ## GQL TYPES
    Mix.Brando.add_to_file(
      "lib/#{Mix.Brando.otp_app()}/graphql/schema/types.ex",
      "types",
      "import_types #{binding[:base]}.Schema.Types.#{binding[:alias]}"
    )

    binding
  end

  defp add_gql_types(binding) do
    # this is for GraphQL type objects
    attrs = Keyword.get(binding, :attrs) ++ Keyword.get(binding, :assocs)

    gql_types =
      Enum.map(attrs, fn
        {k, {:references, _}} ->
          {k, ~s<\n    field #{inspect(k)}_id, :id>}

        {k, {:array, _}} ->
          {k, ~s<field #{inspect(k)}, list_of\(:string\)>}

        {k, :integer} ->
          {k, ~s<field #{inspect(k)}, :integer>}

        {k, :boolean} ->
          {k, ~s<field #{inspect(k)}, :boolean>}

        {k, :string} ->
          {k, ~s<field #{inspect(k)}, :string>}

        {k, :text} ->
          {k, ~s<field #{inspect(k)}, :string>}

        {k, :date} ->
          {k, ~s<field #{inspect(k)}, :date>}

        {k, :time} ->
          {k, ~s<field #{inspect(k)}, :time>}

        {k, :datetime} ->
          {k, ~s<field #{inspect(k)}, :time>}

        {k, :file} ->
          {k, ~s<field #{inspect(k)}, :file_type>}

        {k, :image} ->
          {k, ~s<field #{inspect(k)}, :image_type>}

        {k, :villain} ->
          fields =
            case k do
              :data ->
                [:data, :html]

              _ ->
                [String.to_atom(to_string(k) <> "_data"), String.to_atom(to_string(k) <> "_html")]
            end

          {k,
           ~s<field #{inspect(Enum.at(fields, 0))}, :json\n    field #{
             inspect(Enum.at(fields, 1))
           }, :string>}

        {k, :gallery} ->
          {k,
           ~s<field #{inspect(k)}_id, :id\n    field #{inspect(k)}, :image_series, resolve: dataloader(Brando.Images)>}

        {k, :status} ->
          {k, ~s<field :status, :string>}

        {k, _} ->
          {k, ~s<field #{inspect(k)}, :string>}
      end)

    Keyword.put(binding, :gql_types, gql_types)
  end

  defp add_gql_inputs(binding) do
    # this is for GraphQL input objects
    attrs = Keyword.get(binding, :attrs) ++ Keyword.get(binding, :assocs)

    gql_inputs =
      Enum.map(attrs, fn
        {k, {:references, _}} ->
          {k, ~s<field #{inspect(k)}_id, :id>}

        {k, {:array, _}} ->
          {k, nil, nil}

        {k, :integer} ->
          {k, ~s<field #{inspect(k)}, :integer>}

        {k, :boolean} ->
          {k, ~s<field #{inspect(k)}, :boolean>}

        {k, :string} ->
          {k, ~s<field #{inspect(k)}, :string>}

        {k, :text} ->
          {k, ~s<field #{inspect(k)}, :string>}

        {k, :date} ->
          {k, ~s<field #{inspect(k)}, :date>}

        {k, :time} ->
          {k, ~s<field #{inspect(k)}, :time>}

        {k, :datetime} ->
          {k, ~s<field #{inspect(k)}, :time>}

        {k, :image} ->
          {k, ~s<field #{inspect(k)}, :upload_or_image>}

        {k, :file} ->
          {k, ~s<field #{inspect(k)}, :upload>}

        {k, :villain} ->
          k = (k == :data && :data) || String.to_atom(Atom.to_string(k) <> "_data")
          {k, ~s<field #{inspect(k)}, :json>}

        {k, :status} ->
          {k, ~s<field #{inspect(k)}, :string>}

        {k, :gallery} ->
          {k, ~s<field #{inspect(k)}_id, :id\n    field #{inspect(k)}, :image_series_upload>}

        {k, _} ->
          {k, ~s<field #{inspect(k)}, :string>}
      end)

    Keyword.put(binding, :gql_inputs, gql_inputs)
  end

  defp add_gql_query_fields(binding) do
    fields = Keyword.get(binding, :attrs) ++ Keyword.get(binding, :assocs)
    # this is for GraphQL query fields
    gql_query_fields =
      fields
      |> Enum.map(fn {k, v} -> {Atom.to_string(k), v} end)
      |> Enum.map(fn
        {k, {:array, _}} ->
          {k, Recase.to_camel(k)}

        {k, :gallery} ->
          {k, ~s<#{k}Id>}

        {k, :file} ->
          file_code = "#{Recase.to_camel(k)} {\n    url\n  }"
          {k, file_code}

        {k, :image} ->
          image_code =
            "#{Recase.to_camel(k)} {\n    thumb: url(size: \"original\")\n    xlarge: url(size: \"xlarge\")\n    focal\n  }"

          {k, image_code}

        {k, :villain} ->
          case k do
            "data" ->
              {k, k}

            _ ->
              {k, ~s<#{k}Data>}
          end

        {k, {:references, _}} ->
          {k, ~s<#{Recase.to_camel(k)}Id>}

        {k, _} ->
          {k, Recase.to_camel(k)}
      end)

    Keyword.put(binding, :gql_query_fields, gql_query_fields)
  end
end
