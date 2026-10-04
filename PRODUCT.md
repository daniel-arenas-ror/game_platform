# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

Groups that are physically together in one room and want to play something together in under a minute. There are three equally important settings:

- **Classrooms.** A teacher puts the host screen on a projector and students join from their phones. Players can be young, so content must be kid-safe and readable from the back of the room.
- **Work meetings.** Icebreakers and team breaks, often on a shared screen in a meeting room. Colleagues join quickly and don't want an account.
- **Friends and family gatherings.** A living room with the host on the TV and 3 to 10 people on phones. Ages and comfort with tech vary.

There are two roles in every session:

- **Host.** Picks the game, configures it, and drives the shared screen, which may be a TV, projector or laptop. They are often also the organizer explaining the rules out loud.
- **Player.** Scans the QR code or types the 4-character room code, picks a nickname and plays on a phone. They may never have seen the site before.

## Product Purpose

Grouparty is a free collection of real-time multiplayer party games for people in the same room. The shared screen tells the story and each phone becomes a private controller. That lets players keep secrets, race each other and see the results together.

Success means growing into a real product. That means building an audience through search and word of mouth, being the obvious "let's play something" choice for a room of people, and keeping the door open to premium features or other monetization later. Ads currently cover the servers.

## Positioning

There is nothing to install and no account to create. It works in any modern browser. One shared screen plus everyone's own phone turns a room into a game in less than a minute. The collection mixes very different kinds of play, so one room can switch games without anyone leaving: timed trivia, social deduction, memory, color matching, number hunting, word matching, tank battles and submarine combat.

## Operating Context

- **Two screens per session.** The host view is seen from across a room, on a TV, projector or laptop, or shared on a video call (Zoom, Google Meet, Microsoft Teams). The player view is a phone held in the hand, often on mobile data, sometimes as a spectator.
- **Remote play is supported but secondary.** Players on a call scan the code from the shared screen or type it at `/join`. Fast-reaction games play best in the same room, and copy must say so rather than promise that every game works well over screen share.
- **The host flow is Home (`/`) → Games (`/games`) → create room → configure → lobby with QR and room code → playing → finished.** The host can change games while players stay in the room, via `/games?room=CODE`.
- **Players join via the QR code (straight to `/join/:code`) or by typing the code on the Join page (`/join`).** Identity is per session, so there are no accounts.
- **Everything happens in real time over WebSockets.** Players who disconnect are removed after a 30-second grace period.
- **The rules are usually explained out loud by the host.** In-game instruction images and the game descriptions support that.

## Capabilities and Constraints

- **Stack.** Rails 8, MongoDB (Mongoid), ActionCable, Stimulus, Tailwind via `tailwindcss-rails`, and importmap with no Node bundler. It is deployed to AWS via `script/aws_deploy.sh`.
- **Games.** Nine are playable: `fisherman`, `how_want_be_billionare`, `battle_city`, `guess_the_color`, `count_birds`, `sequence_memory`, `submarine_combat`, `mind_match` and `soup_of_numbers`. `impostor` is pending.
- **Public pages.** There are three main pages, linked from a shared site header. **Home** explains the idea: use cases, benefits, in-room and video-call play, and how it works. **Games** is the catalog. **Join** is room-code entry. About, Contact and Privacy hang off the footer. SEO is set up with JSON-LD, OG tags, a sitemap and robots.txt. Change-game pages (`/games?room=`) and room pages are noindex.
- **Ads.** Google AdSense is shown in a limited set of places: Home, Games, the lobby, the info pages and the host's Game Over screen. The Join page never shows ads. An ad must never sit next to a Play or Join control, and game screens stay free of ads and footers.
- **Language.** Copy is English today and Spanish is the planned second locale. New copy should be written so it can be translated, without hard-coded string concatenation in places where translation would break it.
- **Undecided.** Premium features and their pricing don't exist yet.

## Brand Commitments

- **Name.** The product is called "Grouparty" (`SeoHelper::SITE_NAME`).
- **Voice.** Plain, friendly and direct. Examples: "Free party games you play from your phone" and "No app to install, no sign-up — just pick a game and play together."
- **Author.** It is made by Daniel Arenas as a personal project, and the About page says so openly.

## Evidence on Hand

- **Instruction images.** There is one per game at `public/games/{code}/instructions.png`.
- **Game descriptions.** These live in `db/seeds.rb`.
- **Site copy.** This is in the About, Contact and Privacy pages under `app/views/pages/`.
- **Sounds.** Sound assets are in `public/games/sounds/`.
- **Not available.** There are no testimonials, user counts, press, ratings or case studies. Future work must not invent them.
- **Claims.** Benefit copy stays modest: "Wake up your brain" and "take a break from stress". Never claim IQ gains or other measurable health or cognitive outcomes.
- **Home illustrations.** These are planned but not made yet. They were held back by image-generation credits.

## Product Principles

1. **One minute from idea to playing.** Every step between "let's play" and the first round is a cost: creating, joining, configuring. Never add accounts or installs.
2. **Two screens, two jobs.** The host screen must read from across a room. The phone must work one-handed with no explanation needed.
3. **Safe for any room.** Content and tone must work in front of a class of kids, a team of colleagues or a family table.
4. **Keep the room together.** Switching games, rejoining after a disconnect and spectating should never break the group's session.
5. **Monetization never blocks play.** Ads stay away from game screens and primary actions.

## Accessibility & Inclusion

- Host screens are read at a distance, so they need large type, high contrast and meaning that doesn't depend on color alone. This matters especially in color-centric games.
- Player controls must have touch targets sized for phones, and must work on older and low-end devices and on slow connections.
- Players include children and people with little tech experience, so language should be simple.
