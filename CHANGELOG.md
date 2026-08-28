# Changelog

## 1.0.0

- `Boop.send/2` and `Boop.send_async/2` with title, keyword, map and `%Boop.Event{}` input.
- Client-side redaction of sensitive keys, truncation instead of rejection, bounded retries.
- `Boop.Event.exception/3` for rich error events.
- `Boop.healthy?/1`.
