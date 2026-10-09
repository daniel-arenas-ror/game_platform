import { Controller } from "@hotwired/stimulus"

// Header language picker: picking a language reloads the page in it (see LocalesController).
export default class extends Controller {
  change() {
    this.element.requestSubmit()
  }
}
