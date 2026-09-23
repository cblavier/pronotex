defmodule PronotexWeb.Settings do
  use Phoenix.Component

  def panel(assigns) do
    ~H"""
    <section id="settings-content" aria-labelledby="settings-title">
      <PronotexWeb.CoreComponents.page_title id="settings-title" class="mb-6">
        Réglages
      </PronotexWeb.CoreComponents.page_title>
      <div id="app-settings" phx-hook="Settings" phx-update="ignore" class="space-y-6">
        <section class="card border border-base-300 bg-base-100 p-5">
          <label
            class="flex cursor-pointer items-center justify-between gap-4"
            for="notifications-enabled"
          >
            <span class="font-medium">Activer les notifications</span>
            <PronotexWeb.CoreComponents.toggle_switch
              id="notifications-enabled"
              disabled
              aria-describedby="notification-status"
            />
          </label>
          <p
            id="notification-status"
            class="mt-3 text-sm text-[var(--muted-ink)]"
            role="status"
            aria-live="polite"
          >
            Vérification de la disponibilité…
          </p>
        </section>
        <section class="card border border-base-300 bg-base-100 p-5">
          <fieldset>
            <legend class="mb-4 font-medium">Thème</legend>
            <div class="settings-choices">
              <label :for={
                {value, label} <- [{"light", "Jour"}, {"dark", "Nuit"}, {"system", "Système"}]
              }>
                <input type="radio" name="theme" value={value} checked={value == "system"} />
                <span>{label}</span>
              </label>
            </div>
          </fieldset>
        </section>
        <section class="card border border-base-300 bg-base-100 p-5">
          <fieldset>
            <legend class="mb-4 font-medium">Niveau de zoom</legend>
            <div class="settings-choices">
              <label :for={
                {value, label} <- [
                  {"small", "Plus petit"},
                  {"normal", "Normal"},
                  {"large", "Plus grand"}
                ]
              }>
                <input type="radio" name="zoom" value={value} checked={value == "normal"} />
                <span>{label}</span>
              </label>
            </div>
          </fieldset>
        </section>
        <p class="text-sm text-[var(--muted-ink)]">Ces réglages sont conservés sur cet appareil.</p>
      </div>
    </section>
    """
  end
end
