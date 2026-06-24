# Skill — cpan-release

> Déclencheur : `cpan-release`
> Agent : `code`
>
> **Responsabilité unique : publier une nouvelle version de Chorus::Engine sur PAUSE/CPAN.**
> Ce skill couvre le bump de version, la vérification des artefacts, la construction
> de la tarball, l'upload sur PAUSE et le tag git.
>
> Dépôt : `$ENGINE` = `/home/civorra/Documents/Chorus/Engine`
> Outil d'upload : `cpan-upload` (CPAN::Uploader) — credentials dans `~/.pause`

---

## ⚡ Étape 0 — État des lieux (toujours en premier)

Exécuter séquentiellement :

```bash
# Version actuelle dans le module
grep "VERSION" /home/civorra/Documents/Chorus/Engine/lib/Chorus/Engine.pm | head -3

# Dernier tag git
git -C /home/civorra/Documents/Chorus/Engine tag --sort=-v:refname | head -5

# Statut du dépôt
git -C /home/civorra/Documents/Chorus/Engine status
```

Afficher le résultat et demander confirmation avant de continuer :

> "Version actuelle : X.YY — dernier tag : vX.YY — N fichiers modifiés.
> Quelle sera la nouvelle version ? (ex. 1.06)"

---

## Phase 1 — Bump de version

### 1.1 Bumper `$VERSION` dans `Engine.pm`

Un seul endroit à modifier (`VERSION_FROM` dans `Makefile.PL` pointe sur ce fichier) :

```perl
# lib/Chorus/Engine.pm
our $VERSION = 'X.YY';   # → nouvelle version
```

### 1.2 Mettre à jour `Changes`

Format attendu en tête de `Changes` :

```
X.YY    YYYY-MM-DD
        - <description des changements>
        - <description des changements>
```

Proposer un résumé des commits depuis le dernier tag :

```bash
git -C /home/civorra/Documents/Chorus/Engine log --oneline $(git -C /home/civorra/Documents/Chorus/Engine tag --sort=-v:refname | head -1)..HEAD
```

### 1.3 Commiter le bump

```bash
git -C /home/civorra/Documents/Chorus/Engine add lib/Chorus/Engine.pm Changes
git -C /home/civorra/Documents/Chorus/Engine commit -m "release: bump version to X.YY"
```

---

## Phase 2 — Vérification des artefacts

### 2.1 Regénérer le MANIFEST

```bash
cd /home/civorra/Documents/Chorus/Engine && perl Makefile.PL && make manifest
```

Vérifier que `lib/Chorus/Engine/ECA.pod` est bien présent dans `MANIFEST`.
Vérifier que `eca/`, `doc/`, `MYMETA.*`, `Makefile` sont absents (exclus par `MANIFEST.SKIP`).

### 2.2 Vérifier les écarts MANIFEST

```bash
cd /home/civorra/Documents/Chorus/Engine && make distcheck 2>&1
```

Zéro écart attendu. Si des fichiers manquent dans `MANIFEST` : les ajouter et relancer.

### 2.3 Tests complets

```bash
cd /home/civorra/Documents/Chorus/Engine && make test 2>&1
```

Tous les tests doivent passer (ok). Arrêter si un test échoue — ne jamais publier
une distribution avec des tests rouges.

### 2.4 Tests auteur (POD)

```bash
cd /home/civorra/Documents/Chorus/Engine && AUTHOR_TESTING=1 make test 2>&1
```

### 2.5 Vérification POD directe

```bash
cd /home/civorra/Documents/Chorus/Engine && perl -e "
  use Pod::Checker;
  podchecker('lib/Chorus/Engine.pm');
  podchecker('lib/Chorus/Expert.pm');
  podchecker('lib/Chorus/Frame.pm');
  podchecker('lib/Chorus/Collection/List.pm');
  podchecker('lib/Chorus/Collection/Filter.pm');
  podchecker('lib/Chorus/Engine/ECA.pod');
" 2>&1
```

Zéro erreur attendue.

---

## Phase 3 — Construction de la tarball

```bash
cd /home/civorra/Documents/Chorus/Engine && make dist 2>&1
```

Vérifie que la tarball `Chorus-Engine-X.YY.tar.gz` est créée dans `$ENGINE/`.

Inspecter le contenu pour confirmer l'absence de fichiers indésirables :

```bash
tar tzf /home/civorra/Documents/Chorus/Engine/Chorus-Engine-X.YY.tar.gz | sort
```

Points de contrôle :
- [ ] `lib/Chorus/Engine/ECA.pod` présent
- [ ] `eca/` absent
- [ ] `doc/` absent
- [ ] `MYMETA.*` absent
- [ ] `Makefile` (généré) absent — `Makefile.PL` présent ✓

---

## Phase 4 — Upload sur PAUSE

### 4.1 Prérequis credentials

Vérifier que `~/.pause` existe et contient les credentials :

```bash
test -f ~/.pause && echo "OK" || echo "MANQUANT — créer ~/.pause avec user/password PAUSE"
```

Format de `~/.pause` :
```
user PAUSEID
password MOTDEPASSE
```

### 4.2 Upload

```bash
cpan-upload /home/civorra/Documents/Chorus/Engine/Chorus-Engine-X.YY.tar.gz
```

Après l'upload :
- PAUSE envoie un e-mail de confirmation à l'adresse du compte
- L'indexation MetaCPAN prend généralement 15–60 minutes
- Vérifier sur : `https://metacpan.org/dist/Chorus-Engine`

---

## Phase 5 — Tag git et nettoyage

### 5.1 Tagger la release

```bash
git -C /home/civorra/Documents/Chorus/Engine tag vX.YY
git -C /home/civorra/Documents/Chorus/Engine push origin vX.YY
```

### 5.2 Pousser la branche

```bash
git -C /home/civorra/Documents/Chorus/Engine push origin devel
```

### 5.3 Nettoyer les artefacts de build

```bash
cd /home/civorra/Documents/Chorus/Engine && make distclean
```

Supprime : `Makefile`, `MYMETA.*`, `pm_to_blib`, `blib/`, la tarball `.tar.gz`.

---

## Checklist finale

- [ ] `$VERSION` bumpée dans `lib/Chorus/Engine.pm`
- [ ] `Changes` mis à jour avec la date et le résumé
- [ ] Commit de bump poussé sur `devel`
- [ ] `make manifest` — MANIFEST cohérent, `ECA.pod` présent, `eca/` absent
- [ ] `make distcheck` — zéro écart
- [ ] `make test` — tous verts
- [ ] POD checker — zéro erreur sur les 6 fichiers
- [ ] `make dist` — tarball créée et inspectée
- [ ] `cpan-upload` — confirmation PAUSE reçue
- [ ] `git tag vX.YY && git push origin vX.YY`
- [ ] `make distclean` — répertoire propre

---

## Référence rapide

```
1. grep VERSION lib/Chorus/Engine.pm          # version actuelle
2. [éditer $VERSION + Changes]
3. git add lib/Chorus/Engine.pm Changes && git commit -m "release: bump version to X.YY"
4. perl Makefile.PL && make manifest          # synchroniser MANIFEST
5. make distcheck                             # vérifier les écarts
6. make test                                  # tous verts
7. AUTHOR_TESTING=1 make test                 # POD
8. make dist                                  # → Chorus-Engine-X.YY.tar.gz
9. tar tzf Chorus-Engine-X.YY.tar.gz | sort  # inspecter
10. cpan-upload Chorus-Engine-X.YY.tar.gz    # upload PAUSE
11. git tag vX.YY && git push origin vX.YY   # tag
12. make distclean                            # nettoyage
```

---

## Notes

**`cpan-upload` absent ?**

```bash
cpan CPAN::Uploader
```

**Tester la tarball localement avant upload :**

```bash
cd /tmp && tar xzf /home/civorra/Documents/Chorus/Engine/Chorus-Engine-X.YY.tar.gz
cd Chorus-Engine-X.YY && perl Makefile.PL && make test
```

**Vérifier l'indexation après upload :**
`https://metacpan.org/dist/Chorus-Engine` — rafraîchir jusqu'à voir la nouvelle version.

**PAUSE :** `https://pause.perl.org` — compte requis pour uploader.
Queue de bugs : `https://rt.cpan.org/Dist/Display.html?Name=Chorus-Engine`
