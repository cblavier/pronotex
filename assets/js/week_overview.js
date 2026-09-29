export const WeekOverview = {
  mounted() {
    this.previousFocus = document.activeElement
    this.previousOverflow = document.body.style.overflow
    this.inlinePresentation = window.matchMedia("(orientation: portrait), (min-width: 768px) and (min-height: 600px), (min-width: 1024px) and (hover: hover) and (pointer: fine)")
    this.syncPresentation = () => {
      const modal = !this.inlinePresentation.matches
      if (this.el.open && this.modal !== modal) this.el.close()
      document.body.style.overflow = modal ? "hidden" : this.previousOverflow
      if (!this.el.open) {
        if (modal) this.el.showModal()
        else this.el.show()
      }
      this.modal = modal
    }
    this.onCancel = event => {
      event.preventDefault()
      this.pushEvent("close-week-overview", {})
    }
    this.el.addEventListener("cancel", this.onCancel)
    this.inlinePresentation.addEventListener("change", this.syncPresentation)
    this.syncPresentation()
  },
  updated() {
    this.syncPresentation()
  },
  destroyed() {
    this.el.removeEventListener("cancel", this.onCancel)
    this.inlinePresentation.removeEventListener("change", this.syncPresentation)
    this.el.close()
    document.body.style.overflow = this.previousOverflow
    if (this.previousFocus?.isConnected) this.previousFocus.focus()
  }
}
