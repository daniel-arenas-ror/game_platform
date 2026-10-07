module Admin
  class DashboardController < BaseController
    # Days are counted in UTC. The full dashboard (charts, game ranking) comes in phase 3.
    def show
      today = Time.now.utc.beginning_of_day
      @totals = Event::KINDS.index_with do |kind|
        { today: Event.where(kind: kind, :created_at.gte => today).count, all: Event.where(kind: kind).count }
      end
    end
  end
end
