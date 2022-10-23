# TeslaCurl

Tesla Curl is a middleware for [Tesla](https://hex.pm/packages/tesla). It will log a curl command for each request.

## Installation

Add `:tesla_curl` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:tesla_curl, "~> 0.1.0"}
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

## License

The source code is under the MIT License. Copyright (c) 2022- Colin Cromar.