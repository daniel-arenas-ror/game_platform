# Removes a player from their room: deletes the Player, drops every per-player entry from
# game_state (scores, answers, placements, …) and tells the lobby and the game screens.
class PlayerRemover
  # How long a player may stay fully disconnected before being removed. Covers page reloads,
  # the lobby → game navigation, a phone screen lock and short network drops.
  GRACE_PERIOD = 30.seconds

  def self.schedule(player_id)
    Thread.new do
      sleep GRACE_PERIOD
      remove_if_disconnected(player_id)
    rescue => e
      Rails.logger.error("[PlayerRemover] #{player_id}: #{e.message}")
    end
  end

  # Called after the disconnect grace period. Does nothing if the player came back meanwhile.
  def self.remove_if_disconnected(player_id)
    player = Player.where(id: player_id, :connections.lte => 0).first
    player ? new(player).remove! : false
  end

  def initialize(player)
    @player = player
    @room   = player.room
  end

  def remove!
    player_id = @player.id.to_s
    nickname  = @player.nickname
    @player.destroy

    return true unless @room

    @room.reload
    unset = @room.game_state.select { |_, v| v.is_a?(Hash) && v.key?(player_id) }
                             .keys.to_h { |k| [ "game_state.#{k}.#{player_id}", "" ] }
    Room.collection.update_one({ _id: @room.id }, { "$unset" => unset }) if unset.any?
    @room.reload

    payload = { action: "player_left", player_id: player_id, nickname: nickname }
    ActionCable.server.broadcast("game_#{@room.code}", payload)
    ActionCable.server.broadcast(@room.game_stream_name, payload)

    game_service&.player_removed!(player_id) if @room.status == "playing"
    true
  end

  private

  def game_service
    GameFactory.build(@room)
  rescue RuntimeError
    nil
  end
end
