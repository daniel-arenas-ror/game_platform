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
