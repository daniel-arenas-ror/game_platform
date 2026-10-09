namespace :questions do
  # English files sit in the folder itself, other languages in a subfolder named after the
  # locale (db/questions/how_want_be_billionare/es/*.yml). "es.yml" files work too (Fisherman).
  question_locale = lambda do |file|
    parent = File.basename(File.dirname(file))
    name   = File.basename(file, ".yml")
    [ parent, name ].find { |part| I18n.available_locales.map(&:to_s).include?(part) } || "en"
  end

  namespace :billionaire do
    desc "Import How Want Be Billionaire questions from db/questions/how_want_be_billionare/**/*.yml (or FILE=path). " \
         "Files in es/ are Spanish. Creates new questions and updates existing ones matched by text and language; never deletes."
    task import: :environment do
      files = ENV["FILE"].present? ? [ ENV["FILE"] ] : Dir[Rails.root.join("db/questions/how_want_be_billionare/**/*.yml")].sort
      abort "No question files found." if files.empty?

      # Validate everything first so a typo in one file doesn't leave a half-finished import.
      questions = files.flat_map do |file|
        locale = question_locale.(file)
        Array(YAML.safe_load_file(file)).each_with_index.map do |q, i|
          answers = Array(q["answers"]).map { |a| { text: a["text"].to_s.strip, correct: a["correct"] == true } }
          valid = q["text"].present? && q["points"].is_a?(Integer) &&
                  answers.size >= 2 && answers.all? { |a| a[:text].present? } && answers.any? { |a| a[:correct] }
          abort "#{file}, question ##{i + 1}: needs text, integer points, 2+ answers and at least one correct answer." unless valid

          { text: q["text"].strip, points: q["points"], topic: q["topic"].to_s.strip.presence, answers: answers, locale: locale }
        end
      end

      created = updated = 0
      questions.each do |attrs|
        question = HowWantBeBillionare::Question.where(text: attrs[:text], locale: attrs[:locale]).first ||
                   (attrs[:locale] == "en" && HowWantBeBillionare::Question.where(text: attrs[:text], locale: nil).first) ||
                   HowWantBeBillionare::Question.new(text: attrs[:text])
        question.new_record? ? created += 1 : updated += 1
        question.update!(attrs.except(:text))
      end

      puts "Imported #{questions.size} questions (#{created} new, #{updated} updated). " \
           "Total: #{HowWantBeBillionare::Question.count} (#{HowWantBeBillionare::Question.where(locale: "es").count} in Spanish)."
    end
  end

  namespace :fisherman do
    desc "Import The Fisherman questions from db/questions/fisherman/<locale>.yml (or FILE=path). " \
         "Creates new questions and updates existing ones matched by text and language; never deletes."
    task import: :environment do
      files = ENV["FILE"].present? ? [ ENV["FILE"] ] : Dir[Rails.root.join("db/questions/fisherman/*.yml")].sort
      abort "No question files found." if files.empty?

      questions = files.flat_map do |file|
        locale = question_locale.(file)
        Array(YAML.safe_load_file(file)).each_with_index.map do |q, i|
          answers = Array(q["answers"]).map { |a| a.to_s.strip }.reject(&:empty?)
          abort "#{file}, question ##{i + 1}: needs text and 2+ answers." unless q["text"].present? && answers.size >= 2

          { text: q["text"].strip, answerds: answers, locale: locale } # `answerds` is the model's field name
        end
      end

      created = updated = 0
      questions.each do |attrs|
        # Old questions have no locale; the same text twice (an old duplicate) is updated, not added again.
        question = Fisherman::Question.where(text: attrs[:text], locale: attrs[:locale]).first ||
                   (attrs[:locale] == "en" && Fisherman::Question.where(text: attrs[:text], locale: nil).first) ||
                   Fisherman::Question.new(text: attrs[:text])
        question.new_record? ? created += 1 : updated += 1
        question.update!(attrs.except(:text))
      end

      puts "Imported #{questions.size} questions (#{created} new, #{updated} updated). " \
           "Total: #{Fisherman::Question.count} (#{Fisherman::Question.where(locale: "es").count} in Spanish)."
    end
  end
end
