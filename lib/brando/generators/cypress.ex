defmodule Brando.Generators.Cypress do
  def before_copy(binding) do
    binding
    |> add_cypress_fields()
  end

  def after_copy(binding) do
    add_to_files(binding)
  end

  defp add_to_files(binding) do
    ## Cypress / factory stuff
    Mix.Brando.add_to_file(
      "lib/#{Mix.Brando.otp_app()}/factory.ex",
      "aliases",
      "alias #{binding[:base]}.#{binding[:domain]}.#{binding[:alias]}"
    )

    factory_code =
      EEx.eval_file(
        Application.app_dir(
          :brando,
          "priv/templates/brando.gen/factory_function.eex"
        ),
        binding
      )

    Mix.Brando.add_to_file(
      "lib/#{Mix.Brando.otp_app()}/factory.ex",
      "functions",
      factory_code
    )

    binding
  end

  defp add_cypress_fields(binding) do
    attrs = Keyword.get(binding, :attrs)
    singular = Keyword.get(binding, :vue_singular)

    cypress_fields =
      Enum.map(attrs, fn
        {k, :boolean} ->
          {k, ["cy.get('##{singular}_#{k}_').clear().check()"]}

        {k, :text} ->
          {k, ["cy.get('##{singular}_#{k}_').clear().type('Default Text Value')"]}

        {k, :date} ->
          {k,
           [
             "cy.get('##{singular}_#{k}_').siblings('.form-control').click()",
             "cy.get('.today').click()"
           ]}

        {k, :time} ->
          {k,
           [
             "cy.get('##{singular}_#{k}_').siblings('.form-control').click()",
             "cy.get('.today').click()"
           ]}

        {k, :datetime} ->
          {k,
           [
             "cy.get('##{singular}_#{k}_').siblings('.form-control').click()",
             "cy.get('.today').click()"
           ]}

        {k, :image} ->
          {k,
           [
             "cy.fixture('jpeg.jpg', 'base64').then(fileContent => {",
             "  cy.get('##{singular}_#{k}_').upload({ fileContent, fileName: 'jpeg.jpg', mimeType: 'image/jpeg' })",
             "})"
           ]}

        {k, :file} ->
          {k,
           [
             "cy.fixture('example.json', 'base64').then(fileContent => {",
             "  cy.get('##{singular}_#{k}_').upload({ fileContent, fileName: 'example.json', mimeType: 'application/json' })",
             "})"
           ]}

        {k, :villain} ->
          {k,
           [
             "cy.get('.villain-editor-plus-inactive > a').click()",
             "cy.get('.villain-editor-plus-available-blocks > :nth-child(1)').click()",
             "cy.get('.ql-editor > p').click().type('This is a paragraph')"
           ]}

        {k, _} ->
          {k, ["cy.get('##{singular}_#{k}_').clear().type('Default value')"]}
      end)

    Keyword.put(binding, :cypress_fields, cypress_fields)
  end

  defp add_vue_defaults(binding) do
    attrs = Keyword.get(binding, :attrs)

    vue_defaults =
      Enum.map(attrs, fn
        {k, {:array, _}} ->
          {k, nil, nil}

        {k, :boolean} ->
          {k, "false"}

        {k, :text} ->
          {k, "''"}

        {k, :string} ->
          {k, "''"}

        {k, :villain} ->
          k = (k == :data && :data) || String.to_atom(Atom.to_string(k) <> "_data")
          {k, "null"}

        {k, _} ->
          {k, "null"}
      end)

    Keyword.put(binding, :vue_defaults, vue_defaults)
  end

  defp add_vue_locales(binding) do
    all_fields = Keyword.get(binding, :assocs) ++ Keyword.get(binding, :attrs)

    # this is for locale.js
    vue_locales =
      Enum.map(@locales, fn locale ->
        fields =
          Enum.map(all_fields, fn
            {k, {_, _}} ->
              string_key = to_string(k) <> "_id"

              %{
                field: string_key,
                label: String.capitalize(Atom.to_string(k)),
                placeholder: String.capitalize(Atom.to_string(k)),
                help_text: ""
              }

            {k, _} ->
              string_key = to_string(k)

              %{
                field: string_key,
                label: String.capitalize(string_key),
                placeholder: String.capitalize(string_key),
                help_text: ""
              }
          end)

        {locale, fields}
      end)
      |> Enum.into(%{})

    Keyword.put(binding, :vue_locales, vue_locales)
  end

  defp add_vue_form_queries(binding) do
    assocs = Keyword.get(binding, :assocs)

    if Enum.count(assocs) > 0 do
      queries =
        Enum.reduce(assocs, "", fn {_field, {:references, target}}, acc ->
          acc <>
            """
              #{target}: {
                  query: GET_#{String.upcase(Atom.to_string(target))}
                },
            """
        end)

      vue_form_queries = """
      apollo: {
        #{queries}
        },
      """

      Keyword.put(binding, :vue_form_queries, vue_form_queries)
    else
      Keyword.put(binding, :vue_form_queries, "")
    end
  end

  defp add_vue_inputs(binding) do
    # this is for vue components
    attrs = Keyword.get(binding, :attrs)
    assocs = Keyword.get(binding, :assocs)

    vue_assoc_inputs =
      Enum.map(assocs, fn
        {k, {:references, ref_target}} ->
          k = String.to_atom(Atom.to_string(k) <> "_id")
          binding = binding ++ [k: k, ref_target: ref_target]

          filename =
            Application.app_dir(
              :brando,
              "priv/templates/brando.gen/assets/backend/vue_inputs/references.eex"
            )

          {k, EEx.eval_file(filename, binding)}
      end)

    vue_inputs =
      Enum.map(attrs, fn
        {k, {:array, _}} ->
          {k, nil, nil}

        {k, :gallery} ->
          {k, nil, nil}

        {k, type} ->
          k =
            cond do
              type == :villain and k == :data ->
                :data

              type == :villain ->
                String.to_atom(Atom.to_string(k) <> "_data")

              true ->
                k
            end

          binding = binding ++ [k: k]

          filename =
            Application.app_dir(
              :brando,
              "priv/templates/brando.gen/assets/backend/vue_inputs/#{type}.eex"
            )

          {k, EEx.eval_file(filename, binding)}
      end)

    Keyword.put(binding, :vue_inputs, vue_assoc_inputs ++ vue_inputs)
  end
end
