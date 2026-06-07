module FifaworldCup
  class Matches
    include Mongoid::Document
    include Mongoid::Timestamps

    field :home_team, type: String
    field :home_score, type: Integer
    field :away_score, type: Integer
    field :away_team, type: String
    field :kickoff, type: DateTime
    
    belongs_to :group, class_name: "FifaworldCup::Group"
  end
end
