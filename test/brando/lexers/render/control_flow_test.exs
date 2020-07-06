defmodule Brando.Lexer.Render.ControlFlowTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Brando.Lexer.Context

  describe "if statements" do
    test "failing if statement" do
      context = Context.new(%{"product" => %{"title" => "Not Awesome Shoes"}})

      {:ok, template} =
        """
        {% if product.title == "Awesome Shoes" %}
          These shoes are awesome!
        {% endif %}
        """
        |> String.trim()
        |> Brando.Lexer.parse()

      assert elem(Brando.Lexer.render(template, context), 0)
             |> IO.chardata_to_string()
             |> String.trim() == ""
    end

    test "else statement" do
      context = Context.new(%{"product" => %{"title" => "Not Awesome Shoes"}})

      {:ok, template} =
        """
        {% if product.title == "Awesome Shoes" %}
          These shoes are awesome!
        {% else %}
          These are ${product.title}
        {% endif %}
        """
        |> String.trim()
        |> Brando.Lexer.parse()

      assert elem(Brando.Lexer.render(template, context), 0)
             |> IO.chardata_to_string()
             |> String.trim() == "These are Not Awesome Shoes"
    end

    test "elsif statement" do
      context = Context.new(%{"product" => %{"id" => 2, "title" => "Not Awesome Shoes"}})

      {:ok, template} =
        """
        {% if product.title == "Awesome Shoes" %}
          These shoes are awesome!
        {% elsif product.id == 2 %}
          These are not awesome shoes
        {% else %}
          I don't know what these are
        {% endif %}
        """
        |> String.trim()
        |> Brando.Lexer.parse()

      assert elem(Brando.Lexer.render(template, context), 0)
             |> IO.chardata_to_string()
             |> String.trim() == "These are not awesome shoes"
    end

    test "or statement" do
      customer = %{"tags" => [], "email" => "example@mycompany.com"}

      {:ok, template} =
        """
        {% if customer.tags contains 'VIP' or customer.email contains 'mycompany.com' %}
          Welcome! We're pleased to offer you a special discount of 15% on all products.
        {% else %}
          Welcome to our store!
        {% endif %}
        """
        |> String.trim()
        |> Brando.Lexer.parse()

      assert Brando.Lexer.render(template, Context.new(%{"customer" => customer}))
             |> elem(0)
             |> IO.chardata_to_string()
             |> String.trim() ==
               "Welcome! We're pleased to offer you a special discount of 15% on all products."
    end
  end
end
