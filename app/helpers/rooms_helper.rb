# Room screens: lobby, join form and settings.
module RoomsHelper
  # The player's blobatar, made from the nickname (same face as controllers/shared/avatar.js
  # draws in the games). avatar_controller.js fills it in. `classes` sets the size, plus `block`
  # when it isn't inside a flex row.
  def player_avatar(nickname, classes = "size-10")
    tag.span class: "#{classes} shrink-0 rounded-full [&>svg]:size-full", aria: { hidden: true },
             data: { controller: "avatar", avatar_name_value: nickname }
  end
end
