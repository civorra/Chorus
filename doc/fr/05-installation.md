# Installation & environnement d'exécution

## Installer Chorus

Chorus s'installe depuis les sources, via git. Il n'existe pas d'autre canal
de distribution : les classes Perl de Chorus sur GitHub ne sont pas
systématiquement propagées sur le CPAN — **n'installez pas Chorus depuis
CPAN**. Le dépôt git est l'unique source faisant foi, aussi bien pour le
moteur Perl (`lib/`) que pour le pipeline assisté par IA (`agent/skills/`,
`agent/org/`).

```sh
git clone https://github.com/civorra/Chorus
cd Chorus
perl Makefile.PL && make && make test && make install
```

Cela installe le framework complet :

- `lib/` — le moteur d'inférence Perl : `Chorus::Engine`, `Chorus::Frame`,
  `Chorus::Expert`
- `agent/skills/` — les skills `chorus-*` (`chorus-feed`, `chorus-check`,
  `chorus-pdf`…) chargés par un agent IA
- `agent/org/` — les templates de KB et l'ontologie des agents
- `sandboxes/01-demo_en` et `sandboxes/02-nephro-KDIGO-compliance` — deux
  exemples complets, prêts à exécuter

## Dépendances à l'exécution

Le moteur d'inférence en lui-même est du Perl pur, 5.006+, sans dépendance
au-delà du cœur Perl et de quelques modules CPAN standards (`YAML`,
`Scalar::Util`, `Digest::MD5`). Une fois qu'un pipeline a été généré par
`chorus-check`, il tourne de façon totalement autonome :

```sh
# Sur n'importe quelle machine dotée de Perl — sans agent IA, sans réseau :
perl run.pl project.json
```

C'est tout l'intérêt de la conception en deux phases : l'agent IA n'intervient
que lors de la **Phase A** (construction de la KB et des règles à partir d'un
corpus). La **Phase B** (exécution d'un projet à travers le pipeline généré)
est du Perl déterministe, rien de plus.

## Environnement recommandé — ECA

Les commandes `chorus-*` sont des skills pour agent IA, pas des scripts
shell — elles doivent être chargées et exécutées par un agent de codage IA.
Chorus est en soi agnostique vis-à-vis de l'agent utilisé, et les skills ont
d'abord été validés depuis un terminal, avec Claude Code puis avec GitHub
Copilot. Cela dit, l'environnement réellement utilisé au quotidien pour
développer et faire tourner Chorus est **[ECA](https://eca.dev)** (Editor
Code Assistant) — un agent de codage IA agnostique vis-à-vis de l'éditeur,
qui fonctionne dans Neovim, IntelliJ, VS Code.
Quel que soit l'éditeur utilisé, la différence qu'apporte ECA n'a rien de
subtil : faire opérer l'agent directement à l'intérieur de l'éditeur —
mêmes buffers, même contexte projet, mêmes raccourcis — transforme ce qui
était auparavant une boucle de copier-coller entre un terminal et un éditeur
en un workflow réellement fluide, sur une seule et même surface. Exécution
de skills multi-fichiers, génération incrémentale de sandboxes, édition de
la KB en org-mode — tout cela s'intègre naturellement à l'éditeur plutôt que
de s'y greffer artificiellement.

Si vous êtes en train de choisir une configuration pour faire tourner le
pipeline assisté par IA de Chorus, ECA — dans l'éditeur que vous utilisez
déjà — est celle que ce projet recommande réellement. Voir
<https://eca.dev> pour démarrer.

## Résumé

| | |
|---|---|
| **Installer depuis** | git uniquement — `git clone` + `make` |
| **Ne pas installer depuis** | CPAN (pas systématiquement synchronisé avec GitHub) |
| **Dépendance runtime du moteur** | Perl 5.006+ et modules CPAN standards uniquement |
| **Runtime du pipeline généré** | Perl seul — sans agent IA, sans réseau |
| **Environnement agent IA recommandé** | [ECA](https://eca.dev) (Neovim, IntelliJ, VS Code) |
