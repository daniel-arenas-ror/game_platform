module Fisherman
  class Question
    include Mongoid::Document
    include Mongoid::Timestamps

    field :text, type: String
    field :answerds, type: Array

  end
end