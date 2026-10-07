defmodule Brando.Notes.MentionEmail do
  @moduledoc """
  The email telling a user what they were mentioned in, in their own
  language, in the mailer's shared layout. One email collects every mention
  since the last one (`Brando.Notes.deliver_mentions/2`).
  """
  use Phoenix.Component
  use Gettext, backend: Brando.Gettext

  alias Brando.Mailer
  alias Brando.Mailer.Layout

  @doc """
  The email for `user` about `items`: maps with `:author`, `:entry_title`,
  `:anchor`, `:text` and `:url`.
  """
  @spec build(map(), [map()]) :: Swoosh.Email.t()
  def build(user, items) do
    language = to_string(user.language || Brando.config(:default_admin_language) || "en")

    Gettext.with_locale(Brando.Gettext, language, fn ->
      subject =
        case items do
          [%{author: author, entry_title: title}] when is_binary(author) ->
            gettext("%{name} mentioned you in a note on %{title}", name: author, title: title)

          _ ->
            ngettext(
              "You were mentioned in a note",
              "You were mentioned in %{count} notes",
              length(items)
            )
        end

      items = Enum.map(items, &Map.put(&1, :heading, heading(&1)))

      assigns = %{
        intro: gettext("Here is what you were mentioned in:"),
        items: items,
        open: gettext("Open the entry"),
        footer: gettext("You get one email at most every ten minutes, with every mention since the last one.")
      }

      text =
        Enum.join(
          [assigns.intro] ++
            Enum.map(items, fn item -> Enum.join(Enum.reject([item.heading, item.text, item.url], &is_nil/1), "\n") end) ++
            [assigns.footer],
          "\n\n"
        )

      [to: user.email, subject: subject]
      |> Mailer.new()
      |> Layout.put_body(language: language, preheader: subject, html: html(assigns), text: text)
    end)
  end

  defp heading(%{author: author, entry_title: title, anchor: anchor}) do
    place = if anchor in [nil, ""], do: title, else: "#{title} · #{anchor}"

    if author,
      do: gettext("%{name} in %{place}", name: author, place: place),
      else: place
  end

  defp html(assigns) do
    ~H"""
    <p style="margin:0 0 16px;">{@intro}</p>
    <div :for={item <- @items} style="margin:0 0 20px;padding:12px 16px;border-left:3px solid #e4b866;background:#fbf7ee;">
      <p style="margin:0 0 6px;font-size:14px;color:#5b5b5b;">{item.heading}</p>
      <p style="margin:0 0 8px;white-space:pre-wrap;">{item.text}</p>
      <p :if={item.url} style="margin:0;"><a href={item.url} style="color:#254e3f;">{@open}</a></p>
    </div>
    <p style="margin:0;font-size:14px;color:#5b5b5b;">{@footer}</p>
    """
  end
end
