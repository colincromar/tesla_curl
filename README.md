# TeslaCurl

Tesla Curl is a middleware for [Tesla](https://hex.pm/packages/tesla). It will log a curl command for each request.

This has not officially released yet, but you can use it by adding the following to your `mix.exs` file:

```elixir

## Installation

Add `:tesla_curl` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:tesla_curl, git: "https://github.com/colincromar/tesla_curl.git", branch: "main"}
  ]
end
```

## Usage

```elixir
defmodule HelloWorld do
  use Tesla

  plug Tesla.Middleware.Curl
end
```

This middleware supports field redaction. You can pass a list of header keys or body field keys to be redacted in the options. 
For example:

```elixir
defmodule HelloWorld do
  use Tesla

  plug Tesla.Middleware.Curl, redact_fields: ["api_token", "authorization", "password"]
end
```

If supplied, the redacted fields will be replaced with `[REDACTED]` in the curl command.

## License

The source code is under the MIT License. Copyright (c) 2022- Colin Cromar.