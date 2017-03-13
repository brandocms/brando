defmodule <%= admin_module %>View do
  use Brando.Web, :view
<%= if sequenced do %>  use Brando.Sequence, :view<% end %>
  alias <%= admin_module %>Form
  import <%= base %>.Web.Backend.Gettext
end
