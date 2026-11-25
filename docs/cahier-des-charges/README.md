# Cahier des charges technique — Wiki Rhénatech (BookStack sur Kubernetes)

**SAÉ5.DevCloud.03 · IUT de Colmar · BUT R&T 3 · dossier à remettre le 20/01/2027**
Client : Rhénatech (fictive) · Interlocutrice : Claire Fischer · Plateforme : k3s · Dépôt : ce dépôt Git

Rédigé au fil de l'eau, un fichier par partie (plan imposé par le sujet). Pour le rendu : assembler en un
PDF (par ex. `pandoc docs/cahier-des-charges/0*.md docs/cahier-des-charges/10-*.md docs/cahier-des-charges/annexe-*.md -o dossier.pdf`)
avec page de garde et sommaire ; 20 pages au plus hors annexes.

| # | Partie | Fichier | Taille visée |
|---|---|---|---|
| 1 | Contexte et besoins (B1-B16, dimensionnement B9) | [01-contexte-besoins.md](01-contexte-besoins.md) | 1-2 p. |
| 2 | Architecture (schémas logique et physique, matrice des flux) | [02-architecture.md](02-architecture.md) | 2-3 p. |
| 3 | Choix et justifications | [03-choix-justifications.md](03-choix-justifications.md) | 3-4 p. |
| 4 | Mise en œuvre (dépôt, étapes, rôles, permissions, TOTP) | [04-mise-en-oeuvre.md](04-mise-en-oeuvre.md) | 3-4 p. |
| 5 | Points d'attention | [05-points-attention.md](05-points-attention.md) | 1-2 p. |
| 6 | Sécurité et RGPD | [06-securite-rgpd.md](06-securite-rgpd.md) | 2 p. |
| 7 | Exploitation | [07-exploitation.md](07-exploitation.md) | 2 p. |
| 8 | Recette R1-R12 | [08-recette.md](08-recette.md) | 1-2 p. |
| 9 | Limites et suite | [09-limites-suite.md](09-limites-suite.md) | ½ p. |
| 10 | Références | [10-references.md](10-references.md) | ½ p. |
| A | Registre de traitement RGPD | [annexe-a-registre-rgpd.md](annexe-a-registre-rgpd.md) | annexe |
| B | Manifestes et scripts | dossiers [`k8s/`](../../k8s) et [`scripts/`](../../scripts) | annexe |
