# The generated CMS layout renders the site header, but not the mobile chrome
# `MOBILE_MENU.js` drives — a real site supplies that itself. Replace the header
# with one that carries it, so the smoke browser exercises the installed menu JS
# and CSS. It has to stay a single header: Jupiter binds the menu to the first
# one it finds, and a second would leave the hamburger wired to nothing.
path = "lib/igniter_smoke_web/cms/layouts.ex"
source = File.read!(path)
opening = "        <header data-nav>"
closing = "        </header>\n"
true = String.contains?(source, opening)

[before, rest] = String.split(source, opening, parts: 2)
[_generated_header, rest] = String.split(rest, closing, parts: 2)

header = ~S"""
        <header data-nav>
          <nav id="menu" aria-label="Menu">
            <a :if={site_name(assigns)} class="brand" href="/">{site_name(assigns)}</a>
            <div class="mobile-bg"></div>
            <section class="main">
              <ul>
                <li><a href="/">Home</a></li>
                <li><a href="/about">About</a></li>
              </ul>
            </section>
            <figure class="menu-button">
              <a href="#menu" class="hamburger noanim" aria-label="Menu" aria-controls="menu" aria-expanded="false">
                <i></i>
                <i></i>
                <i></i>
              </a>
            </figure>
          </nav>
        </header>
"""

File.write!(path, before <> header <> rest)
