namespace :questions do
  namespace :billionaire do
    desc "Import How Want Be Billionaire questions from db/questions/how_want_be_billionare/*.yml (or FILE=path). " \
         "Creates new questions and updates existing ones matched by text; never deletes."
    task import: :environment do
      files = ENV["FILE"].present? ? [ ENV["FILE"] ] : Dir[Rails.root.join("db/questions/how_want_be_billionare/*.yml")].sort
      abort "No question files found." if files.empty?

      # Validate everything first so a typo in one file doesn't leave a half-finished import.
      questions = files.flat_map do |file|
        Array(YAML.safe_load_file(file)).each_with_index.map do |q, i|
          answers = Array(q["answers"]).map { |a| { text: a["text"].to_s.strip, correct: a["correct"] == true } }
          valid = q["text"].present? && q["points"].is_a?(Integer) &&
                  answers.size >= 2 && answers.all? { |a| a[:text].present? } && answers.any? { |a| a[:correct] }
          abort "#{file}, question ##{i + 1}: needs text, integer points, 2+ answers and at least one correct answer." unless valid

          { text: q["text"].strip, points: q["points"], topic: q["topic"].to_s.strip.presence, answers: answers }
        end
      end

      created = updated = 0
      questions.each do |attrs|
        question = HowWantBeBillionare::Question.where(text: attrs[:text]).first_or_initialize
        question.new_record? ? created += 1 : updated += 1
        question.update!(attrs.except(:text))
      end

      puts "Imported #{questions.size} questions (#{created} new, #{updated} updated). " \
           "Total: #{HowWantBeBillionare::Question.count}."
    end
  end
end
