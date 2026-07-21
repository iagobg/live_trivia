defmodule LiveTriviaWeb.AdminLive do
  use LiveTriviaWeb, :live_view

  alias LiveTrivia.Game
  alias LiveTrivia.Lobby
  alias LiveTrivia.PlayerColors
  alias LiveTriviaWeb.Presence
  alias LiveTriviaWeb.RoomPresence
  import LiveTriviaWeb.TriviaComponents

  @example_questions [
    %{
      question: "European capital",
      answer: "Paris",
      hints: [
        "Largest city in France",
        "Starts with P",
        "_ I _ A _",
        "City of Light",
        "Sounds like pair is"
      ]
    },
    %{
      question: "Biggest living land mammal",
      answer: "Elephant",
      hints: [
        "It is grey",
        "Starts with E",
        "A_E__E__",
        "Said to have great memory",
        "Has a trunk"
      ]
    },
    %{
      question: "Largest ocean",
      answer: "Pacific",
      hints: [
        "Covers more than 60 million square miles",
        "Starts with P",
        "P_C_I_IC",
        "Contains the Mariana Trench",
        "Not Atlantic"
      ]
    },
    %{
      question: "Smallest prime number",
      answer: "Two",
      hints: ["Only even prime", "Starts with T", "T_W_", "One less than three", "A number"]
    },
    %{
      question: "Chemical symbol for gold",
      answer: "Au",
      hints: ["From Latin aurum", "Starts with A", "A_", "Found in jewelry", "Value by weight"]
    },
    %{
      question: "Fastest land animal",
      answer: "Cheetah",
      hints: [
        "Runs over 70 mph",
        "Starts with C",
        "C_E_E_A_",
        "Spotted cat from Africa",
        "Not a leopard"
      ]
    },
    %{
      question: "Capital of Japan",
      answer: "Tokyo",
      hints: [
        "Home to the emperor",
        "Starts with T",
        "T_K_Y_",
        "Formerly Edo",
        "Known for cherry blossoms"
      ]
    },
    %{
      question: "Hardest natural substance",
      answer: "Diamond",
      hints: ["Made of carbon", "Starts with D", "D_A_O_N_", "Used in drills", "Often in rings"]
    },
    %{
      question: "Largest planet in our solar system",
      answer: "Jupiter",
      hints: [
        "Great Red Spot",
        "Starts with J",
        "J_P_T_R",
        "Fifth from the Sun",
        "Named after a Roman god"
      ]
    },
    %{
      question: "Most abundant gas in Earth's atmosphere",
      answer: "Nitrogen",
      hints: [
        "About 78 percent of air",
        "Starts with N",
        "N_T_O_E_",
        "Used in fertilizers",
        "Symbol N2"
      ]
    }
  ]
  @preset_trivias [
    %{
      id: "historia",
      title: "História",
      description: "De grandes impérios a eventos que mudaram o mundo.",
      questions: [
        %{
          question: "Civilização Antiga",
          answer: "Império Romano",
          hints: [
            "Dominou territórios em três continentes diferentes simultaneamente",
            "Construiu uma rede de estradas e aquedutos impressionantes que existem até hoje",
            "Dividiu-se em duas partes (Ocidente e Oriente) antes de sua queda final",
            "Seus imperadores costumavam oferecer 'Pão e Circo' para a população",
            "Sua capital fica na Itália e abriga o Coliseu"
          ]
        },
        %{
          question: "Conflito Global",
          answer: "Guerra Fria",
          hints: [
            "Durou décadas, mas nunca teve um confronto militar direto e oficial entre os dois lados principais",
            "Dividiu o planeta nos conceitos de 'Primeiro Mundo', 'Segundo Mundo' e 'Terceiro Mundo'",
            "Envolveu uma corrida muito além das nuvens, rumo ao espaço",
            "Seus maiores símbolos foram a construção (e depois a queda) do Muro de Berlim",
            "Foi a disputa ideológica entre os Estados Unidos e a União Soviética"
          ]
        },
        %{
          question: "Figura Histórica Feminina",
          answer: "Cleópatra",
          hints: [
            "Foi a última governante ativa do Reino Ptolemaico",
            "Embora governasse um país africano, sua linhagem familiar original era grega (macedônia)",
            "Teve relacionamentos amorosos e políticos com Júlio César e Marco Antônio",
            "A lenda mais famosa diz que ela se suicidou após ser picada por uma cobra venenosa",
            "É a mais famosa rainha do Egito Antigo"
          ]
        },
        %{
          question: "Evento na História do Brasil",
          answer: "Chegada da Família Real Portuguesa",
          hints: [
            "Foi motivado por guerras intensas que aconteciam no continente europeu",
            "Foi um evento inédito: fez com que uma colônia passasse a sediar o próprio império que a dominava",
            "Trouxe como consequência imediata a Abertura dos Portos às 'Nações Amigas'",
            "Eles vieram ao Brasil fugindo das tropas de Napoleão Bonaparte",
            "Aconteceu em 1808 com o desembarque de Dom João VI no Rio de Janeiro"
          ]
        },
        %{
          question: "Invenção Histórica",
          answer: "Imprensa",
          hints: [
            "Revolucionou completamente a forma como a informação e as ideias circulavam no mundo",
            "Ajudou imensamente a espalhar os ideais da Reforma Protestante pela Europa",
            "Utilizava um sistema mecânico inovador de letras em peças móveis de metal",
            "O primeiro grande livro produzido em massa por ela foi a Bíblia",
            "Foi inventada por Johannes Gutenberg no século XV para imprimir textos no papel"
          ]
        },
        %{
          question: "Período Histórico",
          answer: "Renascimento",
          hints: [
            "Começou como um movimento local em cidades-estado e se espalhou por toda a Europa",
            "Valorizava a razão, a ciência e o resgate da cultura clássica (greco-romana)",
            "Marcou a transição da Idade Média para a Idade Moderna",
            "Foi financiado por mecenas e produziu gênios como Michelangelo e Galileu Galilei",
            "Foi o período cultural em que Leonardo da Vinci pintou a Mona Lisa"
          ]
        },
        %{
          question: "Estrutura Histórica",
          answer: "Muralha da China",
          hints: [
            "Demorou mais de dois milênios para ter todas as suas partes construídas e reconstruídas",
            "Ao contrário do que diz um famoso mito popular, ela não pode ser vista do espaço a olho nu",
            "Foi erguida com o objetivo de proteger um império de invasões de povos nômades",
            "É considerada a mais longa estrutura já construída pela humanidade",
            "É uma enorme fortificação localizada na... China"
          ]
        },
        %{
          question: "Império Pré-Colombiano",
          answer: "Incas",
          hints: [
            "Não possuíam um sistema de escrita tradicional, mas registravam informações usando cordões com nós chamados 'quipus'",
            "Seu território se estendia por quase toda a Cordilheira dos Andes, na América do Sul",
            "Eles foram conquistados pelos colonizadores espanhóis, liderados por Francisco Pizarro",
            "Falavam o idioma quíchua, que ainda é muito falado hoje em dia",
            "Construíram a famosa cidade de Machu Picchu, no Peru"
          ]
        }
      ]
    },
    %{
      id: "geografia",
      title: "Geografia",
      description:
        "Lugares, rios e formas do planeta com pistas para quem olha o mapa com calma.",
      questions: [
        %{
          question: "País Continental",
          answer: "Austrália",
          hints: [
            "É o sexto maior país do mundo em extensão territorial",
            "Uma enorme parte do seu interior é uma região árida e desértica conhecida como 'Outback'",
            "É o lar da Grande Barreira de Corais, que pode ser vista até do espaço",
            "Não chega a ser um continente inteiro por si só, mas domina quase toda a Oceania",
            "É a terra natal dos coalas e dos cangurus"
          ]
        },
        %{
          question: "Corpo d'Água",
          answer: "Rio Amazonas",
          hints: [
            "Suas nascentes ficam no alto da Cordilheira dos Andes, no Peru",
            "Durante muitos anos disputou com o Nilo o título de mais longo do mundo",
            "Possui, de longe, a maior bacia hidrográfica e o maior volume de água do planeta",
            "Nele ocorre o famoso fenômeno do encontro das águas (Rios Negro e Solimões) e a pororoca",
            "Fica no norte do Brasil e cruza a gigantesca floresta que leva seu nome"
          ]
        },
        %{
          question: "Nação Asiática",
          answer: "Japão",
          hints: [
            "É um arquipélago formado por quase 7 mil ilhas, embora as quatro maiores concentrem quase tudo",
            "Sofre constantemente com terremotos e tsunamis por estar localizado no Círculo de Fogo do Pacífico",
            "Sua cultura exporta fortemente mangás, sushis e samurais",
            "É mundialmente conhecido pela alcunha de 'A Terra do Sol Nascente'",
            "Sua capital é Tóquio e o país é famoso pelas animações (animes)"
          ]
        },
        %{
          question: "Formação Geográfica",
          answer: "Deserto do Saara",
          hints: [
            "Estudos indicam que, há milhares de anos, essa região era verde, úmida e cheia de lagos",
            "Suas areias são levadas pelo vento por cima do oceano até a Amazônia para fertilizá-la",
            "É tão grande que atravessa o território de mais de 10 países diferentes no mesmo continente",
            "É o maior deserto do mundo na categoria 'quente'",
            "Cobre grande parte do Norte da África com suas dunas gigantescas de areia e camelos"
          ]
        },
        %{
          question: "País da América do Norte",
          answer: "Canadá",
          hints: [
            "Possui a maior linha costeira (litoral) entre todos os países do mundo",
            "Sua economia, política e cultura têm forte influência de duas línguas oficiais: inglês e francês",
            "Em área total, é o segundo maior país de todo o planeta",
            "Sua bandeira exibe orgulhosamente uma folha vermelha de bordo (Maple)",
            "Fica no extremo norte da América, logo acima (fazendo fronteira) com os Estados Unidos"
          ]
        },
        %{
          question: "Cidade Histórica e Estratégica",
          answer: "Istambul",
          hints: [
            "Na antiguidade, antes de ser o centro de um império, a cidade era chamada de Bizâncio",
            "Foi a grandiosa capital do Império Romano do Oriente e, depois, do Império Otomano",
            "Geograficamente, é dividida ao meio pelo famoso Estreito de Bósforo",
            "É a única grande metrópole do mundo que fica oficialmente dividida em dois continentes (Europa e Ásia)",
            "É a maior e mais famosa cidade da Turquia"
          ]
        },
        %{
          question: "Estado Soberano",
          answer: "Vaticano",
          hints: [
            "Possui sua própria rede de correios, moeda, estação de rádio e banco central",
            "A segurança pessoal de seu chefe de estado é feita por uma força chamada Guarda Suíça",
            "Todo o seu pequeno território é oficialmente classificado como Patrimônio Mundial da Humanidade",
            "Em termos de área territorial e população, é o menor país independente do mundo",
            "É um enclave cercado pela cidade de Roma (Itália) e serve como a casa do Papa"
          ]
        },
        %{
          question: "Elevação Geográfica",
          answer: "Monte Everest",
          hints: [
            "Sua altitude total continua crescendo alguns milímetros por ano por causa da colisão de placas tectônicas",
            "Fica localizado exatamente na fronteira entre o Nepal e a China (região do Tibete)",
            "Existem centenas de corpos de alpinistas congelados que servem como pontos de referência macabros",
            "Mede cerca de 8.848 metros de altura e fica na famosa Cordilheira do Himalaia",
            "É o ponto mais alto de todo o planeta Terra em relação ao nível do mar"
          ]
        }
      ]
    },
    %{
      id: "esportes",
      title: "Esportes",
      description:
        "Futebol, Olimpíadas e cultura esportiva com Brasil no radar sem virar prova de almanaque.",
      questions: [
        %{
          question: "Atleta Histórico",
          answer: "Pelé",
          hints: [
            "Iniciou sua carreira profissional no Santos Futebol Clube",
            "Foi um dos responsáveis por paralisar temporariamente uma guerra na Nigéria",
            "Marcou mais de mil gols ao longo de sua trajetória profissional",
            "É o único jogador da história a vencer três Copas do Mundo",
            "É mundialmente conhecido como o 'Rei do Futebol'"
          ]
        },
        %{
          question: "Atleta Olímpico",
          answer: "Michael Phelps",
          hints: [
            "Participou de cinco edições diferentes dos Jogos Olímpicos",
            "Tem uma envergadura de 2,01m e calça impressionantes tamanho 43",
            "É o atleta olímpico mais condecorado de todos os tempos, quebrando recordes milenares",
            "Seu esporte de domínio envolve muita água, técnica e toucas",
            "É um nadador americano que conquistou 23 medalhas de ouro"
          ]
        },
        %{
          question: "Evento Esportivo",
          answer: "Super Bowl",
          hints: [
            "Possui os espaços publicitários mais caros de toda a televisão mundial",
            "Acontece tradicionalmente sempre em um domingo, gerando um consumo altíssimo de comida",
            "É conhecido por ter um show espetacular e milionário no intervalo da partida",
            "Decide qual equipe leva o Troféu Vince Lombardi da NFL",
            "É a grande final anual do campeonato de futebol americano"
          ]
        },
        %{
          question: "Esporte de Raquete",
          answer: "Tênis",
          hints: [
            "Seus quatro torneios mais importantes do ano formam o circuito 'Grand Slam'",
            "O sistema de pontuação é bem diferentão: vai de 15, para 30, depois 40...",
            "Pode ser jogado em diferentes superfícies: saibro, grama ou quadra dura",
            "Roger Federer, Rafael Nadal e Serena Williams são lendas absolutas desse esporte",
            "Você usa uma raquete com cordas para rebater uma bolinha amarela por cima de uma rede"
          ]
        },
        %{
          question: "Competição Esportiva",
          answer: "Fórmula 1",
          hints: [
            "Possui uma das provas mais famosas e luxuosas nas ruas do Principado de Mônaco",
            "É administrada e regida internacionalmente pela FIA",
            "Possui equipes mecânicas que conseguem trocar pneus em menos de 3 segundos",
            "Ayrton Senna conquistou três títulos mundiais nela",
            "É a categoria máxima do automobilismo, com os carros de corrida mais rápidos do mundo"
          ]
        },
        %{
          question: "Arte Marcial",
          answer: "Judô",
          hints: [
            "Foi criado no Japão no final do século XIX por Jigoro Kano",
            "Seu nome, em tradução literal para o português, significa 'caminho suave'",
            "Não utiliza socos ou chutes; o foco é em projeções, quedas e imobilizações no solo",
            "A pontuação máxima e que encerra a luta imediatamente se chama 'Ippon'",
            "Os praticantes usam um quimono branco ou azul com faixas coloridas que indicam o nível"
          ]
        },
        %{
          question: "Esporte em Equipe",
          answer: "Vôlei",
          hints: [
            "Originalmente, quando foi inventado em 1895, se chamava 'Mintonette'",
            "Possui uma posição exclusivamente de defesa chamada 'Líbero', que usa um uniforme de cor diferente",
            "É expressamente proibido invadir a quadra do adversário durante o jogo",
            "Os times podem dar no máximo três toques na bola antes de mandá-la para o outro lado",
            "O objetivo é fazer a bola passar por cima da rede e tocar no chão da quadra adversária"
          ]
        },
        %{
          question: "Esporte de Precisão",
          answer: "Golfe",
          hints: [
            "É um dos raros esportes em que o vencedor é justamente quem faz a menor quantidade de pontos",
            "É praticado em enormes campos abertos ao ar livre que possuem muitos lagos e caixas de areia",
            "Woods é o sobrenome do seu atleta mais famoso do mundo (Tiger)",
            "Uma partida padrão exige que o jogador passe por um circuito de 18 'buracos'",
            "O jogador usa diferentes tipos de tacos de metal para bater em uma pequena bolinha branca"
          ]
        }
      ]
    }
  ]
  @synthetic_player_count 16
  @synthetic_test_cycles 5
  @synthetic_keystroke_limit 18
  @synthetic_tick_ms 100
  @synthetic_submitted_clear_delay_ms 2_000
  @synthetic_client_start_delay_ms 100

  def demo_questions, do: @example_questions
  def preset_trivias, do: @preset_trivias

  def preset_questions(preset_id) do
    @preset_trivias
    |> Enum.find(&(&1.id == preset_id))
    |> case do
      nil -> nil
      preset -> preset.questions
    end
  end

  @impl true
  def mount(%{"room_id" => room_id} = params, session, socket) do
    player_id = Map.fetch!(session, "player_id")
    room = Lobby.get_room(room_id)

    cond do
      is_nil(room) ->
        {:ok,
         socket
         |> put_flash(:error, "This room was closed.")
         |> push_navigate(to: ~p"/")}

      room.admin_id != player_id ->
        {:ok, push_navigate(socket, to: ~p"/rooms/#{room_id}")}

      true ->
        benchmark_auto_run? = params["benchmark"] == "synthetic"

        if connected?(socket) do
          Game.subscribe(room_id)
          RoomPresence.subscribe(room_id)
          RoomPresence.track_admin(room_id, player_id)
          Lobby.touch_room(room_id)

          if benchmark_auto_run? do
            Process.send_after(self(), :prepare_synthetic_benchmark, 300)
          end
        end

        socket =
          socket
          |> assign(:page_title, "Admin - #{room.name}")
          |> assign(:room, room)
          |> assign(:room_id, room_id)
          |> assign(:player_id, player_id)
          |> assign(:game_state, Game.get_state(room_id))
          |> assign(:players, RoomPresence.players(room_id))
          |> assign(:synthetic_players, [])
          |> assign(:synthetic_test_running?, benchmark_auto_run?)
          |> assign(:benchmark_auto_run?, benchmark_auto_run?)
          |> assign(:json_text, Jason.encode!(demo_questions(), pretty: true))
          |> assign(:validation_error, nil)

        {:ok, socket}
    end
  end

  def mount(_params, _session, socket) do
    {:ok, push_navigate(socket, to: ~p"/")}
  end

  @impl true
  def terminate(_reason, socket) do
    if socket.assigns[:room_id] && socket.assigns[:player_id] do
      untrack_synthetic_players(socket.assigns.room_id, socket.assigns[:synthetic_players] || [])

      Presence.untrack(
        self(),
        RoomPresence.admins_topic(socket.assigns.room_id),
        socket.assigns.player_id
      )

      Lobby.admin_left(socket.assigns.room_id)
    end

    :ok
  end

  @impl true
  def handle_event("load_demo", _params, socket) do
    questions = demo_questions()
    Game.load_questions(socket.assigns.room_id, questions)
    Lobby.touch_room(socket.assigns.room_id)

    {:noreply,
     socket
     |> assign(:json_text, Jason.encode!(questions, pretty: true))
     |> assign(:validation_error, nil)}
  end

  def handle_event("load_preset", %{"id" => preset_id}, socket) do
    case preset_questions(preset_id) do
      nil ->
        {:noreply, assign(socket, :validation_error, "Preset not found")}

      questions ->
        Game.load_questions(socket.assigns.room_id, questions)
        Lobby.touch_room(socket.assigns.room_id)

        {:noreply,
         socket
         |> assign(:json_text, Jason.encode!(questions, pretty: true))
         |> assign(:validation_error, nil)}
    end
  end

  def handle_event("run_synthetic_render_test", _params, socket) do
    {:noreply, start_synthetic_test(socket, benchmark?: false)}
  end

  def handle_event("synthetic_submit", %{"cycle" => cycle}, socket) do
    cycle = parse_synthetic_cycle(cycle)
    {:noreply, broadcast_synthetic_submit(socket, socket.assigns.synthetic_players, cycle)}
  end

  def handle_event("synthetic_test_finished", params, socket) do
    emit_synthetic_client_summary(socket, params)
    {:noreply, assign(socket, :synthetic_test_running?, false)}
  end

  def handle_event("load_json", %{"quiz" => %{"json" => json}}, socket) do
    case decode_questions(json) do
      {:ok, questions} ->
        Game.load_questions(socket.assigns.room_id, questions)
        Lobby.touch_room(socket.assigns.room_id)

        {:noreply,
         socket
         |> assign(:json_text, json)
         |> assign(:validation_error, nil)}

      {:error, error} ->
        {:noreply, assign(socket, :validation_error, error)}
    end
  end

  def handle_event("start", _params, socket) do
    Game.start_quiz(socket.assigns.room_id)
    {:noreply, socket}
  end

  def handle_event("next", _params, socket) do
    Game.next_round(socket.assigns.room_id)
    {:noreply, socket}
  end

  def handle_event("reset", _params, socket) do
    Game.force_reset(socket.assigns.room_id)
    {:noreply, socket}
  end

  def handle_event("close_room", _params, socket) do
    Lobby.close_room(socket.assigns.room_id)

    {:noreply,
     socket
     |> put_flash(:info, "Room closed.")
     |> push_navigate(to: ~p"/")}
  end

  @impl true
  def handle_info(:prepare_synthetic_benchmark, socket) do
    if socket.assigns.benchmark_auto_run? do
      Game.load_questions(socket.assigns.room_id, demo_questions())
      Game.start_quiz(socket.assigns.room_id)
      Process.send_after(self(), :run_synthetic_benchmark, 300)
    end

    {:noreply, socket}
  end

  def handle_info(:run_synthetic_benchmark, socket) do
    if socket.assigns.benchmark_auto_run? do
      {:noreply, start_synthetic_test(socket, benchmark?: true)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:run_synthetic_typing_test, config}, socket) do
    {:noreply, push_event(socket, "run_synthetic_typing_test", config)}
  end

  def handle_info({:game_state, game_state}, socket) do
    {:noreply, assign(socket, :game_state, game_state)}
  end

  def handle_info({:room_closed, _room_id}, socket) do
    {:noreply,
     socket
     |> put_flash(:error, "This room was closed.")
     |> push_navigate(to: ~p"/")}
  end

  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket),
    do: {:noreply, assign(socket, :players, admin_players(socket))}

  def handle_info({:synthetic_clear_submitted, player_id, bubble_id}, socket) do
    broadcast_synthetic_cleared(socket.assigns.room_id, player_id, bubble_id)

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <%= if @game_state.phase == :podium do %>
        <.admin_header
          room={@room}
          game_state={@game_state}
          validation_error={@validation_error}
          synthetic_test_running?={@synthetic_test_running?}
        />
        <.podium game_state={@game_state} players={@players} />
      <% else %>
        <.admin_header
          room={@room}
          game_state={@game_state}
          validation_error={@validation_error}
          synthetic_test_running?={@synthetic_test_running?}
        />
        <.game_stage
          game_state={@game_state}
          players={@players}
          current_player_id={nil}
          room_id={@room_id}
        />
      <% end %>

      <div class="fixed bottom-4 right-4 z-50 max-h-[calc(100svh-6rem)] w-[min(42rem,calc(100vw-2rem))] overflow-y-auto rounded-xl border border-gray-700 bg-gray-900/95 p-3 text-white shadow-2xl">
        <.form for={%{}} as={:quiz} phx-submit="load_json" class="space-y-3">
          <div class="grid gap-2 sm:grid-cols-3">
            <button
              :for={preset <- preset_trivias()}
              type="button"
              phx-click="load_preset"
              phx-value-id={preset.id}
              class="rounded-lg border border-indigo-400/30 bg-indigo-500/10 px-3 py-2 text-left transition hover:border-indigo-300 hover:bg-indigo-500/20"
            >
              <span class="block text-sm font-bold text-indigo-100">{preset.title}</span>
              <span class="mt-1 block text-xs leading-snug text-gray-400">{preset.description}</span>
            </button>
          </div>

          <textarea
            name="quiz[json]"
            class="h-32 w-full rounded-lg border border-gray-700 bg-gray-950 p-3 font-mono text-xs text-gray-200 outline-none focus:border-indigo-500"
          >{@json_text}</textarea>
          <div class="flex flex-wrap items-center gap-2">
            <button
              type="submit"
              class="rounded-lg bg-indigo-700 px-3 py-1.5 text-sm font-semibold hover:bg-indigo-600"
            >
              Load JSON
            </button>
            <button
              type="button"
              phx-click="load_demo"
              class="rounded-lg bg-gray-700 px-3 py-1.5 text-sm hover:bg-gray-600"
            >
              Demo EN
            </button>
            <span :if={@validation_error} class="text-xs text-red-400">{@validation_error}</span>
          </div>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  attr :game_state, :map, required: true
  attr :room, :map, required: true
  attr :validation_error, :string, default: nil
  attr :synthetic_test_running?, :boolean, default: false

  def admin_header(assigns) do
    ~H"""
    <div class="fixed left-0 right-0 top-0 z-50 border-b border-gray-700 bg-gray-900/95 px-4 py-2 text-white">
      <div class="flex flex-wrap items-center gap-3">
        <Layouts.logo show_name={false} mark_class="h-8 w-8 rounded-lg" />
        <span class="mr-2 text-sm font-bold text-indigo-300">ADMIN</span>
        <span class="rounded-full bg-indigo-500/15 px-2 py-1 text-xs font-semibold text-indigo-200">
          {@room.name}
        </span>
        <span class="rounded-full bg-gray-700 px-2 py-1 text-xs font-medium text-gray-300">
          {@game_state.phase |> Atom.to_string() |> String.replace("_", " ") |> String.upcase()}
          <%= if @game_state.phase == :in_progress do %>
            - Q{@game_state.current_index + 1}/{length(@game_state.questions)}
          <% end %>
        </span>
        <div class="flex-1" />
        <button
          phx-click="run_synthetic_render_test"
          disabled={@synthetic_test_running?}
          class="rounded-lg bg-sky-800 px-3 py-1.5 text-sm font-medium hover:bg-sky-700 disabled:cursor-not-allowed disabled:opacity-30"
        >
          16-player test
        </button>
        <button
          phx-click="start"
          disabled={@game_state.phase != :loaded}
          class="rounded-lg bg-green-700 px-3 py-1.5 text-sm font-medium hover:bg-green-600 disabled:cursor-not-allowed disabled:opacity-30"
        >
          Start Quiz
        </button>
        <button
          phx-click="next"
          disabled={@game_state.phase not in [:in_progress, :results]}
          class="rounded-lg bg-yellow-700 px-3 py-1.5 text-sm font-medium hover:bg-yellow-600 disabled:cursor-not-allowed disabled:opacity-30"
        >
          Next Round
        </button>
        <button
          phx-click="reset"
          class="rounded-lg bg-red-800 px-3 py-1.5 text-sm font-medium hover:bg-red-700"
        >
          Force Reset
        </button>
        <button
          phx-click="close_room"
          data-confirm="Close this room?"
          class="rounded-lg bg-gray-800 px-3 py-1.5 text-sm font-medium hover:bg-gray-700"
        >
          Close Room
        </button>
      </div>
    </div>
    """
  end

  defp decode_questions(json) do
    with {:ok, decoded} <- Jason.decode(json),
         true <- is_list(decoded) || {:error, "JSON must be an array of questions"} do
      decoded
      |> Enum.with_index(1)
      |> Enum.reduce_while({:ok, []}, fn {item, index}, {:ok, questions} ->
        case normalize_question(item, index) do
          {:ok, question} -> {:cont, {:ok, [question | questions]}}
          {:error, error} -> {:halt, {:error, error}}
        end
      end)
      |> case do
        {:ok, questions} -> {:ok, Enum.reverse(questions)}
        error -> error
      end
    else
      {:error, %Jason.DecodeError{}} -> {:error, "Invalid JSON"}
      {:error, error} -> {:error, error}
    end
  end

  defp normalize_question(%{"question" => question, "answer" => answer} = item, _index) do
    hints =
      item
      |> Map.get("hints", [])
      |> List.wrap()
      |> Enum.map(&to_string/1)
      |> Enum.take(5)
      |> pad_hints()

    {:ok, %{question: to_string(question), answer: to_string(answer), hints: hints}}
  end

  defp normalize_question(_item, index),
    do: {:error, "Question #{index} is missing question or answer"}

  defp pad_hints(hints) do
    hints ++ Enum.map((length(hints) + 1)..5//1, &"Hint #{&1}")
  end

  defp start_synthetic_test(socket, opts) do
    synthetic_players = synthetic_players()
    untrack_synthetic_players(socket.assigns.room_id, socket.assigns.synthetic_players)
    track_synthetic_players(socket.assigns.room_id, synthetic_players)

    config = %{
      players: synthetic_players,
      guesses: synthetic_guesses(),
      cycles: @synthetic_test_cycles,
      tick_ms: @synthetic_tick_ms,
      keystroke_limit: @synthetic_keystroke_limit,
      benchmark: Keyword.get(opts, :benchmark?, false),
      room_id: socket.assigns.room_id
    }

    Process.send_after(
      self(),
      {:run_synthetic_typing_test, config},
      @synthetic_client_start_delay_ms
    )

    socket
    |> assign(:synthetic_players, synthetic_players)
    |> assign(:players, admin_players(socket, synthetic_players))
    |> assign(:synthetic_test_running?, true)
  end

  defp admin_players(socket, synthetic_players \\ nil) do
    synthetic_players = synthetic_players || socket.assigns.synthetic_players || []
    real_players = RoomPresence.players(socket.assigns.room_id)
    synthetic_ids = synthetic_players |> Enum.map(& &1.player_id) |> MapSet.new()

    real_players
    |> Enum.reject(&MapSet.member?(synthetic_ids, &1.player_id))
    |> Kernel.++(synthetic_players)
    |> Enum.sort_by(& &1.joined_at)
  end

  defp emit_synthetic_client_summary(socket, params) when is_map(params) do
    if Map.get(params, "benchmark") do
      :telemetry.execute(
        [:live_trivia, :synthetic_benchmark, :client_summary],
        %{
          samples: parse_number(params["samples"], 0),
          avg_ms: parse_number(params["avg_ms"], 0.0),
          p50_ms: parse_number(params["p50_ms"], 0.0),
          p95_ms: parse_number(params["p95_ms"], 0.0),
          p99_ms: parse_number(params["p99_ms"], 0.0),
          max_ms: parse_number(params["max_ms"], 0.0),
          receive_p95_ms: parse_number(params["receive_p95_ms"], 0.0),
          receive_p99_ms: parse_number(params["receive_p99_ms"], 0.0),
          dom_p95_ms: parse_number(params["dom_p95_ms"], 0.0),
          dom_p99_ms: parse_number(params["dom_p99_ms"], 0.0),
          duration_ms: parse_number(params["duration_ms"], 0.0)
        },
        %{room_id: socket.assigns.room_id}
      )
    end
  end

  defp emit_synthetic_client_summary(_socket, _params), do: :ok

  defp parse_number(value, _default) when is_number(value), do: value

  defp parse_number(value, default) when is_binary(value) do
    case Float.parse(value) do
      {number, _rest} -> number
      :error -> default
    end
  end

  defp parse_number(_value, default), do: default

  defp synthetic_players do
    colors = PlayerColors.all()

    Enum.map(1..@synthetic_player_count, fn index ->
      %{
        player_id: "synthetic-#{index}",
        name: "Bot #{index}",
        color: Enum.at(colors, index - 1),
        joined_at: index
      }
    end)
  end

  defp track_synthetic_players(room_id, synthetic_players) do
    Enum.each(synthetic_players, fn player ->
      Presence.track(self(), RoomPresence.players_topic(room_id), player.player_id, player)
    end)
  end

  defp untrack_synthetic_players(_room_id, []), do: :ok

  defp untrack_synthetic_players(room_id, synthetic_players) do
    Enum.each(synthetic_players, fn player ->
      Presence.untrack(self(), RoomPresence.players_topic(room_id), player.player_id)
    end)
  end

  defp broadcast_synthetic_submit(socket, synthetic_players, cycle) do
    Enum.each(synthetic_players, fn player ->
      bubble_id = "synthetic-#{System.unique_integer([:positive, :monotonic])}"
      guess_text = synthetic_guess_text(player, cycle)

      Game.submit_guess(
        socket.assigns.room_id,
        player.player_id,
        player.name,
        guess_text
      )

      broadcast_synthetic_submitted(
        socket.assigns.room_id,
        player,
        guess_text,
        bubble_id
      )

      Process.send_after(
        self(),
        {:synthetic_clear_submitted, player.player_id, bubble_id},
        @synthetic_submitted_clear_delay_ms
      )
    end)

    socket
  end

  defp broadcast_synthetic_submitted(room_id, player, text, bubble_id) do
    LiveTriviaWeb.Endpoint.broadcast(
      RoomPresence.typing_topic(room_id),
      "s",
      %{i: synthetic_index(player) - 1, t: text, b: bubble_id}
    )
  end

  defp broadcast_synthetic_cleared(room_id, player_id, bubble_id) do
    LiveTriviaWeb.Endpoint.broadcast(
      RoomPresence.typing_topic(room_id),
      "c",
      %{i: synthetic_index(%{player_id: player_id}) - 1, b: bubble_id}
    )
  end

  defp synthetic_guesses do
    [
      "montanha azul",
      "paises baixos distante",
      "paralelepipedo muito comprido",
      "cidade inventada",
      "elemento secreto",
      "capital escondida longe"
    ]
  end

  defp synthetic_guess_text(player, cycle) do
    guesses = synthetic_guesses()
    Enum.at(guesses, rem(cycle + synthetic_index(player), length(guesses)))
  end

  defp synthetic_index(%{player_id: "synthetic-" <> index}), do: String.to_integer(index)

  defp parse_synthetic_cycle(cycle) when is_integer(cycle), do: cycle

  defp parse_synthetic_cycle(cycle) when is_binary(cycle) do
    case Integer.parse(cycle) do
      {cycle, _rest} -> cycle
      :error -> 0
    end
  end

  defp parse_synthetic_cycle(_cycle), do: 0
end
