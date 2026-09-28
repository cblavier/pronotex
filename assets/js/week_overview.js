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
    this.cancelResizeWait = () => {
      window.clearTimeout(this.resizeTimer)
      window.cancelAnimationFrame(this.resizeFrame)
    }
    this.viewportSize = () => [window.innerWidth, window.innerHeight,
      window.visualViewport?.width, window.visualViewport?.height].join(":")
    this.onResize = () => {
      this.cancelResizeWait()
      this.resizing = true
      this.el.toggleAttribute("data-resizing", true)
      this.resizeTimer = window.setTimeout(() => {
        const size = this.viewportSize()
        this.resizeFrame = window.requestAnimationFrame(() => {
          this.resizeFrame = window.requestAnimationFrame(() => {
            if (size !== this.viewportSize()) return this.onResize()
            this.syncPresentation()
            this.resizing = false
            this.el.toggleAttribute("data-resizing", false)
          })
        })
      }, 180)
    }
    this.el.addEventListener("cancel", this.onCancel)
    window.addEventListener("resize", this.onResize)
    window.addEventListener("orientationchange", this.onResize)
    window.visualViewport?.addEventListener("resize", this.onResize)
    this.inlinePresentation.addEventListener("change", this.syncPresentation)
    this.syncPresentation()
  },
  updated() {
    this.el.toggleAttribute("data-resizing", !!this.resizing)
    this.syncPresentation()
  },
  destroyed() {
    this.cancelResizeWait()
    window.removeEventListener("resize", this.onResize)
    window.removeEventListener("orientationchange", this.onResize)
    window.visualViewport?.removeEventListener("resize", this.onResize)
    this.el.removeEventListener("cancel", this.onCancel)
    this.inlinePresentation.removeEventListener("change", this.syncPresentation)
    this.el.close()
    document.body.style.overflow = this.previousOverflow
    if (this.previousFocus?.isConnected) this.previousFocus.focus()
  }
}
