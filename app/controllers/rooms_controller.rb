class RoomsController < ApplicationController
  def create
    session[:player_id] = nil
    @game = Game.find(params[:game_id])
    @room = Room.create!(game: @game)

    redirect_to edit_room_path(@room.code)
  end

  def edit
    @room = Room.find_by(code: params[:id])
  end

  def update
    @room = Room.find(params[:id])

    if @room.update(room_params)
      redirect_to room_path(@room.code), notice: "Game configured!"
    else
      render :edit
    end
  end

  def show
    @room = Room.find_by(code: params[:id])
    @game = @room.game
    
    if @room.status == 'playing'
      return redirect_to playing_room_path(@room.code), alert: "Game has already started"
    end

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
      session[:player_id] = @player.id
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

  def start
    @room = Room.find_by!(code: params[:id].upcase)
    game_manager = GameFactory.build(@room)

    if game_manager.setup_game!
      render json: { status: "Game Started" }
    else
      render json: { error: "Failed to start" }, status: 422
    end
  end

  def playing
    current_player
    @room = Room.find_by!(code: params[:id].upcase)

    return redirect_to join_room_path(@room.code), alert: "Game has not started yet" if @room.status == 'lobby'

    @game_state = @room.game_state

    render "playing"
  end

  private

  def room_params
    params.require(:room).permit(:name, game_state: {})
  end
end
