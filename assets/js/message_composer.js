export const MessageComposer = {
  mounted() {
    this.localDirty = false
    this.onInput = () => { this.localDirty = true }
    this.onBeforeUnload = event => {
      if (!this.leaving && (this.localDirty || this.el.dataset.dirty === "true" || this.el.dataset.sending === "true")) {
        event.preventDefault()
        event.returnValue = ""
      }
    }
    this.onKeyDown = event => {
      const picker = event.target.closest("#recipient-picker")
      if (!picker) return
      const input = picker.querySelector("input")
      const options = [...picker.querySelectorAll('[role="option"]')]
      const index = options.indexOf(document.activeElement)
      if (event.key === "ArrowDown" || event.key === "ArrowUp") {
        event.preventDefault()
        if (!options.length) { this.pushEvent("show-recipients", {}); return }
        const next = event.key === "ArrowDown" ? (index + 1) % options.length : (index <= 0 ? options.length - 1 : index - 1)
        options[next].focus()
      } else if (event.key === "Escape") {
        event.preventDefault()
        input.focus()
        this.pushEvent("hide-recipients", {})
      } else if (event.key === "Enter" && event.target === input) {
        event.preventDefault()
        options[0]?.click()
      }
    }
    this.onClick = event => {
      if (event.target.closest('[role="option"]')) {
        this.localDirty = true
      }
    }
    this.el.addEventListener("input", this.onInput)
    this.el.addEventListener("keydown", this.onKeyDown)
    this.el.addEventListener("click", this.onClick)
    window.addEventListener("beforeunload", this.onBeforeUnload)
    this.handleEvent("compose-logout", () => {
      this.leaving = true
      document.querySelector(".child-picker-logout").submit()
    })
    this.handleEvent("recipient-selected", () => {
      const input = this.el.querySelector("#recipient-query")
      // LiveView preserves the focused input's value during patches.
      // Clear it explicitly after the server has accepted the selection.
      if (input) input.value = ""
    })
  },
  destroyed() {
    this.el.removeEventListener("input", this.onInput)
    this.el.removeEventListener("keydown", this.onKeyDown)
    this.el.removeEventListener("click", this.onClick)
    window.removeEventListener("beforeunload", this.onBeforeUnload)
  }
}
