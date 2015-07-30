defmodule Brando.PageForm do
  @moduledoc """
  A form for the Page model. See the `Brando.Form` module for more
  documentation
  """
  use Brando.Form
  alias Brando.Page

  @doc false
  def get_language_choices(_) do
    Brando.config(:languages)
  end

  @doc false
  def get_status_choices(language) do
    Keyword.get(Brando.config(:status_choices), String.to_atom(language))
  end

  @doc false
  def get_parent_choices(_) do
    no_value = [value: "", text: "–"]
    if parents = Page |> Page.with_parents |> Brando.repo.all do
      parents
      |> Enum.reverse
      |> Enum.reduce([no_value], fn (parent, acc) ->
           acc ++ [[value: Integer.to_string(parent.id), text: "#{parent.slug} (#{parent.language})"]]
         end)
    else
      [no_value]
    end
  end

  @doc false
  @spec is_parent_selected?(String.t, Integer.t) :: boolean
  def is_parent_selected?(form_value, model_value) do
    cond do
      form_value == ""                             -> false
      String.to_integer(form_value) == model_value -> true
      true                                         -> false
    end
  end

  @doc false
  def get_now do
    Ecto.DateTime.to_string(Ecto.DateTime.local)
  end

  @doc """
  Check if status' choice is selected.
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

  form "page", [model: Brando.Page, helper: :admin_page_path, class: "grid-form"] do
    field :parent_id, :select,
      [required: true,
      help_text: "Hvis siden du oppretter skal være en underside, " <>
                 "velg tilhørende side her. Hvis ikke, velg <em>Ingen tilhørighet</em>",
      choices: &__MODULE__.get_parent_choices/1,
      is_selected: &__MODULE__.is_parent_selected?/2]
    field :key, :text,
        [required: true]
    fieldset do
      field :language, :select,
        [required: true,
        default: "no",
        choices: &__MODULE__.get_language_choices/1]
    end
    fieldset do
      field :status, :radio,
        [required: true,
        default: "2",
        choices: &__MODULE__.get_status_choices/1,
        is_selected: &__MODULE__.is_status_selected?/2]
    end
    fieldset do
      field :title, :text,
        [required: true]
      field :slug, :text,
        [required: true,
         slug_from: :title]
    end
    field :data, :textarea
    submit :save, [class: "btn btn-success"]
  end
end