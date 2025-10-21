# TeslaCurl

TeslaCurl is a middleware for [Tesla](https://hex.pm/packages/tesla). It will log a curl command for each request.

The package can be installed by adding `tesla_curl` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:tesla, "~> 1.15"},
    {:tesla_curl, "~> 1.4", only: [:dev, :test]}
  ]
end
```

## Usage

#### As a middleware:
You can use TeslaCurl as a middleware to automatically log cURL commands for each request:

```elixir
defmodule HelloWorld do
  def middleware do
    [
      Tesla.Middleware.Headers,
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Curl, logger_level: :debug, redact_fields: ["authorization"]}
    ]
  end

  def client do
    Tesla.client(middleware())
  end

  def get_data(path) do
    Tesla.get(client(), path)
  end
end
```

Tesla executes middlewares in list order for requests (top-to-bottom), meaning Tesla.Middleware.Curl should
come after other middlewares that modify the request. For example, if you are using Tesla.Middleware.Headers
and Tesla.Middleware.JSON:

```elixir
# Correct order - Curl logs the final request with headers and JSON encoding
def middleware do
  [
    Tesla.Middleware.Headers,
    Tesla.Middleware.JSON,
    Tesla.Middleware.Curl
  ]
end

# Incorrect order - Curl won't see JSON encoding or headers
def middleware do
  [
    Tesla.Middleware.Curl,
    Tesla.Middleware.Headers,
    Tesla.Middleware.JSON
  ]
end
```

#### Standalone usage:
You can also use the `TeslaCurl` module directly with `log/2` without configuring it as middleware:

```elixir
defmodule HelloWorld do
  def foo(%Tesla.Env{} = env, opts \\ []) do
    Tesla.Middleware.Curl.log(env, opts)
  end
end
```

## Configuration Options

#### Field Redaction

To prevent sensitive information from being logged, use redact_fields to specify headers or body fields that should be redacted:

```elixir
{Tesla.Middleware.Curl, redact_fields: ["api_token", "authorization", "password"]}
```

Sensitive values will be replaced with `REDACTED` in the generated cURL command.

##### Using Regex Captures for Redaction

If the request body is a string (e.g., XML or JSON), you can redact values using regular expressions with capture groups, for example,
supplying `redact_fields: [~r{<password>(.*?)</password>}]` will result in `"<username>John Doe</username><password>REDACTED</password>"`

#### Follow Redirects

If you would like to enable the flag to follow redirects by default, supply `follow_redirects: true` in the options list.

#### Compressed

For compressed responses, you can supply the `compressed: true` option. This will add the `--compressed` flag to the curl command.

#### Logger Level

You can supply the `logger_level` option to set the level of the logger. The default is `:info`. Must be one of `:debug`, `:info`, `:warn`, `:error`, `:fatal`, `:none`.


## Best Practices
- **Avoid Logging Sensitive Data:** Always use redact_fields in production to prevent exposing secrets.
- **Use in Development & Debugging:** Consider enabling TeslaCurl only in non-production environments.
- **Define Middleware Order Correctly:** Place `Tesla.Middleware.Curl` after other middlewares that modify the request
(like `Tesla.Middleware.Headers` and `Tesla.Middleware.JSON`) to ensure it logs the final request state.

## License

The source code is under the MIT License. Copyright (c) 2023-2025 Colin Cromar.
