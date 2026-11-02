- The live preview keeps updating on a site whose own scripts declare a name the preview's script used (`token`, `body`, `self` and others), and no longer replaces the site's `Phoenix` or `morphdom` globals.

- An element in the content named after a member of `document` (`<img name="querySelector">`, `createElement`, `createRange`, `addEventListener`, `currentScript`) no longer stops the live preview from starting, updating or recovering after a reconnect.
