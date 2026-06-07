module FifaworldCup
  class Group
    include Mongoid::Document
    include Mongoid::Timestamps

    field :name, type: String
    has_many :matches, class_name: "FifaworldCup::Matches"
  end
end
