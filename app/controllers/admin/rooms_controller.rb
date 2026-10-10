module Admin
  # Every room, newest first, and one room's details: players, game state and its event log.
  class RoomsController < BaseController
    PER_PAGE = 50
    STATUSES = %w[lobby playing finished].freeze

    def index
      @status = params[:status].presence_in(STATUSES)
      @game   = Game.where(id: params[:game]).first if params[:game].present?
      @query  = params[:q].to_s.strip.upcase.gsub(/[^A-Z0-9]/, "").first(4)
      @page   = [ params[:page].to_i, 1 ].max

      scope = Room.all
      scope = scope.where(status: @status) if @status
      scope = scope.where(game_id: @game.id) if @game
      scope = scope.where(code: /\A#{@query}/) if @query.present?

      @total = scope.count
      @rooms = scope.order_by(created_at: :desc).skip((@page - 1) * PER_PAGE).limit(PER_PAGE).to_a
      @pages = [ (@total / PER_PAGE.to_f).ceil, 1 ].max
      @games = Game.order_by(name: :asc).to_a
      @game_names     = @games.to_h { |g| [ g.id, g.name ] }
      @player_counts = count_by(Player, "room_id", "room_id" => { "$in" => @rooms.map(&:id) })
      @games_played  = count_by(Event, "room_id", "kind" => "game_started", "room_id" => { "$in" => @rooms.map(&:id) })
      @status_counts = count_by(Room, "status")
    end

    def show
      @room    = Room.where(id: params[:id]).first || Room.where(code: params[:id].to_s.upcase).first
      return redirect_to(admin_rooms_path, alert: "That room no longer exists.") unless @room

      @players = @room.players.order_by(created_at: :asc).to_a
      @events  = Event.where(room_id: @room.id).order_by(created_at: :desc).limit(200).to_a
      @event_counts = count_by(Event, "kind", "room_id" => @room.id)
      @games        = Game.where(:id.in => @events.map(&:game_id).uniq + [ @room.game_id ]).to_h { |g| [ g.id, g ] }
    end

    private

    # { value of field => number of documents } in one query, e.g. players per room.
    def count_by(model, field, match = {})
      model.collection.aggregate([
        { "$match" => match },
        { "$group" => { "_id" => "$#{field}", "n" => { "$sum" => 1 } } }
      ]).to_h { |row| [ row["_id"], row["n"] ] }
    end
  end
end
