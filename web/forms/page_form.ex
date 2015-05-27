defmodule Brando.PageForm do
  @moduledoc """
  A form for the Page model. See the `Brando.Form` module for more
  documentation
  """
  use Brando.Form
  alias Brando.Page

  @doc false
  def get_language_choices do
    Brando.config(:languages)
  end

  @doc false
  def get_status_choices do
    Brando.config(:status_choices)
  end

  @doc false
  def get_parent_choices do
    no_value = [value: "", text: "Ingen tilhørighet"]
    if parents = Page.all_parents() do
      parents
      |> Enum.reverse
      |> Enum.reduce([no_value], fn (parent, acc) ->
           acc ++ [[value: Integer.to_string(parent.id), text: parent.slug]]
         end)
    else
      [no_value]
    end
  end

  @doc false
  def get_now do
    Ecto.DateTime.to_string(Ecto.DateTime.local)
  end

  @doc """
  Check is status' choice is selected.
  Translates the `model_value` from an atom to an int as string
  through `Brando.Type.Status.dump/1`.
  Returns boolean.
  """
  @spec is_status_selected?(String.t, atom) :: boolean
  def is_status_selected?(form_value, model_value) do
    # translate value from atom to corresponding int as string
    {:ok, status_int} = Brando.Type.Status.dump(model_value)
    form_value == to_string(status_int)
  end

  form "page", [helper: :admin_page_path, class: "grid-form"] do
    field :parent_id, :select,
      [required: true,
      label: "Hører til",
      help_text: "Hvis siden du oppretter skal være en underside, " <>
                 "velg tilhørende side her. Hvis ikke, velg <em>Ingen tilhørighet</em>",
      choices: &__MODULE__.get_parent_choices/0]
    field :key, :text,
        [required: true,
         label: "Identifikasjonsnøkkel",
         placeholder: "Identifikasjonsnøkkel"]
    fieldset do
      field :language, :select,
        [required: true,
        label: "Språk",
        default: "no",
        choices: &__MODULE__.get_language_choices/0]
    end
    fieldset do
      field :status, :radio,
        [required: true,
        label: "Status",
        default: "2",
        choices: &__MODULE__.get_status_choices/0,
        is_selected: &__MODULE__.is_status_selected?/2]
    end
    fieldset do
      field :title, :text,
        [required: true,
         label: "Tittel",
         placeholder: "Tittel"]
      field :slug, :text,
        [required: true,
         label: "URL-tamp",
         placeholder: "URL-tamp",
         slug_from: :title]
    end
    field :data, :textarea,
      [label: "Innhold"]
    submit "Lagre",
      [class: "btn btn-success"]
  end
end