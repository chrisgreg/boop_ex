defmodule Boop.Error do
  @moduledoc """
  Why a send failed. Returned as `{:error, %Boop.Error{}}`; never raised.

  `code` is one of:

    * `:invalid` — the event failed local validation (nothing was sent)
    * `:not_configured` — no `url` or `api_key`
    * `:unauthorized` — the server rejected the API key (401)
    * `:rejected` — the server rejected the event (400/413/422); see `message`
    * `:server_error` — the server failed (5xx) after retries
    * `:unreachable` — network error or timeout after retries
    * `:unexpected` — anything else, including exceptions
  """

  defstruct [:code, :message, :status, :details]

  @type code :: :invalid | :not_configured | :unauthorized | :rejected | :server_error | :unreachable | :unexpected
  @type t :: %__MODULE__{code: code(), message: String.t(), status: non_neg_integer() | nil, details: term()}

  @doc false
  def new(code, message, fields \\ []) do
    struct(%__MODULE__{code: code, message: message}, fields)
  end

  @doc false
  def from_response(status, body) do
    {server_code, message} =
      case body do
        %{"error" => code, "message" => message} -> {code, message}
        _ -> {nil, "request failed (#{status})"}
      end

    code =
      cond do
        status == 401 -> :unauthorized
        status in [400, 413, 422] -> :rejected
        status >= 500 -> :server_error
        true -> :unexpected
      end

    new(code, message, status: status, details: server_code)
  end

  @doc false
  def exception_error(exception) do
    new(:unexpected, Exception.message(exception), details: exception)
  end

  @doc "Whether retrying the same request could succeed."
  @spec retryable?(t()) :: boolean()
  def retryable?(%__MODULE__{code: code}), do: code in [:server_error, :unreachable]
end
