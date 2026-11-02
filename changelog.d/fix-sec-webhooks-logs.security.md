- Unsigned requests no longer refuse signed GitHub Markdown deliveries by filling the webhook's node-wide request cap.

- The GitHub Markdown webhook answers a missing or malformed signature header with 401 before reading the body.

- The Mux webhook rejects every delivery when its secret is an empty string, as it does when the secret is unset.

- The request log keeps percent-encoded characters encoded on paths with a filtered token, so an encoded line feed cannot start a fabricated log line.
