namespace :events do
  # Rooms are the only history kept from before the stats existed (players are deleted when they
  # leave, and a room keeps only its last game), so only "room created" can be rebuilt.
  desc "Add a room_created event for every room that has none, dated when the room was made. Safe to re-run."
  task backfill_rooms: :environment do
    counted = Event.where(kind: "room_created").distinct(:room_id).to_set
    added   = 0

    Room.only(:_id, :game_id, :created_at).each_slice(1000) do |rooms|
      docs = rooms.reject { |room| counted.include?(room.id) }.map do |room|
        { kind: "room_created", room_id: room.id, game_id: room.game_id, created_at: room.created_at || room.id.generation_time }
      end
      next if docs.empty?

      Event.collection.insert_many(docs)
      added += docs.size
    end
    puts "Added #{added} room_created events (#{counted.size} rooms already had one)."
  end
end
