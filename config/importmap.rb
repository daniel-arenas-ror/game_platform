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
