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
end
