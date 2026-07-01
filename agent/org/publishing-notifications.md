# Notifications post-publication — GitHub & CPAN

> Référence opérationnelle pour la publication de Chorus 2 (modules `Chorus::Expert`,
> `Chorus::Engine`, `Chorus::Frame`).  
> Objectif : rester informé des réactions sans être spammé.

---

## GitHub

### 1. Désactiver les notifications email par défaut

Dans **Settings → Notifications** :
- Désactiver *"Email"* pour les *Watching* activities
- Garder uniquement *"Web"* (notifications dans l'interface GitHub)

### 2. Ne pas "Watch" le repo en mode exhaustif

Quand le repo est publié, GitHub active automatiquement le mode *Watching*.  
Passer en **"Participating and @mentions only"** :
- Notif uniquement si quelqu'un mentionne `@civorra` ou répond à un fil où on est impliqué
- Zéro spam pour chaque nouvelle issue/PR ouverte par un inconnu

### 3. Activer les "Releases" uniquement

Mode *"Custom"* → cocher uniquement **Releases** — idéal pour suivre les forks
qui taggeraient une version dérivée.

### 4. Stars — pas de notification native

GitHub ne notifie pas nativement les nouvelles stars. Options :

- **[Star History](https://star-history.com)** — dashboard visuel, pas de notif
- **[Repobeats](https://repobeats.axiom.co)** — stats d'activité en badge
- Script `cron` qui poll l'API GitHub et envoie un résumé hebdo :

```bash
curl -s https://api.github.com/repos/<user>/chorus/stargazers | jq length
```

### 5. Issues / Discussions

- Activer les **GitHub Discussions** plutôt que les Issues pour les retours généraux
  — abonnement possible par catégorie
- Répondre à une discussion = on rejoint automatiquement le fil, sans être abonné
  à tout le reste

### Tableau récapitulatif GitHub

| Action | Réglage |
|---|---|
| Watch mode | *Participating and @mentions* |
| Email | désactivé pour *Watching* |
| Stars | script cron hebdo ou Star History |
| Issues/PR | abonnement manuel au cas par cas |

---

## CPAN

### 1. CPAN Testers — principale source de spam ⚠️

À chaque upload, des centaines de robots testent le module sur toutes les plateformes
et envoient les résultats par mail (volume très élevé, 95% de PASS).

**Solution :** configurer sur [cpantesters.org](https://cpantesters.org) pour ne
recevoir que **FAIL** et **UNKNOWN** :
- Compte auteur → *Author preferences* → décocher *"Send PASS reports"*

### 2. RT (rt.cpan.org) — bugs & tickets

Abonnement automatique à la queue de ses modules. Chaque ticket (nouveau + chaque
commentaire) génère un mail.

**Solutions :**
- RT → *Preferences → Notifications* → passer en **digest quotidien** plutôt
  qu'email par événement
- Ou règle mail côté client : `from:rt.cpan.org AND subject:Chorus` → dossier dédié

### 3. MetaCPAN Favorites (≈ stars)

Pas de notification native. Polling API :

```bash
# Chorus::Expert
curl -s "https://fastapi.metacpan.org/v1/favorite?q=distribution:Chorus-Expert&size=1" \
  | jq '.hits.total.value'

# Chorus::Frame
curl -s "https://fastapi.metacpan.org/v1/favorite?q=distribution:Chorus-Frame&size=1" \
  | jq '.hits.total.value'

# Chorus::Engine
curl -s "https://fastapi.metacpan.org/v1/favorite?q=distribution:Chorus-Engine&size=1" \
  | jq '.hits.total.value'
```

Un cron hebdo sur les 3 distributions suffit.

### 4. PAUSE — notifications d'upload

Juste des confirmations d'indexation — peu fréquent, peu bruyant. Pas besoin de filtrer.

### Tableau récapitulatif CPAN

| Source | Volume | Recommandation |
|---|---|---|
| CPAN Testers | ⚠️ Très élevé | Ne garder que FAIL/UNKNOWN |
| RT tickets | Modéré | Digest quotidien ou règle mail |
| MetaCPAN Favorites | Pas de notif | Cron API hebdo |
| PAUSE indexation | Faible | RAS |

---

## Recommandation globale (combinaison optimale)

1. **GitHub** : Watch → *Participating and @mentions*, email désactivé pour Watching
2. **CPAN Testers** : FAIL/UNKNOWN only (décocher PASS sur cpantesters.org)
3. **RT** : digest quotidien
4. **Stars/Favorites** : script cron unique qui couvre GitHub + les 3 distributions MetaCPAN
