# The cards Matching Pairs can deal. Only names and codes live here: images load in the browser
# straight from public CDNs (Twemoji for animals/objects, flagcdn for flags), numbers are plain text.
module GameServices::MatchingPairs::Catalog
  TWEMOJI_URL = "https://cdn.jsdelivr.net/gh/jdecked/twemoji@15.1.0/assets/svg/%s.svg".freeze
  FLAG_URL    = "https://flagcdn.com/w160/%s.png".freeze

  # key => [label, Twemoji codepoint]
  ANIMALS = {
    "dog" => [ "Dog", "1f436" ], "cat" => [ "Cat", "1f431" ], "mouse" => [ "Mouse", "1f42d" ],
    "hamster" => [ "Hamster", "1f439" ], "rabbit" => [ "Rabbit", "1f430" ], "fox" => [ "Fox", "1f98a" ],
    "bear" => [ "Bear", "1f43b" ], "panda" => [ "Panda", "1f43c" ], "koala" => [ "Koala", "1f428" ],
    "tiger" => [ "Tiger", "1f42f" ], "lion" => [ "Lion", "1f981" ], "cow" => [ "Cow", "1f42e" ],
    "pig" => [ "Pig", "1f437" ], "frog" => [ "Frog", "1f438" ], "monkey" => [ "Monkey", "1f435" ],
    "chicken" => [ "Chicken", "1f414" ], "penguin" => [ "Penguin", "1f427" ], "chick" => [ "Chick", "1f424" ],
    "duck" => [ "Duck", "1f986" ], "eagle" => [ "Eagle", "1f985" ], "owl" => [ "Owl", "1f989" ],
    "bat" => [ "Bat", "1f987" ], "wolf" => [ "Wolf", "1f43a" ], "horse" => [ "Horse", "1f434" ],
    "unicorn" => [ "Unicorn", "1f984" ], "bee" => [ "Bee", "1f41d" ], "butterfly" => [ "Butterfly", "1f98b" ],
    "snail" => [ "Snail", "1f40c" ], "ladybug" => [ "Ladybug", "1f41e" ], "turtle" => [ "Turtle", "1f422" ],
    "snake" => [ "Snake", "1f40d" ], "lizard" => [ "Lizard", "1f98e" ], "t_rex" => [ "T-Rex", "1f996" ],
    "octopus" => [ "Octopus", "1f419" ], "crab" => [ "Crab", "1f980" ], "blowfish" => [ "Blowfish", "1f421" ],
    "tropical_fish" => [ "Tropical Fish", "1f420" ], "dolphin" => [ "Dolphin", "1f42c" ], "whale" => [ "Whale", "1f433" ],
    "shark" => [ "Shark", "1f988" ], "crocodile" => [ "Crocodile", "1f40a" ], "zebra" => [ "Zebra", "1f993" ],
    "giraffe" => [ "Giraffe", "1f992" ], "elephant" => [ "Elephant", "1f418" ], "camel" => [ "Camel", "1f42a" ],
    "kangaroo" => [ "Kangaroo", "1f998" ], "peacock" => [ "Peacock", "1f99a" ], "parrot" => [ "Parrot", "1f99c" ],
    "flamingo" => [ "Flamingo", "1f9a9" ], "sloth" => [ "Sloth", "1f9a5" ], "otter" => [ "Otter", "1f9a6" ],
    "hedgehog" => [ "Hedgehog", "1f994" ], "gorilla" => [ "Gorilla", "1f98d" ]
  }.freeze

  OBJECTS = {
    "apple" => [ "Apple", "1f34e" ], "banana" => [ "Banana", "1f34c" ], "grapes" => [ "Grapes", "1f347" ],
    "watermelon" => [ "Watermelon", "1f349" ], "strawberry" => [ "Strawberry", "1f353" ], "pineapple" => [ "Pineapple", "1f34d" ],
    "cherries" => [ "Cherries", "1f352" ], "lemon" => [ "Lemon", "1f34b" ], "pizza" => [ "Pizza", "1f355" ],
    "burger" => [ "Burger", "1f354" ], "hot_dog" => [ "Hot Dog", "1f32d" ], "taco" => [ "Taco", "1f32e" ],
    "donut" => [ "Donut", "1f369" ], "cookie" => [ "Cookie", "1f36a" ], "cake" => [ "Cake", "1f382" ],
    "ice_cream" => [ "Ice Cream", "1f366" ], "lollipop" => [ "Lollipop", "1f36d" ], "popcorn" => [ "Popcorn", "1f37f" ],
    "soccer_ball" => [ "Soccer Ball", "26bd" ], "basketball" => [ "Basketball", "1f3c0" ], "football" => [ "Football", "1f3c8" ],
    "tennis" => [ "Tennis Ball", "1f3be" ], "guitar" => [ "Guitar", "1f3b8" ], "trumpet" => [ "Trumpet", "1f3ba" ],
    "drum" => [ "Drum", "1f941" ], "balloon" => [ "Balloon", "1f388" ], "gift" => [ "Gift", "1f381" ],
    "crown" => [ "Crown", "1f451" ], "glasses" => [ "Glasses", "1f453" ], "top_hat" => [ "Top Hat", "1f3a9" ],
    "umbrella" => [ "Umbrella", "2602" ], "key" => [ "Key", "1f511" ], "lock" => [ "Lock", "1f512" ],
    "light_bulb" => [ "Light Bulb", "1f4a1" ], "rocket" => [ "Rocket", "1f680" ], "car" => [ "Car", "1f697" ],
    "bus" => [ "Bus", "1f68c" ], "bicycle" => [ "Bicycle", "1f6b2" ], "airplane" => [ "Airplane", "2708" ],
    "sailboat" => [ "Sailboat", "26f5" ], "anchor" => [ "Anchor", "2693" ], "alarm_clock" => [ "Alarm Clock", "23f0" ],
    "hourglass" => [ "Hourglass", "231b" ], "camera" => [ "Camera", "1f4f7" ], "laptop" => [ "Laptop", "1f4bb" ],
    "books" => [ "Books", "1f4da" ], "pencil" => [ "Pencil", "270f" ], "scissors" => [ "Scissors", "2702" ],
    "hammer" => [ "Hammer", "1f528" ], "magnet" => [ "Magnet", "1f9f2" ], "teddy_bear" => [ "Teddy Bear", "1f9f8" ],
    "puzzle" => [ "Puzzle Piece", "1f9e9" ], "dice" => [ "Dice", "1f3b2" ], "trophy" => [ "Trophy", "1f3c6" ],
    "bell" => [ "Bell", "1f514" ], "rainbow" => [ "Rainbow", "1f308" ], "star" => [ "Star", "2b50" ],
    "moon" => [ "Moon", "1f319" ], "snowman" => [ "Snowman", "26c4" ], "fire" => [ "Fire", "1f525" ]
  }.freeze

  # ISO 3166-1 alpha-2 code => country name
  FLAGS = {
    "ar" => "Argentina", "au" => "Australia", "at" => "Austria", "be" => "Belgium", "bo" => "Bolivia",
    "br" => "Brazil", "ca" => "Canada", "cl" => "Chile", "cn" => "China", "co" => "Colombia",
    "cr" => "Costa Rica", "hr" => "Croatia", "cu" => "Cuba", "cz" => "Czechia", "dk" => "Denmark",
    "ec" => "Ecuador", "eg" => "Egypt", "fi" => "Finland", "fr" => "France", "de" => "Germany",
    "gr" => "Greece", "in" => "India", "ie" => "Ireland", "il" => "Israel", "it" => "Italy",
    "jm" => "Jamaica", "jp" => "Japan", "ke" => "Kenya", "mx" => "Mexico", "ma" => "Morocco",
    "nl" => "Netherlands", "nz" => "New Zealand", "ng" => "Nigeria", "no" => "Norway", "pa" => "Panama",
    "py" => "Paraguay", "pe" => "Peru", "ph" => "Philippines", "pl" => "Poland", "pt" => "Portugal",
    "kr" => "South Korea", "za" => "South Africa", "es" => "Spain", "se" => "Sweden", "ch" => "Switzerland",
    "th" => "Thailand", "tr" => "Türkiye", "ua" => "Ukraine", "gb" => "United Kingdom", "us" => "United States",
    "uy" => "Uruguay", "ve" => "Venezuela", "vn" => "Vietnam"
  }.freeze

  # Card names in Spanish rooms (the image alt text), by card key. Numbers need none.
  LABELS = {
    "es" => {
      "animals" => {
        "dog" => "Perro", "cat" => "Gato", "mouse" => "Ratón", "hamster" => "Hámster", "rabbit" => "Conejo",
        "fox" => "Zorro", "bear" => "Oso", "panda" => "Panda", "koala" => "Koala", "tiger" => "Tigre",
        "lion" => "León", "cow" => "Vaca", "pig" => "Cerdo", "frog" => "Rana", "monkey" => "Mono",
        "chicken" => "Gallina", "penguin" => "Pingüino", "chick" => "Pollito", "duck" => "Pato", "eagle" => "Águila",
        "owl" => "Búho", "bat" => "Murciélago", "wolf" => "Lobo", "horse" => "Caballo", "unicorn" => "Unicornio",
        "bee" => "Abeja", "butterfly" => "Mariposa", "snail" => "Caracol", "ladybug" => "Mariquita", "turtle" => "Tortuga",
        "snake" => "Serpiente", "lizard" => "Lagartija", "t_rex" => "T-Rex", "octopus" => "Pulpo", "crab" => "Cangrejo",
        "blowfish" => "Pez globo", "tropical_fish" => "Pez tropical", "dolphin" => "Delfín", "whale" => "Ballena",
        "shark" => "Tiburón", "crocodile" => "Cocodrilo", "zebra" => "Cebra", "giraffe" => "Jirafa",
        "elephant" => "Elefante", "camel" => "Camello", "kangaroo" => "Canguro", "peacock" => "Pavo real",
        "parrot" => "Loro", "flamingo" => "Flamenco", "sloth" => "Perezoso", "otter" => "Nutria",
        "hedgehog" => "Erizo", "gorilla" => "Gorila"
      },
      "objects" => {
        "apple" => "Manzana", "banana" => "Banano", "grapes" => "Uvas", "watermelon" => "Sandía",
        "strawberry" => "Fresa", "pineapple" => "Piña", "cherries" => "Cerezas", "lemon" => "Limón", "pizza" => "Pizza",
        "burger" => "Hamburguesa", "hot_dog" => "Perro caliente", "taco" => "Taco", "donut" => "Dona",
        "cookie" => "Galleta", "cake" => "Pastel", "ice_cream" => "Helado", "lollipop" => "Paleta",
        "popcorn" => "Palomitas", "soccer_ball" => "Balón de fútbol", "basketball" => "Balón de baloncesto",
        "football" => "Balón de fútbol americano", "tennis" => "Pelota de tenis", "guitar" => "Guitarra",
        "trumpet" => "Trompeta", "drum" => "Tambor", "balloon" => "Globo", "gift" => "Regalo", "crown" => "Corona",
        "glasses" => "Gafas", "top_hat" => "Sombrero de copa", "umbrella" => "Paraguas", "key" => "Llave",
        "lock" => "Candado", "light_bulb" => "Bombillo", "rocket" => "Cohete", "car" => "Carro", "bus" => "Bus",
        "bicycle" => "Bicicleta", "airplane" => "Avión", "sailboat" => "Velero", "anchor" => "Ancla",
        "alarm_clock" => "Despertador", "hourglass" => "Reloj de arena", "camera" => "Cámara", "laptop" => "Portátil",
        "books" => "Libros", "pencil" => "Lápiz", "scissors" => "Tijeras", "hammer" => "Martillo", "magnet" => "Imán",
        "teddy_bear" => "Osito de peluche", "puzzle" => "Pieza de rompecabezas", "dice" => "Dado", "trophy" => "Trofeo",
        "bell" => "Campana", "rainbow" => "Arcoíris", "star" => "Estrella", "moon" => "Luna",
        "snowman" => "Muñeco de nieve", "fire" => "Fuego"
      },
      "flags" => {
        "ar" => "Argentina", "au" => "Australia", "at" => "Austria", "be" => "Bélgica", "bo" => "Bolivia",
        "br" => "Brasil", "ca" => "Canadá", "cl" => "Chile", "cn" => "China", "co" => "Colombia",
        "cr" => "Costa Rica", "hr" => "Croacia", "cu" => "Cuba", "cz" => "Chequia", "dk" => "Dinamarca",
        "ec" => "Ecuador", "eg" => "Egipto", "fi" => "Finlandia", "fr" => "Francia", "de" => "Alemania",
        "gr" => "Grecia", "in" => "India", "ie" => "Irlanda", "il" => "Israel", "it" => "Italia",
        "jm" => "Jamaica", "jp" => "Japón", "ke" => "Kenia", "mx" => "México", "ma" => "Marruecos",
        "nl" => "Países Bajos", "nz" => "Nueva Zelanda", "ng" => "Nigeria", "no" => "Noruega", "pa" => "Panamá",
        "py" => "Paraguay", "pe" => "Perú", "ph" => "Filipinas", "pl" => "Polonia", "pt" => "Portugal",
        "kr" => "Corea del Sur", "za" => "Sudáfrica", "es" => "España", "se" => "Suecia", "ch" => "Suiza",
        "th" => "Tailandia", "tr" => "Turquía", "ua" => "Ucrania", "gb" => "Reino Unido", "us" => "Estados Unidos",
        "uy" => "Uruguay", "ve" => "Venezuela", "vn" => "Vietnam"
      }
    }
  }.freeze

  NUMBERS = (1..99).freeze

  CATEGORIES = %w[animals objects flags numbers].freeze

  module_function

  # `count` distinct cards from `category` ("random" mixes all of them), named in `locale`.
  def sample(category, count, locale = "en")
    pool = category == "random" ? CATEGORIES.flat_map { |c| all(c, locale) } : all(category, locale)
    pool.sample(count)
  end

  # Every card of a category as { "key", "label", "kind" ("image" | "text"), "src" }.
  def all(category, locale = "en")
    names = LABELS.dig(locale, category) || {}
    case category
    when "animals" then emoji_cards("animals", ANIMALS, names)
    when "objects" then emoji_cards("objects", OBJECTS, names)
    when "flags"   then FLAGS.map { |iso, name| card("flags:#{iso}", names[iso] || name, FLAG_URL % iso) }
    when "numbers" then NUMBERS.map { |n| card("numbers:#{n}", n.to_s) }
    else []
    end
  end

  def emoji_cards(category, items, names = {})
    items.map { |key, (label, code)| card("#{category}:#{key}", names[key] || label, TWEMOJI_URL % code) }
  end

  def card(key, label, src = nil)
    { "key" => key, "label" => label, "kind" => src ? "image" : "text", "src" => src }
  end
end
