defmodule PronotexWeb.LoginHTML do
  use PronotexWeb, :html

  def index(assigns) do
    ~H"""
    <main id="login-screen" class="flex min-h-screen items-center justify-center px-6 py-6">
      <section class="login-card w-full max-w-[21rem] rounded-xl border border-base-300 bg-base-100 p-6">
        <div class="flex items-center gap-3">
          <img
            src={~p"/images/brand/captain-notes-notebook-192.png"}
            alt=""
            width="72"
            height="72"
            class="rounded-xl"
          />
          <h1
            class="login-title text-2xl font-extrabold leading-none tracking-tight"
            aria-label="Captain Notes"
          >
            <span class="block">captain</span><span class="block">notes</span>
          </h1>
        </div>
        <p class="mt-6 text-sm text-base-content/70">
          Saisissez votre code PIN pour accéder à l’application.
        </p>
        <p :if={!@configured} role="alert" class="mt-4 text-sm text-error">
          Accès indisponible : vérifiez la configuration du code PIN, puis redémarrez l’application.
        </p>
        <p :if={@error} role="alert" class="mt-4 text-sm text-error">{@error}</p>
        <.form :if={@configured} for={%{}} action={~p"/login"} id="pin-form" class="mt-6 space-y-4">
          <input
            id="pin"
            aria-label="Code PIN"
            name="pin"
            type="password"
            inputmode="numeric"
            required
            autocomplete="current-password"
            class="input w-full text-center tracking-widest"
          />
          <div class="grid grid-cols-3 gap-2" role="group" aria-label="Pavé numérique">
            <button :for={digit <- 1..9} type="button" class="pin-key" data-pin-digit={digit}>
              {digit}
            </button>
            <button
              type="button"
              class="pin-key text-sm"
              data-pin-action="clear"
              aria-label="Effacer le code"
            >
              Effacer
            </button>
            <button type="button" class="pin-key" data-pin-digit="0">0</button>
            <button
              type="button"
              class="pin-key"
              data-pin-action="backspace"
              aria-label="Effacer le dernier chiffre"
            >
              <.icon name="hero-backspace" class="size-5" />
            </button>
          </div>
          <button class="btn login-submit w-full" type="submit">Se connecter</button>
          <p class="text-xs text-base-content/60">Connexion valable 12 heures.</p>
        </.form>
      </section>
    </main>
    """
  end
end
