# Makes the math problems the phones answer. Pure functions, no database.
#
# A problem is { "id", "text" (what the phone shows, e.g. "7 × 6 − 9"), "answer" and, in
# choice mode, "choices" (four numbers, the answer among them) }. Answers are whole numbers ≥ 0.
module GameServices::TugOfWar::Problems
  DIFFICULTIES = %w[easy medium hard].freeze
  CHOICES      = 4

  module_function

  # A new problem, never the same text as `previous` (the problem the player just answered).
  def generate(difficulty, mode, previous: nil)
    text, answer, mixups = nil
    10.times do
      text, answer, mixups = send(:"#{difficulty}_problem")
      break unless text == previous
    end
    problem = { "id" => SecureRandom.hex(4), "text" => text, "answer" => answer }
    problem["choices"] = choices(answer, mixups) if mode == "choice"
    problem
  end

  # The answer and three wrong ones that look right: off by one or ten, or the other operator.
  def choices(answer, mixups = [])
    wrong = (mixups + [ answer + 1, answer - 1, answer + 10, answer - 10, answer + 2, answer - 2 ].shuffle)
              .select { |n| n >= 0 && n != answer }.uniq
    wrong << answer + wrong.size + 3 while wrong.size < CHOICES - 1
    (wrong.first(CHOICES - 1) << answer).shuffle
  end

  # Only the problem the player is answering is ever in play; its answer stays on the server.
  def shown(problem)
    problem&.except("answer")
  end

  # + and − up to 20.
  def easy_problem
    if rand < 0.5
      a, b = rand(1..10), rand(1..10)
      [ "#{a} + #{b}", a + b, [ (a - b).abs ] ]
    else
      a = rand(5..20)
      b = rand(1..a)
      [ "#{a} − #{b}", a - b, [ a + b ] ]
    end
  end

  # Times tables, whole divisions, and + / − up to 100.
  def medium_problem
    case rand(3)
    when 0
      a, b = rand(2..10), rand(2..10)
      [ "#{a} × #{b}", a * b, [ a + b ] ]
    when 1
      b, q = rand(2..10), rand(2..10)
      [ "#{b * q} ÷ #{b}", q, [ b * q - b ] ]
    else
      a, b = rand(10..60), rand(5..40)
      rand < 0.5 ? [ "#{a} + #{b}", a + b, [ (a - b).abs ] ] : [ "#{a + b} − #{b}", a, [ a + b + b ] ]
    end
  end

  # Two steps: a times table or a division, then + or −.
  def hard_problem
    a, b, c = rand(2..12), rand(2..10), rand(2..30)
    case rand(3)
    when 0
      [ "#{a} × #{b} + #{c}", a * b + c, [ a * (b + c), a + b + c ] ]
    when 1
      c = rand(1..a * b)
      [ "#{a} × #{b} − #{c}", a * b - c, [ a * b + c ] ]
    else
      [ "#{a * b} ÷ #{b} + #{c}", a + c, [ a * b - b + c ] ]
    end
  end
end
