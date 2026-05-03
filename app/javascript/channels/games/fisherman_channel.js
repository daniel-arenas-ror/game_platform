import consumer from "channels/consumer"

const fishermanGameContainer = document.getElementById('fisherman-game-container');

if(fishermanGameContainer) {
  const roomCode = fishermanGameContainer.dataset.roomCode;
  const playerId = fishermanGameContainer.dataset.playerId;

  consumer.subscriptions.create({ 
    channel: "Games::FishermanChannel", 
    room_code: roomCode,
    player_id: playerId
  }, {
    received(data) {
      switch (data.action) {
        case "new_question":
          window.phaserGame.events.emit('addQuestion', data.text);
          break;
        case "all_answers_received":

          break;
      }
    },

    sendAnswer(text) {
      this.perform('submit_answer', { answer: text });
    }
  });
}
