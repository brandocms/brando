defmodule Brando.Generators.Domain do
  def before_copy(binding) do
    binding
  end

  def after_copy(binding) do
    add_to_files(binding)
  end

  def add_to_files(binding) do
    Mix.Brando.add_to_file(
      binding[:domain_filename],
      "types",
      "@type #{binding[:singular]} :: #{binding[:app_module]}.#{binding[:domain]}.#{
        binding[:scoped]
      }.t()"
    )

    Mix.Brando.add_to_file(
      binding[:domain_filename],
      "header",
      "alias #{binding[:app_module]}.#{binding[:domain]}.#{binding[:scoped]}"
    )

    domain_code =
      EEx.eval_file(
        Application.app_dir(
          :brando,
          "priv/templates/brando.gen/domain_code.eex"
        ),
        binding
      )

    Mix.Brando.add_to_file(
      binding[:domain_filename],
      "code",
      domain_code
    )

    binding
  end
end
