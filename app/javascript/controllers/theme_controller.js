import { Controller } from "@hotwired/stimulus"

// Light / dark / system, stored in localStorage under "theme". The head script
// applies it before first paint; this only handles changes after that.
// "system" is stored as the absence of a key, so clearing site data resets to
// following the OS.
export default class extends Controller {
  static targets = ["option"]

  connect() {
    this.media = matchMedia("(prefers-color-scheme: dark)")
    this.onSystemChange = () => { if (this.preference === "system") this.apply() }
    this.media.addEventListener("change", this.onSystemChange)
    this.sync()
  }

  disconnect() {
    this.media.removeEventListener("change", this.onSystemChange)
  }

  select(event) {
    const theme = event.params.theme
    if (theme === "system") localStorage.removeItem("theme")
    else localStorage.setItem("theme", theme)
    this.apply()
    this.sync()
  }

  get preference() {
    return localStorage.getItem("theme") || "system"
  }

  apply() {
    const dark = this.preference === "dark" || (this.preference === "system" && this.media.matches)
    document.documentElement.classList.toggle("dark", dark)
  }

  sync() {
    for (const option of this.optionTargets) {
      option.setAttribute("aria-checked", String(option.dataset.themeThemeParam === this.preference))
    }
  }
}
