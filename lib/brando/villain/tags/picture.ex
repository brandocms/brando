defmodule Brando.Villain.Tags.Picture do
  @moduledoc """
  {% picture entry.cover {
    sizes: 'auto',
    lazyload: true,
    placeholder: 'dominant_color_faded',
    srcset: 'MyApp.Projects.Project:cover.default',
    prefix: '/media'
  } %}
  """
  @behaviour Liquex.Tag

  import Phoenix.Component

  alias Brando.Villain.InertLiquid
  alias Brando.Villain.LiquexParser.TagGrammar
  alias Brando.Villain.TemplateView

  # Read as typed and escaped where printed (`TemplateView.eval_typed/2`)
  @typed_options ~w(alt)

  @impl true
  def parse, do: TagGrammar.parse(:picture)

  @impl true
  def render([source: source, args: args], context) do
    evaled_source = TemplateView.eval(source, context)

    evaled_args =
      Enum.map(args, fn arg ->
        {key, val} = eval_option(arg, context)
        {String.to_existing_atom(key), val}
      end)

    # The entry's language, so an image's text renders in it rather than in
    # whatever locale the renderer runs under (the admin's, on save).
    evaled_args = Keyword.put_new(evaled_args, :language, Liquex.Context.get(context, "language"))
    assigns = %{src: evaled_source, opts: evaled_args}

    comp = ~H"""
    <Brando.HTML.Images.picture src={@src} opts={@opts} />
    """

    # Texts an editor wrote about the media: text to the entry's final Liquid pass
    html = comp |> Phoenix.LiveViewTest.rendered_to_string() |> InertLiquid.encode()

    {[html], context}
  end

  defp eval_option({:keyword, [key, _]} = arg, context) when key in @typed_options,
    do: TemplateView.eval_typed(arg, context)

  defp eval_option(arg, context), do: TemplateView.eval(arg, context)
end
