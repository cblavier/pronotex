import {pushSupported, pushState, enablePush, disablePush} from "./push"

export const Settings = {
  mounted() {
    this.preferences = window.captainPreferences
    this.notifications = this.el.querySelector("#notifications-enabled")
    this.status = this.el.querySelector("#notification-status")
    this.enabled = false
    this.ready = false
    this.busy = false
    this.sync = async () => {
      for (const name of ["theme", "zoom"]) {
        const value = this.preferences.read(name, name === "theme" ? "system" : "normal")
        this.el.querySelectorAll(`input[name="${name}"]`).forEach(input => { input.checked = input.value === value })
      }
      if (this.busy) return
      this.ready = false
      this.renderPermission()
      if (pushSupported()) {
        try {
          const state = await pushState()
          this.enabled = state.enabled
          this.publicKey = state.publicKey
          this.ready = true
          this.renderPermission()
        } catch {
          this.status.textContent = "Impossible de vérifier les notifications. Rechargez la page."
        }
      }
    }
    this.onChange = async event => {
      const input = event.target
      if (["theme", "zoom"].includes(input.name)) {
        this.preferences.set(input.name, input.value)
        return
      }
      if (input !== this.notifications) return
      if (this.busy) return
      this.busy = true
      input.disabled = true
      try {
        if (input.checked) {
          this.enabled = await enablePush(this.publicKey)
        } else {
          await disablePush()
          this.enabled = false
        }
        this.preferences.set("notifications", this.enabled ? "true" : "false")
        this.busy = false
        this.renderPermission()
      } catch {
        this.busy = false
        this.renderPermission()
        this.status.textContent = "Impossible de modifier les notifications. Vérifiez la connexion puis réessayez."
      }
    }
    this.el.addEventListener("change", this.onChange)
    window.addEventListener("focus", this.sync)
    window.addEventListener("storage", this.sync)
    this.sync()
  },
  renderPermission() {
    const ios = /iPad|iPhone|iPod/.test(navigator.userAgent) || (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1)
    const installed = matchMedia("(display-mode: standalone)").matches || navigator.standalone === true
    const supported = pushSupported()
    this.notifications.disabled = !supported || !this.ready || this.busy || Notification.permission === "denied"
    this.notifications.checked = supported && Notification.permission === "granted" && this.enabled
    if (ios && !installed) {
      this.status.textContent = "Sur iPhone ou iPad, ajoutez l’application à l’écran d’accueil puis ouvrez-la depuis son icône."
    } else if (!supported) {
      this.status.textContent = "Les notifications ne sont pas disponibles dans ce navigateur. Utilisez une connexion HTTPS."
    } else if (Notification.permission === "denied") {
      this.status.textContent = "Autorisation refusée. Vous pouvez la modifier dans les réglages de notifications du navigateur ou de l’appareil."
    } else if (!this.ready) {
      this.status.textContent = "Vérification des notifications…"
    } else if (this.notifications.checked) {
      this.status.textContent = "Vous recevrez une notification pour les nouvelles notes de ce profil."
    } else {
      this.status.textContent = "Recevoir les nouvelles notes sur cet appareil, même quand l’application est fermée."
    }
  },
  destroyed() {
    this.el.removeEventListener("change", this.onChange)
    window.removeEventListener("focus", this.sync)
    window.removeEventListener("storage", this.sync)
  }
}
