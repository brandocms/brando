defmodule Brando.Villain.Tags.Form do
  @moduledoc """
  Renders a form in a block:

      {% form contact %}
      {% form 'contact' { class: 'wide' } %}

  The argument is a `:form` block var, or a form key. Either way the form is
  the published one with that key in the entry's language, so a translated
  page shows the translated form. Args: `class`, `id`, and `enhance: false`
  to leave out the submission script.

  Block HTML is stored when the entry is saved, so the tag stores the CSRF
  placeholder that `Brando.Forms.Delivery.finalize/1` fills in per request.
  Inside the admin it renders a preview that cannot be submitted.

  Liquid cannot pass slots. A site that wants its own markup everywhere sets a
  component the tag renders instead of `Brando.HTML.Forms.site_form/1`, with
  the same assigns:

      config :brando, Brando.Forms, component: {MyAppWeb.Forms, :site_form}
  """
  @behaviour Liquex.Tag

  alias Brando.Forms
  alias Brando.Forms.Delivery
  alias Brando.Villain.LiquexParser.TagGrammar

  @impl true
  def parse, do: TagGrammar.parse(:form)

  @impl true
  def render(parsed, context) do
    source = Keyword.fetch!(parsed, :source)
    args = Keyword.get(parsed, :args, [])
    {evaled_source, _context} = Liquex.Argument.eval(source, context)
    language = Liquex.Context.get(context, "language")

    case resolve(evaled_source, language) do
      nil ->
        {["<!-- form #{inspect(key_of(evaled_source))} is not published in #{language} -->"], context}

      form ->
        assigns =
          args
          |> Map.new(fn arg ->
            {{key, value}, _context} = Liquex.Argument.eval(arg, context)
            {key, value}
          end)
          |> assigns(form, Liquex.Context.get(context, "brando_render_for_admin") == true)

        {[render_component(assigns)], context}
    end
  end

  defp resolve(source, language) do
    case key_of(source) do
      nil -> nil
      key -> Forms.get_published_form(key, language)
    end
  end

  defp key_of(%Brando.Forms.Form{key: key}), do: key
  defp key_of(key) when is_binary(key) and key != "", do: key
  defp key_of(_), do: nil

  defp assigns(args, form, admin?) do
    %{
      __changed__: nil,
      form: form,
      id: string_arg(args, "id"),
      class: string_arg(args, "class"),
      enhance: Map.get(args, "enhance", true) != false,
      preview: admin?,
      action: "/__brando/forms/#{form.key}",
      csrf_token: Delivery.csrf_placeholder()
    }
  end

  defp string_arg(args, key) do
    case Map.get(args, key) do
      value when is_binary(value) and value != "" -> value
      _ -> nil
    end
  end

  defp render_component(assigns) do
    {module, function} =
      Application.get_env(:brando, Brando.Forms, [])[:component] || {Brando.HTML.Forms, :site_form}

    assigns =
      if {module, function} == {Brando.HTML.Forms, :site_form} do
        site_form_assigns(assigns)
      else
        assigns
      end

    module
    |> apply(function, [assigns])
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
  end

  # `site_form/1` takes classes by part; the tag's `class` is the form's.
  defp site_form_assigns(%{class: class} = assigns) do
    assigns
    |> Map.delete(:class)
    |> Map.put(:classes, if(class, do: %{form: class}, else: %{}))
  end
end
