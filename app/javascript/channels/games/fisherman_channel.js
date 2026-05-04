import consumer from "channels/consumer"

const fishermanGameContainer = document.getElementById('fisherman-game-container');

if(fishermanGameContainer) {
  const roomCode = fishermanGameContainer.dataset.roomCode;
  const playerId = fishermanGameContainer.dataset.playerId;

  const fishermanSub = consumer.subscriptions.create({ 
    channel: "Games::FishermanChannel", 
    room_code: roomCode,
    player_id: playerId
  }, {
    received(data) {
      console.log("refresh_game_frame received with data:", data);

      switch (data.action) {
        case "player_presence":
          this.updatePlayerDot(data.player_id, data.connected);
          break;
        case "all_answers_received":
          break;
        case "refresh_game_frame":
          break;
        case "next_round_started":
          window.location.reload();
          break;
      }
    },

    sendGuess(data) {
      this.perform('submit_guess', { guess: text });
    },

    updatePlayerDot(playerId, isOnline) {
      const dot = document.getElementById(`status-dot-${playerId}`);
      if (dot) {
        if (isOnline) {
          dot.classList.replace('bg-red-500', 'bg-green-500');
          dot.classList.add('shadow-[0_0_8px_rgba(34,197,94,0.6)]');
        } else {
          dot.classList.replace('bg-green-500', 'bg-red-500');
          dot.classList.remove('shadow-[0_0_8px_rgba(34,197,94,0.6)]');
        }
      }
    }
  });

  let selectedIds = [];

  document.addEventListener('click', (e) => {
    const card = e.target.closest('.suspect-card');
    const lockBtn = document.getElementById('btn-lock-guess');
    const countBadge = document.getElementById('selection-count');

    if (card) {
      const pId = card.dataset.playerId;

      if (selectedIds.includes(pId)) {
        // DESELECT
        selectedIds = selectedIds.filter(id => id !== pId);
        card.classList.replace('border-purple-500', 'border-slate-700');
        card.querySelector('.indicator').classList.remove('bg-purple-500/10', 'border-purple-500');
        card.querySelector('.indicator span').classList.add('hidden');
      } else {
        // SELECT
        selectedIds.push(pId);
        card.classList.replace('border-slate-700', 'border-purple-500');
        card.querySelector('.indicator').classList.add('bg-purple-500/10', 'border-purple-500');
        card.querySelector('.indicator span').classList.remove('hidden');
      }

      // Update UI State
      const count = selectedIds.length;
      countBadge.innerText = `${count} Selected`;
      
      if (count > 0) {
        lockBtn.disabled = false;
        lockBtn.classList.replace('bg-slate-700', 'bg-yellow-400');
        lockBtn.classList.replace('text-slate-500', 'text-slate-900');
        lockBtn.innerText = `GUESS THESE ${count} PLAYERS`;
      } else {
        lockBtn.disabled = true;
        lockBtn.classList.replace('bg-yellow-400', 'bg-slate-700');
        lockBtn.classList.replace('text-slate-900', 'text-slate-500');
        lockBtn.innerText = "Select at least one";
      }
    }

    if (e.target.id === 'btn-lock-guess' && selectedIds.length > 0) {
      // Send array of IDs to ActionCable
      fishermanSub.perform('submit_guess', {
        target_ids: selectedIds,
        room_code: roomCode,
        player_id: playerId
      });
      // Optional: Show spinner immediately on click
      e.target.innerHTML = `<div class="animate-spin h-5 w-5 border-2 border-slate-900 border-t-transparent rounded-full mx-auto"></div>`;
    }

    if (e.target.id === 'btn-restart-game') {
      // We call the restart_game method on the Ruby channel
      fishermanSub.perform('restart_game');
      
      // Visual feedback: show a loading state on the button
      e.target.disabled = true;
      e.target.innerHTML = `<div class="animate-spin h-6 w-6 border-4 border-white border-t-transparent rounded-full mx-auto"></div>`;
    }
  });
}
