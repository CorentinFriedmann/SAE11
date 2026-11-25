# Oral — démonstration (10 min) et questions du jury

## Préparation (avant d'entrer)

- VM démarrée, `timedatectl` → *System clock synchronized: yes*.
- `./scripts/status.sh` tout vert ; `.secrets/comptes-demo.txt` ouvert sur le poste (pas à l'écran projeté).
- Navigateur : une fenêtre normale (salarié) + une **fenêtre privée** (prestataire) ; autorité `ca.crt` importée.
- Le TOTP de `tech1@alpha-reseaux.example` déjà enrôlé dans une appli (téléphone ou KeePassXC).
- Terminal : police grande, `watch kubectl -n wiki get pods` prêt dans un second onglet.

## Déroulé (10 min)

| Temps | Quoi | Ce qu'on montre |
|---|---|---|
| 0:00 | Situation | l'incident de la clinique, les deux publics, ce qu'on a construit |
| 1:30 | **Schéma** (au centre de la présentation) | logique : Traefik → BookStack → MariaDB, NetworkPolicy ; physique : VM, volumes |
| 3:00 | Choix | StatefulSet/Deployment Recreate, local-path et sa limite, rôle par client, retour arrière = image + restauration |
| 4:00 | **Salarié** | `https://wiki.rhenatech.lab` (cadenas, certificat de l'autorité Rhénatech) ; `lecteur@` voit Interne et Clients, ne peut pas modifier (bouton absent, `/edit` redirigé) |
| 5:00 | **Prestataire cloisonné** | fenêtre privée, `tech1@alpha-reseaux.example` : mot de passe → **code TOTP exigé** ; il voit *Procédures réseau* et *Client – Clinique des Tilleuls* seulement ; URL `/books/commercial` tapée à la main → 404 ; recherche « tarif » → rien |
| 6:30 | Journal d'audit | `editeur@` modifie une procédure ; Paramètres › Journal d'audit : l'entrée apparaît (qui, quoi, quand, IP) |
| 7:15 | **Panne sans perte** | `kubectl -n wiki delete pod -l app=bookstack` puis `delete pod mariadb-0` : les pods reviennent seuls (~20 s), la page modifiée est toujours là |
| 8:30 | Exploitation | `./scripts/status.sh` (< 2 s) ; journal de recette R1-R12 ; restauration complète mesurée 87 s |
| 9:30 | Limites | volume lié au nœud, image root, pas d'annuaire ni de courriel → ce qu'il faudrait en production |

Si la démo casse : `kubectl -n wiki describe pod …`, `kubectl -n wiki get events --sort-by=.lastTimestamp`,
journaux — expliquer le diagnostic (c'est noté « acquis »).

## Questions du jury — réponses préparées

**Comment un prestataire est-il empêché de voir les fiches des autres clients ? Montrez-le.**
Son rôle *Prestataire* n'a **aucune** permission de rôle : par défaut il ne voit rien. Chaque livre
« Client – X » n'est ouvert en lecture qu'au rôle « Accès client – X ». Alpha a *Prestataire* + *Accès
client – Clinique des Tilleuls*. Démonstration : URL d'un autre client → 404 ; recherche → rien ; preuve
moteur : requête sur `joint_permissions` (partie 4.4) ; preuve automatique : R3.

**Pourquoi MariaDB en StatefulSet (ou en Deployment) ? Qu'est-ce que ça change ici ?**
Identité stable `mariadb-0`, volume créé par `volumeClaimTemplates` et conservé si on supprime la
StatefulSet, jamais deux pods sur le même volume. À un réplica, l'écart avec un Deployment Recreate est
faible ; la StatefulSet protège mieux la donnée et permettrait d'ajouter un réplica. BookStack, lui, est
un Deployment Recreate : ses données sont dans `/config` et la base, pas dans le pod.

**Où est l'APP_KEY, à quoi sert-elle, que se passe-t-il si on la perd ?**
Dans le Secret `wiki-secrets` (créé depuis `.secrets/wiki-secrets.env`, hors Git, copié au coffre).
Elle chiffre sessions et secrets TOTP en base. Perdue : la base se restaure mais les secrets TOTP sont
illisibles → tous les utilisateurs ré-enrôlent leur TOTP, toutes les sessions sont perdues.

**Le nœud qui porte le volume de la base tombe un samedi soir : que se passe-t-il pour l'astreinte ?**
Avec local-path, le volume est sur le disque de ce nœud : le pod reste *Pending*, le wiki est indisponible.
Procédure : relancer le nœud ; sinon redéployer et restaurer le dernier export sur un autre nœud (87 s
mesurées + décision), perte maximale 24 h (RPO). Les procédures critiques doivent donc aussi exister en
export PDF hors ligne. Parade : stockage répliqué + 2 réplicas (A3).

**Votre sauvegarde est-elle cohérente si quelqu'un écrit pendant qu'elle tourne ?**
La base oui : `mariadb-dump --single-transaction` lit un instantané InnoDB cohérent sans bloquer les
écritures. Les fichiers sont archivés juste après : au pire un fichier ajouté entre les deux est présent
sans sa ligne en base (orphelin inoffensif). Le script vérifie la fin du dump et calcule un sha256.

**Le TOTP refuse tous les codes d'un prestataire : première chose à vérifier ? (RFC 6238)**
L'heure : le code dépend de l'heure (pas de 30 s). `timedatectl` sur la VM (NTP synchronisé ?), puis
l'heure automatique du téléphone. La recette montre qu'un code décalé de 120 s est refusé. Ensuite :
l'APP_KEY a-t-elle changé (restauration avec une autre clé) ?

**Un prestataire quitte son entreprise ce soir : que faites-vous, et où cela se voit-il ?**
`./scripts/disable-user.sh son@courriel` : rôles retirés (plus rien de visible, même dans une session
ouverte), mot de passe remplacé, MFA et sessions supprimés, nom préfixé [DÉSACTIVÉ]. Ça se voit dans
Paramètres › Utilisateurs et dans le journal d'audit (modification de l'utilisateur). Le compte est
supprimé un an après (registre RGPD).

**Quelles données personnelles le wiki contient-il, et combien de temps les gardez-vous ?**
Nom, courriel professionnel, empreinte du mot de passe, secret TOTP chiffré, IP et actions dans le
journal d'audit. Journal : 365 jours (purge automatique) ; comptes prestataires : désactivés à la fin du
contrat, supprimés après un an ; sauvegardes : 7 jours. Registre en annexe A.
