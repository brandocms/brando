defmodule Brando.Notifications.Email do
  @moduledoc """
  Notification email, in the recipient's language and the mailer's shared
  layout: one notification (`single/2`), or a digest of the notifications
  and mentions collected since the last one (`digest/4`).
  """
  use Phoenix.Component
  use Gettext, backend: Brando.Gettext

  alias Brando.Mailer
  alias Brando.Mailer.Layout
  alias Brando.Notifications.Message

  @doc "The email telling `user` about one notification."
  @spec single(map(), map()) :: Swoosh.Email.t()
  def single(user, notification) do
    language = language(user)
    content = Message.content(notification, language)

    Gettext.with_locale(Brando.Gettext, language, fn ->
      assigns = %{items: [content], footer: footer(:single)}

      [to: user.email, subject: content.title]
      |> Mailer.new()
      |> Layout.put_body(language: language, preheader: content.text, html: html(assigns), text: text(assigns))
    end)
  end

  @doc """
  The digest for `user`: `notifications`, and `mentions` as
  `Brando.Notes.MentionEmail` takes them (`:author`, `:entry_title`,
  `:anchor`, `:text`, `:url`). `period` is `:daily` or `:weekly`.
  """
  @spec digest(map(), [map()], [map()], :daily | :weekly) :: Swoosh.Email.t()
  def digest(user, notifications, mentions, period) do
    language = language(user)
    items = Enum.map(notifications, &Message.content(&1, language))

    Gettext.with_locale(Brando.Gettext, language, fn ->
      mention_items =
        Enum.map(mentions, fn mention ->
          place =
            if mention.anchor in [nil, ""], do: mention.entry_title, else: "#{mention.entry_title} · #{mention.anchor}"

          %{
            title:
              if(mention.author,
                do: gettext("%{name} mentioned you in %{place}", name: mention.author, place: place),
                else: gettext("You were mentioned in %{place}", place: place)
              ),
            text: mention.text,
            link: mention.url,
            link_label: gettext("Open the entry"),
            context: nil
          }
        end)

      count = length(items) + length(mention_items)

      subject =
        case period do
          :weekly -> ngettext("Your weekly summary: 1 notification", "Your weekly summary: %{count} notifications", count)
          _ -> ngettext("Your daily summary: 1 notification", "Your daily summary: %{count} notifications", count)
        end

      assigns = %{
        sections: [
          {gettext("Mentions"), mention_items},
          {gettext("Notifications"), items}
        ],
        footer: footer(period)
      }

      [to: user.email, subject: subject]
      |> Mailer.new()
      |> Layout.put_body(language: language, preheader: subject, html: digest_html(assigns), text: digest_text(assigns))
    end)
  end

  defp language(user), do: to_string(user.language || Brando.config(:default_admin_language) || "en")

  defp footer(:single),
    do:
      gettext(
        "You get this because an administrator added you to a notification route. Choose a daily or weekly summary instead in your profile."
      )

  defp footer(:daily), do: gettext("You get one summary a day. Change it in your profile.")
  defp footer(:weekly), do: gettext("You get one summary a week. Change it in your profile.")

  defp text(assigns), do: Enum.join(Enum.map(assigns.items, &item_text/1) ++ [assigns.footer], "\n\n")

  defp digest_text(assigns) do
    sections =
      for {heading, items} <- assigns.sections, items != [] do
        Enum.join([heading | Enum.map(items, &item_text/1)], "\n\n")
      end

    Enum.join(sections ++ [assigns.footer], "\n\n")
  end

  defp item_text(item) do
    [item.title, item.text, item.context, item.link] |> Enum.reject(&(&1 in [nil, ""])) |> Enum.join("\n")
  end

  defp html(assigns) do
    ~H"""
    <.item :for={item <- @items} item={item} />
    <p style="margin:0;font-size:14px;color:#5b5b5b;">{@footer}</p>
    """
  end

  defp digest_html(assigns) do
    ~H"""
    <%= for {heading, items} <- @sections, items != [] do %>
      <h2 style="margin:0 0 12px;font-size:16px;">{heading}</h2>
      <.item :for={item <- items} item={item} />
    <% end %>
    <p style="margin:0;font-size:14px;color:#5b5b5b;">{@footer}</p>
    """
  end

  attr :item, :map, required: true

  defp item(assigns) do
    ~H"""
    <div style="margin:0 0 20px;padding:12px 16px;border-left:3px solid #e4b866;background:#fbf7ee;">
      <p style="margin:0 0 6px;font-weight:600;">{@item.title}</p>
      <p :if={@item.text} style="margin:0 0 6px;white-space:pre-wrap;">{@item.text}</p>
      <p :if={@item.context} style="margin:0 0 6px;font-size:13px;color:#5b5b5b;">{@item.context}</p>
      <p :if={@item.link} style="margin:0;"><a href={@item.link} style="color:#254e3f;">{@item.link_label}</a></p>
    </div>
    """
  end
end
