defmodule Brando.Tenant.ServedHosts.DNSTest do
  # What `DNS` makes of each answer `:inet_res.resolve/5` gives. No test asks
  # a name server: each passes a function in its place.
  use ExUnit.Case, async: true

  alias Brando.Tenant.ServedHosts.DNS

  @v4 {203, 0, 113, 10}
  @v4_other {198, 51, 100, 7}
  @v6 {0x2001, 0xDB8, 0, 0, 0, 0, 0, 0x10}

  # A NOERROR message whose answer section holds `records`, each
  # `{domain, type, data}`, with the truncation flag as `:inet_res` decodes it
  defp noerror(records, truncated? \\ false) do
    answers =
      for {domain, type, data} <- records,
          do: :inet_dns.make_rr(domain: String.to_charlist(domain), class: :in, type: type, data: data, ttl: 300)

    {:ok, :inet_dns.make_msg(header: :inet_dns.make_header(qr: true, tc: truncated?), anlist: answers)}
  end

  defp failure(code), do: {:error, {code, :inet_dns.make_msg([])}}

  # A stand-in for `:inet_res.resolve/5` that answers by name and type, and
  # tells the test what it was asked
  defp resolver(answers) do
    test = self()

    fn name, class, type, options, timeout ->
      send(test, {:asked, to_string(name), class, type, options, timeout})
      Map.get(answers, {to_string(name), type}, failure(:nxdomain))
    end
  end

  describe "both families" do
    test "answered: every address, each family asked with a timeout per query and a bounded total" do
      resolve =
        resolver(%{
          {"acme.example.com", :a} => noerror([{"acme.example.com", :a, @v4}]),
          {"acme.example.com", :aaaa} => noerror([{"acme.example.com", :aaaa, @v6}])
        })

      assert DNS.lookup("acme.example.com", resolve) == {:ok, [@v4, @v6]}

      for type <- [:a, :aaaa] do
        assert_received {:asked, "acme.example.com", :in, ^type, options, timeout}
        assert options[:timeout] == 2_000
        assert options[:retry] == 2
        assert options[:nxdomain_reply] == true
        assert timeout > 0 and timeout <= 4_000
      end
    end

    test "a name that does not exist does not resolve" do
      assert DNS.lookup("gone.example.com", resolver(%{})) == {:error, :nxdomain}
    end

    test "a name with no record of either family does not resolve" do
      resolve =
        resolver(%{
          {"empty.example.com", :a} => noerror([]),
          {"empty.example.com", :aaaa} => noerror([])
        })

      assert DNS.lookup("empty.example.com", resolve) == {:error, :nxdomain}
    end

    test "both timing out leave both unread, never as no records" do
      resolve = fn _name, _class, _type, _options, _timeout -> {:error, :timeout} end

      assert DNS.lookup("slow.example.com", resolve) ==
               {:incomplete, [], [:inet, :inet6], %{inet: :timeout, inet6: :timeout}}
    end
  end

  describe "one family" do
    test "with no record: the other family's addresses are all there is" do
      resolve =
        resolver(%{
          {"acme.example.com", :a} => noerror([{"acme.example.com", :a, @v4}]),
          {"acme.example.com", :aaaa} => noerror([])
        })

      assert DNS.lookup("acme.example.com", resolve) == {:ok, [@v4]}
    end

    test "that does not exist, with the name server's message: no records of it" do
      resolve =
        resolver(%{
          {"acme.example.com", :a} => noerror([{"acme.example.com", :a, @v4}]),
          {"acme.example.com", :aaaa} => failure(:nxdomain)
        })

      assert DNS.lookup("acme.example.com", resolve) == {:ok, [@v4]}
    end

    for {name, answer, reason} <- [
          {:timeout, {:error, :timeout}, :timeout},
          {:servfail, {:error, {:servfail, :msg}}, :server_failure},
          {:refused, {:error, {:refused, :msg}}, :refused},
          {:notimp, {:error, {:notimp, :msg}}, :other},
          {:qfmterror, {:error, {:qfmterror, :msg}}, :other},
          {:unknown_code, {:error, {:unknown, :msg}}, :other},
          {:undecodable_answer, {:error, :formerr}, :other},
          {:connection_refused, {:error, :econnrefused}, :other},
          {:network_unreachable, {:error, :enetunreach}, :other},
          {:no_name_server_to_ask, {:error, :nxdomain}, :no_name_servers},
          {:unexpected_answer, :something_else, :other}
        ] do
      test "unread after #{name}: the lookup is incomplete, whatever the other family holds" do
        answer = unquote(Macro.escape(answer))

        resolve =
          resolver(%{
            {"acme.example.com", :a} => noerror([{"acme.example.com", :a, @v4}]),
            {"acme.example.com", :aaaa} => answer
          })

        assert DNS.lookup("acme.example.com", resolve) == {:incomplete, [@v4], [:inet6], %{inet6: unquote(reason)}}
      end
    end

    # The final reply, over TCP after a truncated UDP one, can still carry the
    # flag, and `:inet_res` returns it as an answer like any other
    test "answered with the truncation flag and no records: unread, not empty" do
      resolve =
        resolver(%{
          {"acme.example.com", :a} => noerror([{"acme.example.com", :a, @v4}]),
          {"acme.example.com", :aaaa} => noerror([], true)
        })

      assert DNS.lookup("acme.example.com", resolve) == {:incomplete, [@v4], [:inet6], %{inet6: :truncated}}
    end

    test "answered with the truncation flag and some records: unread, as more may be cut off" do
      resolve =
        resolver(%{
          {"acme.example.com", :a} => noerror([{"acme.example.com", :a, @v4}], true),
          {"acme.example.com", :aaaa} => noerror([{"acme.example.com", :aaaa, @v6}])
        })

      assert DNS.lookup("acme.example.com", resolve) == {:incomplete, [@v6], [:inet], %{inet: :truncated}}
    end

    test "unread while the other has no records: incomplete with no addresses" do
      resolve =
        resolver(%{
          {"acme.example.com", :a} => {:error, :timeout},
          {"acme.example.com", :aaaa} => noerror([])
        })

      assert DNS.lookup("acme.example.com", resolve) == {:incomplete, [], [:inet], %{inet: :timeout}}
    end
  end

  describe "CNAME" do
    test "a chain in the answer is followed to its addresses, whatever the names' case" do
      resolve =
        resolver(%{
          {"www.acme.example.com", :a} =>
            noerror([
              {"edge.cdn.example.net", :a, @v4},
              {"WWW.acme.example.com", :cname, ~c"Shop.Acme.example.com"},
              {"shop.acme.example.com", :cname, ~c"edge.cdn.example.net"},
              {"other.example.net", :a, @v4_other}
            ]),
          {"www.acme.example.com", :aaaa} => noerror([{"www.acme.example.com", :cname, ~c"edge.cdn.example.net"}])
        })

      assert DNS.lookup("WWW.acme.example.com", resolve) == {:ok, [@v4]}
      # The AAAA answer ends at a name it holds nothing for: that name is asked
      assert_received {:asked, "edge.cdn.example.net", :in, :aaaa, _options, _timeout}
    end

    test "a target the answer holds nothing for is asked about on its own" do
      resolve =
        resolver(%{
          {"www.acme.example.com", :a} => noerror([{"www.acme.example.com", :cname, ~c"edge.cdn.example.net"}]),
          {"www.acme.example.com", :aaaa} => noerror([]),
          {"edge.cdn.example.net", :a} => noerror([{"edge.cdn.example.net", :a, @v4}])
        })

      assert DNS.lookup("www.acme.example.com", resolve) == {:ok, [@v4]}
    end

    test "a target whose own query times out leaves the family unread" do
      resolve =
        resolver(%{
          {"www.acme.example.com", :a} => noerror([{"www.acme.example.com", :a, @v4}]),
          {"www.acme.example.com", :aaaa} => noerror([{"www.acme.example.com", :cname, ~c"edge.cdn.example.net"}]),
          {"edge.cdn.example.net", :aaaa} => {:error, :timeout}
        })

      assert DNS.lookup("www.acme.example.com", resolve) == {:incomplete, [@v4], [:inet6], %{inet6: :timeout}}
    end

    test "a target that does not exist has no records" do
      resolve =
        resolver(%{
          {"www.acme.example.com", :a} => noerror([{"www.acme.example.com", :cname, ~c"gone.example.net"}]),
          {"www.acme.example.com", :aaaa} => noerror([])
        })

      assert DNS.lookup("www.acme.example.com", resolve) == {:error, :nxdomain}
    end

    test "a chain that comes back to a name it passed has no addresses" do
      resolve =
        resolver(%{
          {"a.example.com", :a} =>
            noerror([{"a.example.com", :cname, ~c"b.example.com"}, {"b.example.com", :cname, ~c"a.example.com"}]),
          {"a.example.com", :aaaa} => noerror([])
        })

      assert DNS.lookup("a.example.com", resolve) == {:error, :nxdomain}
    end

    test "a chain longer than eight queries leaves the family unread" do
      # Each name's answer points at the next, and holds nothing for it
      resolve = fn name, _class, type, _options, _timeout ->
        case {to_string(name), type} do
          {"acme.example.com", :aaaa} ->
            noerror([])

          {"acme.example.com", :a} ->
            noerror([{"acme.example.com", :cname, ~c"hop1.example.net"}])

          {"hop" <> n, :a} ->
            next = String.to_integer(hd(String.split(n, "."))) + 1
            noerror([{"hop#{n}", :cname, String.to_charlist("hop#{next}.example.net")}])
        end
      end

      assert DNS.lookup("acme.example.com", resolve) == {:incomplete, [], [:inet], %{inet: :other}}
    end

    test "several CNAMEs for one name leave the family unread" do
      resolve =
        resolver(%{
          {"www.acme.example.com", :a} =>
            noerror([
              {"www.acme.example.com", :cname, ~c"one.example.net"},
              {"www.acme.example.com", :cname, ~c"two.example.net"}
            ]),
          {"www.acme.example.com", :aaaa} => noerror([{"www.acme.example.com", :aaaa, @v6}])
        })

      assert DNS.lookup("www.acme.example.com", resolve) == {:incomplete, [@v6], [:inet], %{inet: :other}}
    end
  end
end
