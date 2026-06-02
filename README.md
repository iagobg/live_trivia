# LiveTrivia

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:3070`](http://localhost:4010) from your browser.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://hexdocs.pm/phoenix/overview.html
* Docs: https://hexdocs.pm/phoenix
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix


## Dockerfile Set up
* Run 
```
docker build -t live-trivia .
docker run -d \
  --name live-trivia \
  -p 3070:3070 \
  -e SECRET_KEY_BASE="your_secret_key" \
  -e PHX_HOST="your-domain.com" \
  live-trivia
  ```

