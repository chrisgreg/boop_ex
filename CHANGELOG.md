# Changelog

## 1.1.0

- `actions` field on events: up to three `%{label, url}` buttons shown on the push notification and in the event detail (Boop server 1.2.0+). Maps, keyword lists, string keys and `{label, url}` tuples are accepted; `Boop.Event.action/2` builds one.
- Documented fingerprint grouping: Boop 1.2.0 collapses events sharing a `fingerprint` into one inbox row, so send stable fingerprints for repeats.

## 1.0.0

- `Boop.send/2` and `Boop.send_async/2` with title, keyword, map and `%Boop.Event{}` input.
- Client-side redaction of sensitive keys, truncation instead of rejection, bounded retries.
- `Boop.Event.exception/3` for rich error events.
- `Boop.healthy?/1`.
