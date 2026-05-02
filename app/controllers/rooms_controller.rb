class RoomsController < ApplicationController
  def create
    @game = Game.find(params[:game_id])
    @room = Room.create!(game: @game)

    redirect_to room_path(@room.code)
  end

  def show
    @room = Room.find_by(code: params[:id])
    @game = @room.game
    
    # The URL that other players will scan to join
    @join_url = join_room_url(code: @room.code)
    
    # Generate QR Code
    @qrcode = RQRCode::QRCode.new(@join_url)
    @svg = @qrcode.as_svg(
      color: "000",
      shape_rendering: "crispEdges",
      module_size: 11,
      standalone: true,
      use_path: true
    )
  end

  def join
    @room = Room.find_by!(code: params[:code].upcase)
    @game = @room.game
  end

  def player_join
    @room = Room.find_by!(code: params[:code].upcase)
    nickname = params[:nickname].strip

    if nickname.present?
      @player = @room.players.create!(nickname: nickname)

      # For now, we'll store the player in the session
      # Later, we will broadcast this to the Room's ActionCable channel
      session[:nickname] = nickname
      session[:room_code] = @room.code

      ActionCable.server.broadcast("game_#{@room.code}", {
        action: "player_joined",
        nickname: @player.nickname,
        player_id: @player.id.to_s
      })
      
      redirect_to room_path(@room.code), notice: "Joined as #{nickname}!"
    else
      flash[:alert] = "Please enter a nickname"
      render :join
    end
  end

  def start_game
    @room = Room.find_by!(code: params[:code].upcase)
    game_manager = GameFactory.build(@room)
    game_manager.setup_game!

    render json: { status: "success" }
  end
end
