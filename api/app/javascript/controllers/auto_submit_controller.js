import { Controller } from "@hotwired/stimulus"

// Auto-submit controller for forms that should submit on input change
// Used for the sprint selector dropdown
export default class extends Controller {
  submit() {
    this.element.requestSubmit()
  }
}
