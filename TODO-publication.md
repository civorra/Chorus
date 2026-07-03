# TODO — Publication Chorus::Engine v2

## 🔴 Critique — fait

- [x] Réécrire POD `NAME` / `DESCRIPTION` pour v2 (`Engine.pm`)
- [x] Ajouter `keywords` dans `META_MERGE` (`Makefile.PL`)

## 🟠 Important — à faire avant publication

- [x] **GitHub Actions CI** — workflow `make test` + badge README/LISEZMOI
- [ ] **Description "About" GitHub** (UI → ⚙️ → About) :
      > Perl inference engine — LLM formalises rules from normative corpora,
      > Chorus executes them deterministically.
- [ ] **Topics GitHub** (UI → ⚙️ → Topics) :
      `perl` `inference-engine` `expert-system` `rule-engine`
      `compliance` `symbolic-ai` `llm` `yaml`
- [ ] **Pinned repositories** — épingler `Chorus` sur le profil GitHub

## 🟡 Utile — avant / jour J

- [ ] **PrePAN** — poster une review request avant la publication CPAN
      <http://prepan.org>
- [x] **Réécrire POD `DESCRIPTION`** plus orienté v2 (corpus → pipeline → conformité)
- [ ] **Article blogs.perl.org** — présentation jour J
      Angle suggéré : pipeline complet corpus → rapport de conformité

## 🟢 Amplification — jour J / J+1

- [ ] **PerlWeekly** — soumettre le lien via le formulaire
      <https://perlweekly.com> (~3 000 abonnés, envoi hebdomadaire)
- [ ] **r/perl** — annonce technique, angle `chorus-feed` + sandbox demo
- [ ] **Hacker News `Show HN:`** — angle percutant :
      *"LLM generates rules, Perl engine executes them — deterministically"*
- [ ] **r/MachineLearning** ou **r/LocalLLaMA** — angle symbolique augmenté :
      Chorus comme couche déterministe au-dessus d'un LLM

## ⚙️ Automatique à la publication CPAN (rien à faire)

- MetaCPAN Recent Releases — flux RSS/JSON, scraped par PerlWeekly et blogs
- CPAN Testers — smoke tests 200+ configs Perl/OS sous 24–48h
- PAUSE announcement — email `modules@perl.org`, archivé
- `Chorus::Frame` reverse deps — MetaCPAN liste Chorus::Engine automatiquement
