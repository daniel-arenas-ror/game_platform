module HowWantBeBillionare
  class Question
    include Mongoid::Document
    include Mongoid::Timestamps
    include LocalizedQuestion

    field :text, type: String
    field :correct_answer, type: Array
    field :answers, type: Array
    field :topic, type: String
    field :pack, type: String # the file it was imported from (christmas, history…), for the topic picker
    field :points, type: Integer

  end
end
