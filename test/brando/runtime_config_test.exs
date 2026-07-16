defmodule Brando.RuntimeConfigTest do
  use ExUnit.Case, async: true

  alias Brando.RuntimeConfig

  test "resolves web infrastructure modules without the Brando application facade" do
    web_module = RuntimeConfig.get(:web_module)

    assert RuntimeConfig.endpoint() == Module.concat(web_module, Endpoint)
    assert RuntimeConfig.router_helpers() == Module.concat(web_module, Router.Helpers)
    assert RuntimeConfig.gettext() == Module.concat(web_module, Gettext)
  end

  test "keeps the Brando application facade compatible" do
    assert RuntimeConfig.endpoint() == Brando.endpoint()
    assert RuntimeConfig.router_helpers() == Brando.helpers()
    assert RuntimeConfig.router_helpers() == Brando.routes()
    assert RuntimeConfig.gettext() == Brando.gettext()
  end

  test "reads Images configuration without depending on the Images context" do
    assert RuntimeConfig.images(:default_config) == Brando.config(Brando.Images, :default_config)
    assert RuntimeConfig.images(:cdn) == Brando.config(Brando.Images, :cdn)
  end
end
