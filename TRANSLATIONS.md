### Extract translation for Brando

    $ mix gettext.extract --merge priv/gettext/frontend --locale no --plural-forms-header nplurals="2; plural=(n != 1);"
    $ mix gettext.extract --merge priv/gettext/backend --locale no --plural-forms-header nplurals="2; plural=(n != 1);"
