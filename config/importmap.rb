# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
pin "@rails/actioncable", to: "actioncable.esm.js"
pin_all_from "app/javascript/channels", under: "channels"
# Vendored single-file build (dist/pixi.min.mjs). esm.sh splits pixi into many modules and
# breaks its extension registry (app.ticker undefined, "batcher already has a handler").
pin "pixi.js", to: "pixi.min.js" # @8.21.0
# Vendored single-file build of Motion (esm.sh motion.bundle.mjs); jspm splits it into chunks
# importmap can't resolve. Not preloaded: only the site pages' motion controllers import it.
pin "motion", to: "motion.min.js", preload: false # @12.23.12
# Vendored dist/index.js of blobatar (self-contained, MIT): deterministic blob avatars from a
# nickname. Used through controllers/shared/avatar.js only.
pin "blobatar", to: "blobatar.js" # @2.7.0
