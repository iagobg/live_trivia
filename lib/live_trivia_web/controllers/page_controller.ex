defmodule LiveTriviaWeb.PageController do
  use LiveTriviaWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
