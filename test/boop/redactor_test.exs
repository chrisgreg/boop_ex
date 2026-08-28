defmodule Boop.RedactorTest do
  use ExUnit.Case, async: true

  alias Boop.Redactor

  test "redacts default keys recursively, case-insensitively, with - and _ equivalent" do
    out =
      Redactor.redact(%{
        "api_key" => "a",
        Password: "b",
        headers: %{"Authorization" => "c", "Set-Cookie" => "d", accept: "json"},
        list: [%{token: "e"}, "plain", %{deep: %{private_key: "f"}}],
        safe: 1
      })

    assert out["api_key"] == "[REDACTED]"
    assert out[:Password] == "[REDACTED]"
    assert out.headers == %{"Authorization" => "[REDACTED]", "Set-Cookie" => "[REDACTED]", accept: "json"}
    assert out.list == [%{token: "[REDACTED]"}, "plain", %{deep: %{private_key: "[REDACTED]"}}]
    assert out.safe == 1
  end

  test "extra keys and keyword lists" do
    assert Redactor.redact(%{ssn: "1", name: "n", inner: [ssn: "2"]}, ["ssn"]) == %{ssn: "[REDACTED]", name: "n", inner: %{ssn: "[REDACTED]"}}
  end

  test "leaves dates and scalars alone" do
    dt = ~U[2026-08-28 12:00:00Z]
    assert Redactor.redact(%{at: dt, n: 1.5, ok: true, none: nil}) == %{at: dt, n: 1.5, ok: true, none: nil}
  end
end
