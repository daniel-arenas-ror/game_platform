Game.destroy_all

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
