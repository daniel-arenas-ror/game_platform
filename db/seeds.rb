Game.destroy_all
BattleCity::MapPreset.destroy_all

Game.create!(
  name: "The Fisherman",
  code: "fisherman",
  description: "A social deduction game. The fisherman must find the impostor before they blend in with the knowers."
)

Game.create!(
  name: "The Impostor",
  code: "impostor",
  description: "A social deduction game. The fisherman must find the impostor before they blend in with the knowers."
)

Game.create!(
  name: "Quick Draw",
  code: "quick_draw",
  description: "A fast-paced drawing game where speed is everything. (Coming soon)"
)

Game.create!(
  name: "Battle City",
  code: "battle_city",
  description: "Multiplayer tank battle! Drive your tank from your phone, destroy enemies and protect the base."
)

# ---------------------------------------------------------------------------
# Battle City — Classic map preset
# 26×26 grid. Steel border, brick clusters, base at (12, 24).
# Tank spawns at the four interior corners.
# ---------------------------------------------------------------------------
classic_cells = []

# Steel border — top & bottom rows
(0..25).each do |x|
  classic_cells << { "x" => x, "y" => 0,  "type" => "steel" }
  classic_cells << { "x" => x, "y" => 25, "type" => "steel" }
end

# Steel border — left & right columns (skip already-added corners)
(1..24).each do |y|
  classic_cells << { "x" => 0,  "y" => y, "type" => "steel" }
  classic_cells << { "x" => 25, "y" => y, "type" => "steel" }
end

# Base protection — steel on sides, brick above (base itself is at x=12, y=24)
[[11, 24, "steel"], [13, 24, "steel"],
 [11, 23, "brick"], [12, 23, "brick"], [13, 23, "brick"]].each do |x, y, type|
  classic_cells << { "x" => x, "y" => y, "type" => type }
end

# Interior brick clusters
[
  # Top row of clusters
  [3,2],[4,2],[3,3],[4,3],
  [7,2],[8,2],[7,3],[8,3],
  [11,2],[12,2],[13,2],[11,3],[12,3],[13,3],
  [17,2],[18,2],[17,3],[18,3],
  [21,2],[22,2],[21,3],[22,3],
  # Upper-middle clusters
  [3,6],[4,6],[3,7],[4,7],
  [7,6],[8,6],[7,7],[8,7],
  [11,6],[12,6],[11,7],[12,7],
  [13,6],[14,6],[13,7],[14,7],
  [17,6],[18,6],[17,7],[18,7],
  [21,6],[22,6],[21,7],[22,7],
  # Lower-middle clusters
  [3,16],[4,16],[3,17],[4,17],
  [7,16],[8,16],[7,17],[8,17],
  [17,16],[18,16],[17,17],[18,17],
  [21,16],[22,16],[21,17],[22,17],
  # Near-base flanks
  [5,21],[6,21],[5,22],[6,22],
  [19,21],[20,21],[19,22],[20,22]
].each do |x, y|
  classic_cells << { "x" => x, "y" => y, "type" => "brick" }
end

# Interior steel blocks (centre of map)
[[10,11],[11,11],[14,11],[15,11],
 [10,12],[11,12],[14,12],[15,12]].each do |x, y|
  classic_cells << { "x" => x, "y" => y, "type" => "steel" }
end

BattleCity::MapPreset.create!(
  name: "classic",
  cols: 26,
  rows: 26,
  base_x: 12,
  base_y: 24,
  tank_spawns: [
    { "x" => 2,  "y" => 2  },
    { "x" => 23, "y" => 2  },
    { "x" => 2,  "y" => 22 },
    { "x" => 23, "y" => 22 }
  ],
  cells: classic_cells
)

::HowWantBeBillionare::Question.create!(
  text: "Which of the following countries are considered Scandinavian?",
  points: 100,
  answers: [
    { text: "Sweden", correct: true },
    { text: "Denmark", correct: true },
    { text: "Finland", correct: false },
    { text: "Iceland", correct: false }
  ],
  topic: "Geography"
)

::HowWantBeBillionare::Question.create!(
  text: "Who wrote the play 'Hamlet'?",
  points: 100,
  answers: [
    { text: "Charles Dickens", correct: false },
    { text: "William Shakespeare", correct: true },
    { text: "Mark Twain", correct: false },
    { text: "Jane Austen", correct: false }
  ],
  topic: "Literature"
)

::HowWantBeBillionare::Question.create!(
  text: "Which of these are gases at room temperature?",
  points: 100,
  answers: [
    { text: "Oxygen", correct: true },
    { text: "Gold", correct: false },
    { text: "Mercury", correct: false },
    { text: "Nitrogen", correct: true }
  ],
  topic: "Chemistry"
)

::HowWantBeBillionare::Question.create!(
  text: "What is the capital city of Australia?",
  points: 200,
  answers: [
    { text: "Sydney", correct: false },
    { text: "Melbourne", correct: false },
    { text: "Canberra", correct: true },
    { text: "Brisbane", correct: false }
  ],
  topic: "Geography"
)

::HowWantBeBillionare::Question.create!(
  text: "Which of these famous artists are known for painting during the Renaissance period?",
  points: 200,
  answers: [
    { text: "Leonardo da Vinci", correct: true },
    { text: "Pablo Picasso", correct: false },
    { text: "Michelangelo", correct: true },
    { text: "Vincent van Gogh", correct: false }
  ],
  topic: "Art History"
)

::HowWantBeBillionare::Question.create!(
  text: "What is the chemical symbol for gold?",
  points: 300,
  answers: [
    { text: "Au", correct: true },
    { text: "Ag", correct: false },
    { text: "Fe", correct: false },
    { text: "Pb", correct: false }
  ],
  topic: "Chemistry"
)

::HowWantBeBillionare::Question.create!(
  text: "Which of these planets in our solar system have moons?",
  points: 300,
  answers: [
    { text: "Mercury", correct: false },
    { text: "Mars", correct: true },
    { text: "Venus", correct: false },
    { text: "Jupiter", correct: true }
  ],
  topic: "Astronomy"
)

::HowWantBeBillionare::Question.create!(
  text: "Which empire built the Colosseum in Rome?",
  points: 300,
  answers: [
    { text: "The Roman Empire", correct: true },
    { text: "The Greek Empire", correct: false },
    { text: "The Egyptian Empire", correct: false },
    { text: "The Ottoman Empire", correct: false }
  ],
  topic: "History"
)

::HowWantBeBillionare::Question.create!(
  text: "In music, which of these are considered string instruments?",
  points: 400,
  answers: [
    { text: "Violin", correct: true },
    { text: "Trumpet", correct: false },
    { text: "Flute", correct: false },
    { text: "Cello", correct: true }
  ],
  topic: "Music"
)

::HowWantBeBillionare::Question.create!(
  text: "What is the longest river in the world?",
  points: 400,
  answers: [
    { text: "The Amazon River", correct: true },
    { text: "The Nile River", correct: false },
    { text: "The Yangtze River", correct: false },
    { text: "The Mississippi River", correct: false }
  ],
  topic: "Geography"
)

::HowWantBeBillionare::Question.create!(
  text: "Which of these scientists won a Nobel Prize in Physics?",
  points: 500,
  answers: [
    { text: "Albert Einstein", correct: true },
    { text: "Marie Curie", correct: true },
    { text: "Charles Darwin", correct: false },
    { text: "Isaac Newton", correct: false }
  ],
  topic: "Science History"
)

::HowWantBeBillionare::Question.create!(
  text: "Which of these cities is located in Japan?",
  points: 500,
  answers: [
    { text: "Kyoto", correct: true },
    { text: "Seoul", correct: false },
    { text: "Beijing", correct: false },
    { text: "Bangkok", correct: false }
  ],
  topic: "Geography"
)

::HowWantBeBillionare::Question.create!(
  text: "Which of these are classified as mammals?",
  points: 600,
  answers: [
    { text: "Whale", correct: true },
    { text: "Shark", correct: false },
    { text: "Bat", correct: true },
    { text: "Penguin", correct: false }
  ],
  topic: "Biology"
)

::HowWantBeBillionare::Question.create!(
  text: "Who is the author of the novel '1984'?",
  points: 600,
  answers: [
    { text: "George Orwell", correct: true },
    { text: "Aldous Huxley", correct: false },
    { text: "Ray Bradbury", correct: false },
    { text: "J.R.R. Tolkien", correct: false }
  ],
  topic: "Literature"
)

::HowWantBeBillionare::Question.create!(
  text: "Which of these countries share a land border with Brazil?",
  points: 700,
  answers: [
    { text: "Argentina", correct: true },
    { text: "Chile", correct: false },
    { text: "Colombia", correct: true },
    { text: "Ecuador", correct: false }
  ],
  topic: "Geography"
)

::HowWantBeBillionare::Question.create!(
  text: "What is the primary language spoken in Brazil?",
  points: 700,
  answers: [
    { text: "Spanish", correct: false },
    { text: "Portuguese", correct: true },
    { text: "French", correct: false },
    { text: "English", correct: false }
  ],
  topic: "Language"
)

::HowWantBeBillionare::Question.create!(
  text: "Which of these historical figures was a President of the United States?",
  points: 800,
  answers: [
    { text: "Abraham Lincoln", correct: true },
    { text: "Benjamin Franklin", correct: false },
    { text: "Thomas Jefferson", correct: true },
    { text: "Winston Churchill", correct: false }
  ],
  topic: "History"
)

::HowWantBeBillionare::Question.create!(
  text: "What is the largest ocean on Earth?",
  points: 800,
  answers: [
    { text: "Atlantic Ocean", correct: false },
    { text: "Indian Ocean", correct: false },
    { text: "Pacific Ocean", correct: true },
    { text: "Arctic Ocean", correct: false }
  ],
  topic: "Geography"
)

::HowWantBeBillionare::Question.create!(
  text: "In Greek mythology, who was the god of the sea?",
  points: 900,
  answers: [
    { text: "Zeus", correct: false },
    { text: "Poseidon", correct: true },
    { text: "Hades", correct: false },
    { text: "Apollo", correct: false }
  ],
  topic: "Mythology"
)

::HowWantBeBillionare::Question.create!(
  text: "Which of these elements are noble gases?",
  points: 1000,
  answers: [
    { text: "Neon", correct: true },
    { text: "Oxygen", correct: false },
    { text: "Argon", correct: true },
    { text: "Chlorine", correct: false }
  ],
  topic: "Chemistry"
)
