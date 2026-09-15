# On server start, any room still marked "playing" has no live game thread
# driving it (the previous server process died). Reset them to "finished" so
# hosts can restart without the room being permanently stuck.
Rails.application.config.after_initialize do
  begin
    stuck = Room.where(status: "playing")
    count = stuck.count
    if count > 0
      stuck.update_all(status: "finished")
      Rails.logger.info("[reset_stuck_rooms] Reset #{count} stuck room(s) to 'finished' on startup")
    end
  rescue => e
    # DB might not be available yet during asset precompile or test setup — log and continue
    Rails.logger.warn("[reset_stuck_rooms] Could not reset stuck rooms: #{e.message}")
  end
end
