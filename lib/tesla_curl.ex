defmodule Tesla.Middleware.Curl do
  @moduledoc false

  require Logger

  @behaviour Tesla.Middleware

  @spec call(Tesla.Env.t(), Tesla.Env.stack(), any) :: Tesla.Env.result()
  def call(env, next, _options) do
    env
    |> log_request()
    |> Tesla.run(next)
  end

  @spec log_request(Tesla.Env.t()) :: :ok
  defp log_request(env) do
    headers = parse_headers(env.headers)
    body = parse_body(env.body)

    Logger.info(
      "curl " <>
        "--" <>
        normalize_method(env.method) <>
        " " <> headers <> space(env.headers) <> body <> space(env.body) <> env.url
    )

    env
  end

  @spec normalize_method(atom | String.t()) :: String.t()
  defp normalize_method(method) when is_atom(method) do
    method
    |> Atom.to_string()
    |> String.upcase()
  end

  defp normalize_method(method) when is_binary(method) do
    method
    |> String.upcase()
  end

  @spec parse_headers(list()) :: String.t()
  defp parse_headers(nil), do: ""
  defp parse_headers([]), do: ""

  defp parse_headers(headers) do
    Enum.map(headers, fn {k, v} -> "--header '#{k}: #{v}'" end) |> Enum.join(" ")
  end

  @spec parse_body(list()) :: String.t()
  defp parse_body(nil), do: ""
  defp parse_body([]), do: ""

  defp parse_body(body) do
    Enum.map(body, fn {k, v} -> "--data-urlencode '#{k}=#{v}'" end) |> Enum.join(" ")
  end

  @spec space(list()) :: String.t()
  defp space(nil), do: ""
  defp space([]), do: ""
  defp space(env_list) when length(env_list) > 0, do: " "
end
