defmodule Tesla.Middleware.Curl do
  @moduledoc """
  A middleware for the Tesla HTTP client that logs requests expressed in Curl.
  """

  require Logger

  @behaviour Tesla.Middleware

  @doc """
  Serves as the main entrypoint to the middleware. Handles this middleware and calls
  the next piece of middleware in the chain.
  """
  @spec call(Tesla.Env.t(), Tesla.Env.stack(), keyword() | nil) :: Tesla.Env.result()
  def call(env, next, opts \\ []) do
    env
    |> log_request(opts)
    |> Tesla.run(next)
  end

  # Calls parsing functions for headers and body, constructs the Curl command and logs it.
  @spec log_request(Tesla.Env.t(), keyword() | nil) :: :ok
  defp log_request(env, opts) do
    headers = parse_headers(env.headers, opts)
    body = parse_body(env.body, opts)

    # In general, concatenation, while not as pretty as interpolation, is a slightly more efficient
    # due to less protocol overhead. As such, this library opts to use concatenation.
    Logger.info(
      "curl " <>
        "--" <>
        normalize_method(env.method) <>
        " " <> headers <> space(env.headers) <> body <> space(env.body) <> env.url
    )

    env
  end

  @spec normalize_method(atom) :: String.t()
  defp normalize_method(method) when is_atom(method) do
    method
    |> Atom.to_string()
    |> String.upcase()
  end

  # Top-level function to parse headers
  @spec parse_headers(list(), keyword() | nil) :: String.t()
  defp parse_headers(nil, _opts), do: ""
  defp parse_headers([], _opts), do: ""

  defp parse_headers(headers, opts) do
    Enum.map(headers, fn {k, v} ->
      filter_header(k, v, opts)
    end)
    |> Enum.join(" ")
  end

  # Reads the redact_fields option to find fields to redact
  @spec filter_header(String.t(), String.t(), keyword() | nil) :: String.t()
  defp filter_header(key, value, nil), do: print_header(key, value, false)

  defp filter_header(key, value, opts) do
    with {:ok, redact_fields} <- Keyword.fetch(opts, :redact_fields) do
      fields = Enum.map(redact_fields, fn field -> String.downcase(field) end)
      print_header(key, value, Enum.member?(fields, String.downcase(key)))
    else
      _ -> print_header(key, value, false)
    end
  end

  # Constructs the header string
  @spec print_header(String.t(), String.t(), boolean()) :: String.t()
  defp print_header(key, value, false) do
    "--header '" <> key <> ": " <> value <> "'"
  end

  defp print_header(key, _value, true) do
    "--header '" <> key <> ": [REDACTED]'"
  end

  # Top-level function to parse body
  @spec parse_body(list(), keyword() | nil) :: String.t()
  defp parse_body(nil, _opts), do: ""
  defp parse_body([], _opts), do: ""

  defp parse_body(body, opts) do
    Enum.map(body, fn {k, v} ->
      filter_body(k, v, opts)
    end)
    |> Enum.join(" ")
  end

  # Reads the redact_fields option to find body fields to redact
  @spec filter_body(String.t(), String.t(), keyword() | nil) :: String.t()
  defp filter_body(key, value, nil), do: print_field(key, value, false)

  defp filter_body(key, value, opts) do
    with {:ok, redact_fields} <- Keyword.fetch(opts, :redact_fields) do
      fields = Enum.map(redact_fields, fn field -> String.downcase(field) end)
      print_field(key, value, Enum.member?(fields, String.downcase(key)))
    else
      _ -> print_field(key, value, false)
    end
  end

  # Constructs the body string
  @spec print_field(String.t(), String.t(), boolean()) :: String.t()
  defp print_field(key, value, false) do
    "--data-urlencode '" <> key <> "=" <> value <> "'"
  end

  defp print_field(key, _value, true) do
    "--data-urlencode '" <> key <> "=[REDACTED]'"
  end

  @spec space(list()) :: String.t()
  defp space(nil), do: ""
  defp space([]), do: ""
  defp space(env_list) when length(env_list) > 0, do: " "
end
