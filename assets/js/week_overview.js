export const WeekOverview = {
  mounted() {
    this.previousFocus = document.activeElement
    this.previousOverflow = document.body.style.overflow
    document.body.style.overflow = "hidden"
    this.onCancel = event => {
      event.preventDefault()
      this.pushEvent("close-week-overview", {})
    }
    this.el.addEventListener("cancel", this.onCancel)
    this.el.showModal()
  },
  updated() {
    if (!this.el.open) this.el.showModal()
  },
  destroyed() {
    this.el.removeEventListener("cancel", this.onCancel)
    this.el.close()
    document.body.style.overflow = this.previousOverflow
    if (this.previousFocus?.isConnected) this.previousFocus.focus()
  }
}
