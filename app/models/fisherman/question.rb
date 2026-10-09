module Fisherman
  class Question
    include Mongoid::Document
    include Mongoid::Timestamps
    include LocalizedQuestion

    field :text, type: String
    field :answerds, type: Array

  end
end
