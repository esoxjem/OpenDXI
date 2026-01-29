import { Controller } from "@hotwired/stimulus"

// Dropdown controller for sprint selector and user menu
// Usage: <div data-controller="dropdown">
//          <button data-action="click->dropdown#toggle">Toggle</button>
//          <div data-dropdown-target="menu" class="hidden">Menu content</div>
//        </div>
export default class extends Controller {
  static targets = ["menu"]

  toggle(event) {
    event.stopPropagation()
    if (this.hasMenuTarget) {
      this.menuTarget.classList.toggle("hidden")
    }
  }

  close(event) {
    if (this.hasMenuTarget && !this.element.contains(event.target)) {
      this.menuTarget.classList.add("hidden")
    }
  }
}
