module FifaworldCup
  class Team
    include Mongoid::Document
    include Mongoid::Timestamps

    field :name, type: String
    field :flag, type: String
  end
end
