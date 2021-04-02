defmodule Brando.Villain.LiquexRenderer do
  alias Brando.Pages
  alias Brando.I18n

  def render({:fragment_tag, [parent_key: parent_key, key: key, language: language]}, context) do
    {:ok, fragment} =
      Pages.get_fragment(%{matches: %{parent_key: parent_key, key: key, language: language}})

    {[fragment.html], context}
  end

  def render({:route_tag, [function: function, action: action, args: args]}, context) do
    evaled_args = Enum.map(args, &Liquex.Argument.eval(&1, context))

    evaled_args =
      if function == "page_path" and action == "show", do: [evaled_args], else: evaled_args

    rendered_route =
      apply(Brando.helpers(), :"#{function}", [Brando.endpoint(), :"#{action}"] ++ evaled_args)

    {[rendered_route], context}
  end

  def render({:route_tag, [function: function, action: action]}, context) do
    rendered_route = apply(Brando.helpers(), :"#{function}", [Brando.endpoint(), :"#{action}"])

    {[rendered_route], context}
  end

  def render(
        {:route_i18n_tag, [locale: locale, function: function, action: action, args: args]},
        context
      ) do
    evaled_locale = Liquex.Argument.eval(locale, context)
    evaled_args = Enum.map(args, &Liquex.Argument.eval(&1, context))

    evaled_args =
      if function == "page_path" and action == "show", do: [evaled_args], else: evaled_args

    rendered_route =
      I18n.Helpers.localized_path(
        evaled_locale,
        :"#{function}",
        [Brando.endpoint(), :"#{action}"] ++ evaled_args
      )

    {[rendered_route], context}
  end

  def render({:route_i18n_tag, [locale: locale, function: function, action: action]}, context) do
    evaled_locale = Liquex.Argument.eval(locale, context)

    rendered_route =
      I18n.Helpers.localized_path(evaled_locale, :"#{function}", [Brando.endpoint(), :"#{action}"])

    {[rendered_route], context}
  end

  def render({:picture_tag, [source: source, args: args]}, context) do
    evaled_source = Liquex.Argument.eval(source, context)

    evaled_args =
      args
      |> Enum.map(fn arg ->
        {key, val} = Liquex.Argument.eval(arg, context)
        {String.to_existing_atom(key), val}
      end)

    html =
      evaled_source
      |> Brando.HTML.Images.picture_tag(evaled_args)
      |> Phoenix.HTML.safe_to_string()

    {[html], context}
  end

  # Ignore this tag if we don't match
  def render(_, _), do: false
end
