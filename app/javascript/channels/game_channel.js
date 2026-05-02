import consumer from "channels/consumer"

const playerList = document.getElementById('player-list');

if (playerList) {
  const roomCode = playerList.dataset.roomCode;

  consumer.subscriptions.create({ channel: "GameChannel", room_code: roomCode }, {
    received(data) {
      if (data.action === "player_joined") {
        const newPlayer = `
          <div class="flex items-center space-x-4 bg-slate-700 p-4 rounded-xl border border-purple-500/30 animate-bounce">
            <div class="w-10 h-10 bg-gradient-to-br from-purple-500 to-pink-500 rounded-full flex items-center justify-center font-bold">
              ${data.nickname[0].toUpperCase()}
            </div>
            <div class="text-white font-bold">${data.nickname}</div>
          </div>
        `;
        playerList.insertAdjacentHTML('afterbegin', newPlayer);
      }
    }
  });
}
