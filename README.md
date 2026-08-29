<h1 align="center">BoopEx</h1>

<p align="center">
  <a href="https://hex.pm/packages/boop_ex"><img src="https://img.shields.io/hexpm/v/boop_ex.svg" alt="Hex.pm"></a>
  <a href="https://hexdocs.pm/boop_ex"><img src="https://img.shields.io/badge/hex-docs-blue.svg" alt="Hex Docs"></a>
  <a href="https://hex.pm/packages/boop_ex"><img src="https://img.shields.io/hexpm/dt/boop_ex.svg" alt="Downloads"></a>
  <a href="https://github.com/chrisgreg/boop_ex/blob/main/LICENSE"><img src="https://img.shields.io/hexpm/l/boop_ex.svg" alt="License"></a>
</p>

<p align="center"><strong>Something happened in your app. Tell your phone.</strong></p>

The Elixir client for [Boop](https://github.com/chrisgreg/boop), a tiny self-hosted
push notification inbox.

It exists so a deploy finishing, a backup failing, or a payment landing is one
line away from a native push on your iPhone, with nothing between your server
and Apple:

```elixir
Boop.send("Deploy complete")
```

## Installation

```elixir
def deps do
  [{:boop_ex, "~> 1.1"}]
end
```

## Configuration

```elixir
# config/runtime.exs
config :boop_ex,
  url: System.fetch_env!("BOOP_URL"),          # https://boop.example.com
  api_key: System.fetch_env!("BOOP_API_KEY"),  # boop_proj_... from the Boop web UI
  source: "my_app",                            # optional: tags every event
  enabled: config_env() == :prod               # optional, default true
```

`url` and `api_key` fall back to the `BOOP_URL` and `BOOP_API_KEY` environment variables. Other options: `timeout` (ms, default 10 000), `redact_keys` (extra keys to redact), `req_options` (merged into `Req.new/1`).

## Usage

```elixir
# Minimum
Boop.send("Backup complete")

# Rich
Boop.send(
  title: "Payment received",
  body: "£19.99",
  level: :success,
  source: "polar",
  data: %{customer_id: "123", amount: 19.99, currency: "GBP"}
)

# Struct
Boop.send(%Boop.Event{title: "Backup failed", level: :error, data: %{host: "db-01"}})

# Fire and forget: returns :ok immediately, logs failures, never raises
Boop.send_async(title: "Cron finished", level: :info)
```

`send/2` returns `{:ok, %{id: "evt_…", created_at: %DateTime{}}}`, `{:ok, :disabled}`, or `{:error, %Boop.Error{code: …}}`. Codes: `:invalid`, `:not_configured`, `:unauthorized`, `:rejected`, `:server_error`, `:unreachable`, `:unexpected`. It never raises.

Levels: `:info` (default), `:success`, `:warning`, `:error`, `:critical` (prominent push).

### Errors with stacktraces

```elixir
try do
  risky()
rescue
  e ->
    Boop.send_async(
      title: inspect(e.__struct__),
      body: Exception.message(e),
      level: :error,
      data: Boop.Event.exception(e, __STACKTRACE__, tags: %{env: "prod"}, context: %{user_id: user.id})
    )
    reraise e, __STACKTRACE__
end
```

`exception`, `stacktrace`, `tags`, `context` and `breadcrumbs` in `data` get a rich rendering in the Boop web UI and iOS app. Anything else is kept as-is.

### Actions

Up to three buttons that open a URL, on the push itself (long-press it) and in the event detail. Open the deploy, the payment, the record:

```elixir
Boop.send_async(
  title: "Payment received",
  body: "£19.99",
  level: :success,
  actions: [
    %{label: "Open in Stripe", url: "https://dashboard.stripe.com/payments/pi_1"},
    Boop.Event.action("Open order", "myshop://orders/42")
  ]
)
```

Labels are up to 40 characters; URLs must be absolute (`https://…` or an app scheme). Needs Boop server 1.2.0 or newer (older servers ignore the field).

### Grouping repeats

Send the same `fingerprint` for the same problem and Boop shows one inbox row (`KeyError ×47 · First seen 09:31 · Last seen 10:42`) that opens the individual occurrences, instead of 47 rows:

```elixir
Boop.send_async(title: "Sync failed", level: :error, fingerprint: "sync-#{account.id}", body: inspect(reason))
```

Every occurrence is still stored and pushed; grouping only tidies the inbox. Use a [silence](https://github.com/chrisgreg/boop#silences) in Boop to stop pushes for a fingerprint.

### Phoenix

Nothing special is needed. Two common spots:

```elixir
# A deploy hook / release task
Boop.send(title: "Deployed #{System.get_env("RELEASE_VSN")}", level: :success, source: "deploy")

# Oban / GenServer failures
Boop.send_async(title: "Job failed: #{job.worker}", body: inspect(reason), level: :error, source: "oban")
```

For every unhandled exception in production, wrap `Boop.send_async/2` in a `:logger` handler or a `Plug.ErrorHandler`; the library deliberately stays out of the way and does not install one for you.

## Behaviour

- Never blocks or crashes the host application; every failure is a return value (or a `:warning` log for async).
- Redacts `password`, `secret`, `token`, `api_key`, `authorization`, `cookie`, `private_key` and friends anywhere in `data` before sending (the server does it again).
- Truncates over-long strings (title 200, body 4000) rather than rejecting the event; drops `data` over 256 KB with a note in `body`.
- Retries network errors and 5xx twice with jittered backoff; never retries 4xx.
- Timeouts on every request.
- Never logs the API key or full payloads.

## Testing your app

Point the client at a `Req.Test` stub:

```elixir
config :boop_ex, url: "https://boop.test", api_key: "boop_proj_test", req_options: [plug: {Req.Test, Boop}]

Req.Test.stub(Boop, fn conn ->
  Req.Test.json(conn, %{"id" => "evt_1", "created_at" => "2026-01-01T00:00:00Z"})
end)
```

Or set `enabled: false` in `config/test.exs` and every send returns `{:ok, :disabled}`.

## Usage rules for AI agents

The package ships a [`usage-rules.md`](usage-rules.md) compatible with [usage_rules](https://hexdocs.pm/usage_rules). To pull it into your project's `AGENTS.md` / `CLAUDE.md`:

```elixir
{:usage_rules, "~> 0.1", only: [:dev]}
```

```bash
mix usage_rules.sync AGENTS.md --all --link-to-folder deps
```

## Licence

MIT.
