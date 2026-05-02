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
end
