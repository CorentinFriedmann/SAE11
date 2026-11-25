# Annexe A — Registre de traitement (RGPD, art. 30)

| Rubrique | Contenu |
|---|---|
| Traitement | Base documentaire interne « Wiki Rhénatech » (BookStack) |
| Responsable | Rhénatech, direction ; contact : responsable infrastructure (C. Fischer) |
| Finalités | Mettre à disposition des procédures à jour ; contrôler qui accède à quoi ; tracer les modifications (qualité, enquête après incident) |
| Base légale | Intérêt légitime (sécurité des interventions, art. 6.1.f) ; exécution des contrats de sous-traitance |
| Personnes concernées | Salariés de Rhénatech (140) ; techniciens des sous-traitants (25) |
| Données | Identité : nom, courriel professionnel · Compte : rôles, empreinte bcrypt du mot de passe, secret TOTP chiffré (APP_KEY), préférences · Traces : date, adresse IP, action et objet (journal d'audit), sessions · Contenus rédigés (auteur, date) |
| Données exclues | Aucune donnée sensible (art. 9) ; pas de photo (avatars externes désactivés) ; pas de donnée client nominative dans les pages ; plannings nominatifs d'astreinte tenus hors wiki |
| Destinataires | Administrateurs (comptes, journal) ; utilisateurs selon leurs droits (nom de l'auteur d'une page) |
| Transferts hors UE | Aucun : hébergement interne, aucun flux sortant (NetworkPolicy) |
| Durées de conservation | Journal d'audit : 365 jours (purge automatique hebdomadaire) · Compte prestataire : désactivé à la fin du contrat, supprimé 1 an après · Compte salarié : supprimé au départ (contenus réattribués) · Sauvegardes : 7 jours sur le cluster, exports selon la politique de sauvegarde (30 jours conseillés) |
| Sécurité | HTTPS (TLS ≥ 1.2), TOTP obligatoire pour administrateurs et prestataires, cloisonnement par rôle, NetworkPolicy, secrets hors Git, sauvegardes avec somme de contrôle, journal d'audit |
| Droits des personnes | Accès et rectification via le profil ; demande aux administrateurs pour l'effacement (compte supprimé, traces purgées au terme de la durée) |
