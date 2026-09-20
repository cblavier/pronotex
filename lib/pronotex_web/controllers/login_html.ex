defmodule PronotexWeb.LoginHTML do
  use PronotexWeb, :html

  def index(assigns) do
    ~H"""
    <main id="login-screen" class="flex min-h-screen items-center justify-center px-6 py-6">
      <section class="login-card w-full max-w-[21rem] rounded-xl border border-base-300 bg-base-100 p-6">
        <h1 class="login-title" aria-label="Captain Notes">
          <img
            src={~p"/images/brand/captain-notes-skull-login.png"}
            alt=""
            width="260"
            height="100"
            class="h-auto max-w-full"
          />
        </h1>
        <p class="mt-6 text-sm text-base-content/70">
          Saisissez votre code PIN pour accéder à l’application.
        </p>
        <.flash :if={!@configured || @error} id="login-error" kind={:error}>
          {if !@configured,
            do:
              "Accès indisponible : vérifiez la configuration des comptes et de leurs codes PIN, puis redémarrez l’application.",
            else: @error}
        </.flash>
        <.form :if={@configured} for={%{}} action={~p"/login"} id="pin-form" class="mt-6 space-y-4">
          <.dropdown
            id="login-account"
            name="account"
            label="Compte"
            options={Enum.map(@accounts, &{&1.label, &1.id})}
            value={@selected_account}
          />
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
          <label class="flex items-center gap-2 text-sm cursor-pointer">
            <input
              type="checkbox"
              name="remember"
              value="true"
              checked={@remember}
              class="checkbox checkbox-sm"
            /> Rester connecté
          </label>
          <button class="btn login-submit w-full" type="submit">Se connecter</button>
        </.form>
      </section>
    </main>
    """
  end
end
