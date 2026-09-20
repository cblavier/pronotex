defmodule Pronotex.Pronote.Error do
  @moduledoc "An error safe to display: never includes credentials or server response bodies."
  defexception [:reason, :code, message: "Réponse Pronote inattendue."]

  def new(reason, code \\ nil) do
    message =
      case reason do
        :missing_credentials ->
          "Renseignez PRONOTE_USERNAME et PRONOTE_PASSWORD dans .envrc."

        :invalid_url ->
          "PRONOTE_URL doit être une URL HTTPS directe vers parent.html."

        :authentication_failed ->
          "Pronote a refusé la connexion. Vérifiez vos identifiants."

        :additional_authentication_required ->
          "Pronote demande une vérification supplémentaire non prise en charge."

        :session_expired ->
          "La session Pronote a expiré."

        :rate_limited ->
          "Pronote limite les connexions. Réessayez plus tard."

        :forbidden ->
          "Ce compte ne permet pas de consulter ces données."

        :child_not_found ->
          "Cet enfant n’est pas accessible depuis ce compte parent."

        :stale_discussion ->
          "Rechargez les messages avant de modifier leur statut."

        :message_unconfirmed ->
          "Pronote n’a pas confirmé le changement. Rechargez les messages pour vérifier leur statut."

        :stale_homework ->
          "Rechargez les devoirs avant de modifier leur statut."

        :student_credentials_required ->
          "Les identifiants élèves ne sont pas configurés pour cet enfant."

        :student_mismatch ->
          "Le compte élève configuré ne correspond pas à cet enfant."

        :invalid_homework ->
          "Ce devoir ou ce statut n’est pas valide."

        :homework_unconfirmed ->
          "Pronote n’a pas confirmé le changement. Rechargez les devoirs pour vérifier leur statut."

        :invalid_dates ->
          "Utilisez deux dates ordonnées, espacées de moins d’un an."

        :outside_school_year ->
          "La période demandée est hors de l’année scolaire de cette session."

        :network ->
          "Impossible de joindre Pronote. Réessayez plus tard."

        :http ->
          "Le serveur Pronote a retourné une erreur HTTP."

        :protocol ->
          "Le format de la réponse Pronote n’est pas reconnu."

        _ ->
          "Pronote a refusé la requête."
      end

    %__MODULE__{reason: reason, code: code, message: message}
  end
end
