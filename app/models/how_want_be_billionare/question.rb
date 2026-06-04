module HowWantBeBillionare
  class Question
    include Mongoid::Document
    include Mongoid::Timestamps

    field :text, type: String
    field :correct_answer, type: Array
    field :answers, type: Array
    field :topic, type: String
    field :points, type: Integer

  end
end
