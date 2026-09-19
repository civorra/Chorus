# Post-publication notifications — GitHub & CPAN

> Operational reference for the publication of Chorus 2 (modules `Chorus::Expert`,
> `Chorus::Engine`, `Chorus::Frame`).  
> Goal: stay informed of reactions without being spammed.

---

## GitHub

### 1. Disable default email notifications

In **Settings → Notifications**:
- Disable *"Email"* for *Watching* activities
- Keep only *"Web"* (notifications in the GitHub interface)

### 2. Do not "Watch" the repo in exhaustive mode

When the repo is published, GitHub automatically activates *Watching* mode.  
Switch to **"Participating and @mentions only"**:
- Notifications only if someone mentions `@civorra` or replies to a thread you are involved in
- Zero spam for every new issue/PR opened by a stranger

### 3. Enable "Releases" only

*"Custom"* mode → check only **Releases** — ideal for tracking forks that tag a derived version.

### 4. Stars — no native notification

GitHub does not natively notify new stars. Options:

- **[Star History](https://star-history.com)** — visual dashboard, no notifications
- **[Repobeats](https://repobeats.axiom.co)** — activity stats as a badge
- `cron` script that polls the GitHub API and sends a weekly summary:

```bash
curl -s https://api.github.com/repos/<user>/chorus/stargazers | jq length
```

### 5. Issues / Discussions

- Enable **GitHub Discussions** rather than Issues for general feedback
  — subscription possible by category
- Replying to a discussion = you automatically join the thread, without subscribing
  to everything else

### GitHub summary table

| Action | Setting |
|---|---|
| Watch mode | *Participating and @mentions* |
| Email | disabled for *Watching* |
| Stars | weekly cron script or Star History |
| Issues/PR | manual subscription case by case |

---

## CPAN

### 1. CPAN Testers — main source of spam ⚠️

On every upload, hundreds of bots test the module on all platforms
and send the results by email (very high volume, 95% PASS).

**Solution:** configure on [cpantesters.org](https://cpantesters.org) to receive
only **FAIL** and **UNKNOWN** reports:
- Author account → *Author preferences* → uncheck *"Send PASS reports"*

### 2. RT (rt.cpan.org) — bugs & tickets

Automatic subscription to your modules' queue. Every ticket (new + each
comment) generates an email.

**Solutions:**
- RT → *Preferences → Notifications* → switch to **daily digest** instead
  of per-event email
- Or a mail client rule: `from:rt.cpan.org AND subject:Chorus` → dedicated folder

### 3. MetaCPAN Favorites (≈ stars)

No native notification. API polling:

```bash
# Chorus::Expert
curl -s "https://fastapi.metacpan.org/v1/favorite?q=distribution:Chorus-Expert&size=1" \
  | jq '.hits.total.value'

# Chorus::Frame
curl -s "https://fastapi.metacpan.org/v1/favorite?q=distribution:Chorus-Frame&size=1" \
  | jq '.hits.total.value'

# Chorus::Engine
curl -s "https://fastapi.metacpan.org/v1/favorite?q=distribution:Chorus&size=1" \
  | jq '.hits.total.value'
```

A weekly cron job covering all 3 distributions is sufficient.

### 4. PAUSE — upload notifications

Just indexing confirmations — infrequent, low noise. No filtering needed.

### CPAN summary table

| Source | Volume | Recommendation |
|---|---|---|
| CPAN Testers | ⚠️ Very high | Keep FAIL/UNKNOWN only |
| RT tickets | Moderate | Daily digest or mail rule |
| MetaCPAN Favorites | No notification | Weekly API cron |
| PAUSE indexing | Low | N/A |

---

## Global recommendation (optimal combination)

1. **GitHub**: Watch → *Participating and @mentions*, email disabled for Watching
2. **CPAN Testers**: FAIL/UNKNOWN only (uncheck PASS on cpantesters.org)
3. **RT**: daily digest
4. **Stars/Favorites**: single cron script covering GitHub + all 3 MetaCPAN distributions
