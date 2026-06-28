# Skill — cpan-release

> Trigger: `cpan-release`
> Agent: `code`
>
> **Single responsibility: publish a new version of Chorus::Engine to PAUSE/CPAN.**
> This skill covers the version bump, artifact verification, tarball build,
> PAUSE upload, and git tagging.
>
> Repository: `$ENGINE` = `/home/civorra/Documents/Chorus/Engine`
> Upload tool: `cpan-upload` (CPAN::Uploader) — credentials in `~/.pause`

---

## ⚡ Step 0 — Current State (always first)

Run sequentially:

```bash
# Version actuelle dans le module
grep "VERSION" /home/civorra/Documents/Chorus/Engine/lib/Chorus/Engine.pm | head -3

# Dernier tag git
git -C /home/civorra/Documents/Chorus/Engine tag --sort=-v:refname | head -5

# Repository status
git -C /home/civorra/Documents/Chorus/Engine status
```

Display the result and ask for confirmation before continuing:

> "Current version: X.YY — last tag: vX.YY — N modified files.
> What will the new version be? (e.g. 1.06)"

---

## Phase 1 — Version Bump

### 1.1 Bump `$VERSION` in `Engine.pm`

A single location to update (`VERSION_FROM` in `Makefile.PL` points to this file):

```perl
# lib/Chorus/Engine.pm
our $VERSION = 'X.YY';   # → nouvelle version
```

### 1.2 Update `Changes`

Expected format at the top of `Changes`:

```
X.YY    YYYY-MM-DD
        - <description des changements>
        - <description des changements>
```

Propose a summary of commits since the last tag:

```bash
git -C /home/civorra/Documents/Chorus/Engine log --oneline $(git -C /home/civorra/Documents/Chorus/Engine tag --sort=-v:refname | head -1)..HEAD
```

### 1.3 Commit the Bump

```bash
git -C /home/civorra/Documents/Chorus/Engine add lib/Chorus/Engine.pm Changes
git -C /home/civorra/Documents/Chorus/Engine commit -m "release: bump version to X.YY"
```

---

## Phase 2 — Artifact Verification

### 2.1 Regenerate MANIFEST

```bash
cd /home/civorra/Documents/Chorus/Engine && perl Makefile.PL && make manifest
```

Verify that `lib/Chorus/Engine/ECA.pod` is present in `MANIFEST`.
Verify that `agent/`, `doc/`, `MYMETA.*`, `Makefile` are absent (excluded by `MANIFEST.SKIP`).

### 2.2 Check MANIFEST Discrepancies

```bash
cd /home/civorra/Documents/Chorus/Engine && make distcheck 2>&1
```

Zero discrepancies expected. If files are missing from `MANIFEST`: add them and re-run.

### 2.3 Full Test Suite

```bash
cd /home/civorra/Documents/Chorus/Engine && make test 2>&1
```

All tests must pass (ok). Stop if a test fails — never publish a distribution with failing tests.

### 2.4 Author Tests (POD)

```bash
cd /home/civorra/Documents/Chorus/Engine && AUTHOR_TESTING=1 make test 2>&1
```

### 2.5 Direct POD Check

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

Zero errors expected.

---

## Phase 3 — Tarball Build

```bash
cd /home/civorra/Documents/Chorus/Engine && make dist 2>&1
```

Verify that the tarball `Chorus-Engine-X.YY.tar.gz` is created in `$ENGINE/`.

Inspect the contents to confirm the absence of unwanted files:

```bash
tar tzf /home/civorra/Documents/Chorus/Engine/Chorus-Engine-X.YY.tar.gz | sort
```

Checkpoints:
- [ ] `lib/Chorus/Engine/ECA.pod` present
- [ ] `agent/skills/` present (except `cpan-release.md`)
- [ ] `agent/org/` present
- [ ] `agent/sessions/` absent
- [ ] `doc/` present
- [ ] `MYMETA.*` absent
- [ ] `Makefile` (generated) absent — `Makefile.PL` present ✓

---

## Phase 4 — PAUSE Upload

### 4.1 Credentials Check

Verify that `~/.pause` exists and contains the credentials:

```bash
test -f ~/.pause && echo "OK" || echo "MISSING — create ~/.pause with PAUSE user/password"
```

Format of `~/.pause`:
```
user PAUSEID
password MOTDEPASSE
```

### 4.2 Upload

```bash
cpan-upload /home/civorra/Documents/Chorus/Engine/Chorus-Engine-X.YY.tar.gz
```

After the upload:
- PAUSE sends a confirmation email to the account address
- MetaCPAN indexing typically takes 15–60 minutes
- Check at: `https://metacpan.org/dist/Chorus-Engine`

---

## Phase 5 — Git Tag and Cleanup

### 5.1 Tag the Release

```bash
git -C /home/civorra/Documents/Chorus/Engine tag vX.YY
git -C /home/civorra/Documents/Chorus/Engine push origin vX.YY
```

### 5.2 Push the Branch

```bash
git -C /home/civorra/Documents/Chorus/Engine push origin devel
```

### 5.3 Clean Up Build Artifacts

```bash
cd /home/civorra/Documents/Chorus/Engine && make distclean
```

Removes: `Makefile`, `MYMETA.*`, `pm_to_blib`, `blib/`, the `.tar.gz` tarball.

---

## Final Checklist

- [ ] `$VERSION` bumped in `lib/Chorus/Engine.pm`
- [ ] `Changes` updated with date and summary
- [ ] Bump commit pushed to `devel`
- [ ] `make manifest` — consistent MANIFEST, `ECA.pod` present, `agent/` absent
- [ ] `make distcheck` — zero discrepancies
- [ ] `make test` — all green
- [ ] POD checker — zero errors across all 6 files
- [ ] `make dist` — tarball created and inspected
- [ ] `cpan-upload` — PAUSE confirmation received
- [ ] `git tag vX.YY && git push origin vX.YY`
- [ ] `make distclean` — clean directory

---

## Quick Reference

```
1. grep VERSION lib/Chorus/Engine.pm          # current version
2. [edit $VERSION + Changes]
3. git add lib/Chorus/Engine.pm Changes && git commit -m "release: bump version to X.YY"
4. perl Makefile.PL && make manifest          # synchronise MANIFEST
5. make distcheck                             # check discrepancies
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

**`cpan-upload` missing?**

```bash
cpan CPAN::Uploader
```

**Test the tarball locally before uploading:**

```bash
cd /tmp && tar xzf /home/civorra/Documents/Chorus/Engine/Chorus-Engine-X.YY.tar.gz
cd Chorus-Engine-X.YY && perl Makefile.PL && make test
```

**Check indexing after upload:**
`https://metacpan.org/dist/Chorus-Engine` — refresh until the new version appears.

**PAUSE:** `https://pause.perl.org` — account required to upload.
Bug queue: `https://rt.cpan.org/Dist/Display.html?Name=Chorus-Engine`
