module HowWantBeBillionare
  class Question
    include Mongoid::Document
    include Mongoid::Timestamps

    field :text, type: String
    field :answers, type: Array
    field :topic, type: String

  end
end
