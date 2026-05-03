import consumer from "channels/consumer"

export default function subscribeFisherman(roomCode) {
  return consumer.subscriptions.create({ 
    channel: "Games::FishermanChannel", 
    room_code: roomCode 
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
