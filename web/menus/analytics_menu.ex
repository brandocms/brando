defmodule Brando.Analytics.Menu do
  @moduledoc """
  Menu definitions for the analytics menu.
  """
  use Brando.Menu
  import Brando.Gettext

  menu %{
    name: gettext("Analytics"), anchor: "analytics", icon: "fa fa-bar-chart icon",
      submenu: [
        %{name: gettext("Views"), url: {:admin_analytics_path, :views}},
        %{name: gettext("Referrals"), url: {:admin_analytics_path, :referrals}}
      ]
    }
end
