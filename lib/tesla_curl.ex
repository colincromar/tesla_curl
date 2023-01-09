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

    query_params =
      Enum.into(env.query, %{}) |> URI.encode_query(:rfc3986) |> format_query_params()

    parsed_parts =
      Enum.map(env.body.parts, fn part ->
        parse_part(part)
      end)
      |> Enum.join(" ")

    "curl POST #{headers}#{parsed_parts} #{env.url}#{query_params}"
  end

  defp construct_curl(%Tesla.Env{query: []} = env, opts) when is_binary(env.body) do
    flag_type = set_flag_type(env.headers)
    headers = parse_headers(env.headers, opts)
    location = location_flag(opts)
    method = translate_method(env.method)

    needs_url_encoding = headers =~ "application/x-www-form-urlencoded"
    body = standardize_raw_body(env.body, needs_url_encoding)

    "curl #{location}#{method}#{headers}#{flag_type} '#{body}' #{env.url}"
  end

  defp construct_curl(%Tesla.Env{} = env, opts) when is_binary(env.body) do
    flag_type = set_flag_type(env.headers)
    headers = parse_headers(env.headers, opts)
    location = location_flag(opts)
    method = translate_method(env.method)

    query_params =
      Enum.into(env.query, %{}) |> URI.encode_query(:rfc3986) |> format_query_params()

    "curl #{location}#{method}#{headers}#{flag_type} #{env.body.data} #{env.url}#{query_params}"
  end

  defp construct_curl(%Tesla.Env{} = env, opts) do
    flag_type = set_flag_type(env.headers)
    headers = parse_headers(env.headers, opts)
    body = parse_body(env.body, flag_type, opts)
    location = location_flag(opts)
    method = translate_method(env.method)

    query_params =
      Enum.into(env.query, %{}) |> URI.encode_query(:rfc3986) |> format_query_params()

    "curl #{location}#{method}#{headers}#{body}#{env.url}#{query_params}"
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
    |> Kernel.<>(" ")
  end

  # Reads the redact_fields option to find body fields to redact
  @spec filter_body(String.t(), String.t(), String.t(), keyword() | nil) :: String.t()
  defp filter_body(flag_type, key, value, nil),
    do: construct_field(flag_type, standardize_key(key), value, false)

  defp filter_body(flag_type, key, value, opts) do
    with {:ok, redact_fields} <- Keyword.fetch(opts, :redact_fields) do
      is_redacted = Enum.any?(field_needs_redaction(key, redact_fields), fn x -> x == true end)
      construct_field(flag_type, key, value, is_redacted)
    else
      _ -> construct_field(flag_type, key, value, false)
    end
  end

  # Checks if the key matches any of the redact_fields, including ones found in nested maps or lists
  @spec field_needs_redaction(String.t(), list()) :: list()
  defp field_needs_redaction(key, redact_fields) do
    downcased_key = String.downcase(key)
    downcased_fields = Enum.map(redact_fields, fn field -> String.downcase(field) end)
    Enum.map(downcased_fields, fn field ->
      String.contains?(downcased_key, field) || String.contains?(downcased_key, "[#{field}]")
    end)
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
  defp construct_header_string(key, value, false), do: "--header '#{key}: #{value}'"
  defp construct_header_string(key, _value, true), do: "--header '#{key}: [REDACTED]'"

  # Constructs the body string
  @spec construct_field(String.t(), String.t(), String.t(), boolean()) :: String.t()
  defp construct_field("--data-urlencode" = flag_type, key, value, false), do: "#{flag_type} '#{key}=#{URI.encode(value)}'"
  defp construct_field(flag_type, key, value, false), do: "#{flag_type} '#{key}=#{value}'"
  defp construct_field(flag_type, key, _value, true), do: "#{flag_type} '#{key}=[REDACTED]'"

  # Top-level function to parse body
  @spec parse_body(list() | nil, String.t(), keyword() | nil) :: String.t()
  defp parse_body(nil, _flag_type, _opts), do: ""
  defp parse_body([], _flag_type, _opts), do: ""

  defp parse_body(body, flag_type, opts) do
    Enum.flat_map(body, fn {k, v} ->
      results = translate_value(k, v)
      Enum.map(results, fn {key, value} -> filter_body(flag_type, key, value, opts) end)
    end)
    |> Enum.join(" ")
    |> Kernel.<>(" ")
  end

  # Recursively handles any nested maps or lists, returns a tuple containing the translated keys and values in string form.
  @spec translate_value(String.t(), map() | list() | String.t()) :: [{String.t(), String.t()}]
  def translate_value(key, value) when is_map(value) do
    value
    |> Map.to_list()
    |> Enum.flat_map(fn {k, v} ->
      translate_value("#{key}[#{k}]", v)
    end)
  end

  def translate_value(key, value) when is_list(value) do
    value
    |> Enum.with_index()
    |> Enum.flat_map(fn {v, i} ->
      translate_value("#{key}[#{i}]", v)
    end)
  end

  def translate_value(key, value) do
    [{key, value}]
  end

  # Converts atom keys to strings if needed
  @spec standardize_key(String.t() | atom()) :: String.t()
  defp standardize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp standardize_key(key), do: key

  # URI encode raw string body, if needed.
  @spec standardize_raw_body(String.t(), boolean()) :: String.t()
  defp standardize_raw_body(body, true), do: URI.encode(body)
  defp standardize_raw_body(body, false), do: body

  # Determines the flag type based on the content type header
  @spec set_flag_type(list()) :: String.t()
  defp set_flag_type(headers) do
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

    "#{translated} "
  end

  # Sets the location flag based on the follow_redirects option
  @spec location_flag(keyword()) :: String.t()
  defp location_flag(nil), do: ""

  defp location_flag(opts) do
    with {:ok, follow_redirects} <- Keyword.fetch(opts, :follow_redirects) do
      (follow_redirects == true) |> set_location_flag()
    else
      _ -> ""
    end
  end

  # Returns a location flag based on boolean input
  @spec set_location_flag(boolean()) :: String.t()
  defp set_location_flag(true), do: "-L "
  defp set_location_flag(_), do: ""

  # Returns either an empty string or a query string to append to the URL
  @spec format_query_params(String.t()) :: String.t()
  defp format_query_params(""), do: ""
  defp format_query_params(query_params), do: "?#{query_params}"
end
