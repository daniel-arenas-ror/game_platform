import consumer from "channels/consumer"

const playerList = document.getElementById('player-list');

if (playerList) {
  const roomCode = playerList.dataset.roomCode;

  consumer.subscriptions.create({ channel: "GameChannel", room_code: roomCode }, {
    received(data) {
      switch (data.action) {
        case "player_joined":
          this.handlePlayerJoined(data);
          break;
        case "game_started":
          this.handleGameStarted(data);
          break;
        case "reveal_roles":
          this.handleRevealRoles();
          break;
        case "new_question":
          this.handleNewQuestion(data);
          break;
        default:
          console.warn(`Unhandled action: ${data.action}`, data);
      }
    },
    // Helper methods to keep the switch block clean:
    handlePlayerJoined(data) {
      const playerList = document.getElementById('player-list');
      if (!playerList) return;

      const newPlayer = `
        <div class="flex items-center space-x-4 bg-slate-700 p-4 rounded-xl border border-purple-500/30 animate-pulse">
          <div class="w-10 h-10 bg-gradient-to-br from-purple-500 to-pink-500 rounded-full flex items-center justify-center font-bold">
            ${data.nickname[0].toUpperCase()}
          </div>
          <div class="text-white font-bold">${data.nickname}</div>
        </div>
      `;
      playerList.insertAdjacentHTML('afterbegin', newPlayer);
    },

    handleGameStarted(data) {
      document.getElementById('lobby-container')?.classList.add('hidden');
      document.getElementById('phaser-game')?.classList.remove('hidden');
      
      if (typeof window.initPhaserGame === "function") {
        window.initPhaserGame();
      }
    },

    handleRevealRoles() {
      // Use Turbo.visit or window.location.reload to update the player's UI with their role
      window.location.reload();
    }
  });
}

