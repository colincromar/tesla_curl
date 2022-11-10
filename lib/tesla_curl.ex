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

  # Calls the function to construct the curl command and logs it.
  @spec log_request(Tesla.Env.t(), keyword() | nil) :: Tesla.Env.t()
  defp log_request(env, opts) do
    curl = construct_curl(env, opts)
    Logger.info(curl)
    env
  end

  # Parses the body parts of multipart requests into Curl format.
  @spec parse_part(%Tesla.Multipart.Part{}) :: String.t()
  defp parse_part(%Tesla.Multipart.Part{body: %File.Stream{}} = part) do
    {_, field} = List.first(part.dispositions)
    "--form #{field}=@#{part.body.path}"
  end

  defp parse_part(%Tesla.Multipart.Part{} = part) do
    {_, field} = List.first(part.dispositions)
    "--form #{field}=#{part.body}"
  end

  # Calls parser functions and constructs the Curl command string.
  @spec construct_curl(Tesla.Env.t(), keyword()) :: String.t()
  defp construct_curl(%Tesla.Env{body: %Tesla.Multipart{}} = env, opts) do
    headers = parse_headers(env.headers, opts)
    query_params = Enum.into(env.query, %{}) |> URI.encode_query(:rfc3986)

    parsed_parts =
      Enum.map(env.body.parts, fn part ->
        parse_part(part)
      end)
      |> Enum.join(" ")

    "curl -X POST #{headers}#{space(env.headers)}#{parsed_parts} #{env.url}#{format_query_params(query_params)}"
  end

  defp construct_curl(%Tesla.Env{query: []} = env, opts) when is_binary(env.body) do
    flag_type = get_flag_type(env.headers)
    headers = parse_headers(env.headers, opts)

    "curl #{location_flag(opts)}#{translate_method(env.method)}#{headers}#{space(env.headers)}#{flag_type} '#{env.body}' #{env.url}"
  end

  defp construct_curl(%Tesla.Env{} = env, opts) when is_binary(env.body) do
    flag_type = get_flag_type(env.headers)
    headers = parse_headers(env.headers, opts)
    query_params = Enum.into(env.query, %{}) |> URI.encode_query(:rfc3986)

    "curl #{location_flag(opts)}#{translate_method(env.method)}#{headers}#{space(env.headers)}#{flag_type} #{env.body.data} #{env.url}#{format_query_params(query_params)}"
  end

  defp construct_curl(%Tesla.Env{} = env, opts) do
    flag_type = get_flag_type(env.headers)
    headers = parse_headers(env.headers, opts)
    body = parse_body(env.body, flag_type, opts)
    query_params = Enum.into(env.query, %{}) |> URI.encode_query(:rfc3986)

    "curl #{location_flag(opts)}#{translate_method(env.method)}#{headers}#{space(env.headers)}#{body}#{space(env.body)}#{env.url}#{format_query_params(query_params)}"
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
  defp filter_header(key, value, nil), do: construct_header_string(key, value, false)

  defp filter_header(key, value, opts) do
    with {:ok, redact_fields} <- Keyword.fetch(opts, :redact_fields) do
      fields = Enum.map(redact_fields, fn field -> String.downcase(field) end)
      construct_header_string(key, value, Enum.member?(fields, String.downcase(key)))
    else
      _ -> construct_header_string(key, value, false)
    end
  end

  # Constructs the header string
  @spec construct_header_string(String.t(), String.t(), boolean()) :: String.t()
  defp construct_header_string(key, value, false) do
    "--header '#{key}: #{value}'"
  end

  defp construct_header_string(key, _value, true) do
    "--header '#{key}: [REDACTED]'"
  end

  # Top-level function to parse body
  @spec parse_body(list() | nil, String.t(), keyword() | nil) :: String.t()
  defp parse_body(nil, _flag_type, _opts), do: ""
  defp parse_body([], _flag_type, _opts), do: ""

  defp parse_body(body, flag_type, opts) do
    Enum.map(body, fn {k, v} ->
      filter_body(flag_type, k, v, opts)
    end)
    |> Enum.join(" ")
  end

  # Reads the redact_fields option to find body fields to redact
  @spec filter_body(String.t(), String.t(), String.t(), keyword() | nil) :: String.t()
  defp filter_body(flag_type, key, value, nil), do: construct_field(flag_type, key, value, false)

  defp filter_body(flag_type, key, value, opts) do
    with {:ok, redact_fields} <- Keyword.fetch(opts, :redact_fields) do
      fields = Enum.map(redact_fields, fn field -> String.downcase(field) end)
      construct_field(flag_type, key, value, Enum.member?(fields, String.downcase(key)))
    else
      _ -> construct_field(flag_type, key, value, false)
    end
  end

  # Constructs the body string
  @spec construct_field(String.t(), String.t(), String.t(), boolean()) :: String.t()
  defp construct_field(flag_type, key, value, false) do
    "#{flag_type} '#{key}=#{value}'"
  end

  defp construct_field(flag_type, key, _value, true) do
    "#{flag_type} '#{key}=[REDACTED]'"
  end

  # Determines the flag type based on the content type header
  @spec get_flag_type(list()) :: String.t()
  defp get_flag_type(headers) do
    content_type = Enum.find(headers, fn {key, _val} -> key == "Content-Type" end)

    case content_type do
      {"Content-Type", "application/x-www-form-urlencoded"} -> "--data-urlencode"
      {"Content-Type", "multipart/form-data"} -> "--form"
      _ -> "--data"
    end
  end

  # Converts method atom into a string and assigns proper flag prefixes
  @spec translate_method(atom) :: String.t()
  defp translate_method(:get), do: ""
  defp translate_method(:head), do: "-I "

  defp translate_method(method) when is_atom(method) do
    translated =
      method
      |> Atom.to_string()
      |> String.upcase()

    "-X #{translated} "
  end

  @spec location_flag(keyword()) :: String.t()
  def location_flag(nil), do: ""

  def location_flag(opts) do
    with {:ok, follow_redirects} <- Keyword.fetch(opts, :follow_redirects) do
      (follow_redirects == true) |> set_location_flag()
    else
      _ -> ""
    end
  end

  def set_location_flag(true), do: "-L "
  def set_location_flag(_), do: ""

  # Implements a space function to avoid adding a space when the header or body is empty
  @spec space(list()) :: String.t()
  defp space(nil), do: ""
  defp space([]), do: ""
  defp space(env_list) when length(env_list) > 0, do: " "

  # Returns either an empty string or a query string to append to the URL
  @spec format_query_params(String.t()) :: String.t()
  defp format_query_params(""), do: ""
  defp format_query_params(query_params), do: "?#{query_params}"
end
