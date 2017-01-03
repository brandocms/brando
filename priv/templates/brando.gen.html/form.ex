defmodule <%= admin_module %>Form do
  @moduledoc """
  A form for the <%= alias %> schema. See the `Brando.Form` module for more
  documentation
  """
  use Brando.Form

  form "<%= singular %>", [
    schema: <%= module %>,
    helper: :<%= admin_path %>_path,
    class: "grid-form"] do
<%= for {_k, input} <- inputs, input do %>    <%= input %>
<% end %>    submit :save, [class: "btn btn-success"]
  end
end
