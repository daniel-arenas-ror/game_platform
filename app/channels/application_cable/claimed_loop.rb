module ApplicationCable
  # One game loop per room, whichever TV connection started it. The loop's id and a heartbeat live
  # in game_state, so a TV that reloads never starts a second loop, Play Again (which clears the id)
  # stops the old one, and a loop that died with the server is taken over after LOOP_TIMEOUT.
  # The game's setup_game! must set "loop_id" and "loop_beat" to nil.
  module ClaimedLoop
    LOOP_TIMEOUT = 10 # seconds without a heartbeat before a loop counts as dead

    private

    # Returns a new loop id, or nil when a live loop is already running.
    def claim_loop
      loop_id = SecureRandom.hex(6)
      stale   = Time.now.to_f - LOOP_TIMEOUT
      claimed = Room.collection.update_one(
        { "code" => params[:room_code], "status" => "playing",
          "$or" => [ { "game_state.loop_id" => nil }, { "game_state.loop_beat" => { "$lt" => stale } } ] },
        { "$set" => { "game_state.loop_id" => loop_id, "game_state.loop_beat" => Time.now.to_f } }
      )
      claimed.modified_count == 1 ? loop_id : nil
    end

    # True while this loop is still the room's loop. Also writes the heartbeat.
    def current_loop?(loop_id)
      Room.collection.update_one(
        { "code" => params[:room_code], "status" => "playing", "game_state.loop_id" => loop_id },
        { "$set" => { "game_state.loop_beat" => Time.now.to_f } }
      ).matched_count == 1
    end
  end
end
