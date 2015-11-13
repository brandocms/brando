defmodule Brando.PageForm do
  @moduledoc """
  A form for the Page model. See the `Brando.Form` module for more
  documentation
  """

  use Brando.Form
  alias Brando.Page
  import Brando.Gettext

  @doc false
  def get_language_choices() do
    Brando.config(:languages)
  end

  @doc false
  def get_status_choices() do
    [[value: "0", text: gettext("Draft")],
     [value: "1", text: gettext("Published")],
     [value: "2", text: gettext("Pending")],
     [value: "3", text: gettext("Deleted")]]
  end

  @doc false
  def get_parent_choices() do
    no_value = [value: "", text: "–"]
    if parents = Page |> Page.with_parents |> Brando.repo.all do
      parents
      |> Enum.reverse
      |> Enum.reduce([no_value], fn (parent, acc) ->
           acc ++ [[value: Integer.to_string(parent.id),
                    text: "#{parent.slug} (#{parent.language})"]]
         end)
    else
      [no_value]
    end
  end

  @doc false
  @spec parent_selected?(String.t, Integer.t) :: boolean
  def parent_selected?(form_value, model_value) do
    cond do
      form_value == ""                             -> false
      String.to_integer(form_value) == model_value -> true
      true                                         -> false
    end
  end

  @doc """
  Check if status' choice is selected.
  Translates the `model_value` from an atom to an int as string
  through `Brando.Type.Status.dump/1`.
  Returns boolean.
  """
  @spec status_selected?(String.t, atom) :: boolean
  def status_selected?(form_value, model_value) do
    # translate value from atom to corresponding int as string
    {:ok, status_int} = Brando.Type.Status.dump(model_value)
    form_value == to_string(status_int)
  end

  form "page", [model: Page, helper: :admin_page_path, class: "grid-form"] do
    field :parent_id, :select, [
      help_text: gettext("If this page should belong to another, select parent page here. If not, select –"),
      choices: &__MODULE__.get_parent_choices/0,
      is_selected: &__MODULE__.parent_selected?/2]
    field :key, :text
    fieldset do
      field :language, :select,
        [default: "nb",
        choices: &__MODULE__.get_language_choices/0]
    end
    fieldset do
      field :status, :radio,
        [default: "2",
        choices: &__MODULE__.get_status_choices/0,
        is_selected: &__MODULE__.status_selected?/2]
    end
    fieldset do
      field :title, :text
      field :slug, :text, [slug_from: :title]
    end
    fieldset do
      field :meta_description, :text
      field :meta_keywords, :text
    end
    field :data, :textarea, [required: false]
    field :css_classes, :text, [required: false]
    submit :save, [class: "btn btn-success"]
  end
end
