- A block uid must now hold only letters, digits, `-` and `_` and not end with `-`: proposals report any other uid as a problem, block changesets and block recovery refuse it, and frontend edit and live preview leave markers out for a row already stored with one, so a uid can no longer add markup to an edit-mode page.

- `mix brando.doctor` and the admin's System check report block rows stored with a uid of another shape, which render without frontend edit and live preview markers, and say how to replace them.
