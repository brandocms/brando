defmodule Mix.Tasks.Brando.Gen.MailTest do
  use ExUnit.Case, async: false

  alias Brando.IgniterCase

  test "compilation of the generated contact form rejects incomplete submissions" do
    project = IgniterCase.phoenix_project(module: "MailGeneratorStudio")
    result = Igniter.compose_task(project, "brando.gen.mail", [])
    assert result.issues == []
    module = MailGeneratorStudio.Contact.ContactForm

    on_exit(fn ->
      :code.purge(module)
      :code.delete(module)
    end)

    result |> IgniterCase.source("lib/#{Macro.underscore(module)}.ex") |> Code.compile_string()

    valid =
      apply(module, :changeset, [
        struct(module),
        %{
          name: "Alice",
          email: "alice@example.test",
          phone: "123",
          message: "Hello"
        }
      ])

    assert valid.valid?
    invalid = apply(module, :changeset, [struct(module), %{}])
    refute invalid.valid?
    assert Enum.sort(Keyword.keys(invalid.errors)) == [:email, :message, :name, :phone]
  end
end
