# Chorus à l'ère des LLMs

## Pourquoi les systèmes experts ont échoué — et ce qui a changé

Les systèmes à base de règles des années 80–90 (CLIPS, OPS5, systèmes experts
commerciaux) reposaient sur des fondements théoriques solides : connaissance
explicite, raisonnement traçable, résultat déterministe. Ils ont échoué en
pratique pour trois raisons structurelles :

1. **L'acquisition des connaissances** — remplir une base de règles demandait
   des *knowledge engineers* dédiés et ne passait pas à l'échelle. Chaque nouveau
   domaine était un chantier long et coûteux.
2. **Le langage naturel** — le monde réel s'exprime en prose, en tableaux, en PDF
   et en notes informelles. Les parseurs symboliques cassaient à la première exception.
3. **La maintenance** — à mesure que la base de règles grossissait, les règles
   s'entrechoquaient, les exceptions s'accumulaient, et la base devenait ingérable.

Chorus-2.0 répond à ces trois problèmes, non pas en abandonnant l'approche
symbolique, mais en confiant exactement ces trois difficultés à un modèle de langage :

| Échec historique | Réponse Chorus-2.0 |
|---|---|
| Acquisition des connaissances | `chorus-feed` lit des documents bruts et alimente la KB automatiquement |
| Langage naturel en entrée | Le LLM extrait et structure ; le moteur ne parse jamais du texte libre |
| Maintenance des règles | Les règles YAML sont courtes, lisibles, versionnables, auditables à la main |

Le LLM fait ce qu'il fait bien — lire du texte ambigu à grande échelle. Le moteur
d'inférence fait ce qu'il fait bien — appliquer des règles de façon déterministe.
Aucun des deux n'empiète sur le domaine de l'autre.

> **Sur la terminologie.** L'étiquette *neuro-symbolique* est parfois appliquée
> à des systèmes comme Chorus. Elle est inexacte ici. Dans les systèmes
> neuro-symboliques, un modèle neuronal apprend à *simuler* des règles logiques.
> Dans Chorus, le moteur symbolique est réel — frames, slots, chaîne d'inférence
> explicite — et le LLM est un outil de prétraitement. *Symbolique augmenté* est
> une description plus précise.

---

Les grands modèles de langage (GPT, Claude, Gemini…) atteignent aujourd'hui
des performances remarquables sur des tâches de compréhension, de génération
et de raisonnement général. Cela pose une question légitime : à quoi sert
encore un moteur à règles comme Chorus ?

La réponse tient en un mot : **maîtrise**.

---

## Ce que les LLMs ne donnent pas

Un LLM « sait » des choses, mais cette connaissance est implicite, distribuée
dans des milliards de paramètres, et fondamentalement opaque. On ne peut pas :

- **pointer** la règle qui a produit un résultat particulier,
- **corriger** chirurgicalement une erreur sans réentraîner le modèle,
- **garantir** qu'une contrainte métier sera toujours respectée,
- **lire ou transmettre** la connaissance modélisée à un expert humain.

Pour beaucoup d'usages, cette opacité est acceptable. Pour d'autres — domaines
réglementés, systèmes certifiables, expertise à auditer — elle est rédhibitoire.

---

## Ce que Chorus apporte

Avec Chorus, la connaissance est un **artefact explicite** : des frames lisibles,
des règles YAML versionnées, discutables. Un expert du domaine peut les lire,
les contester, les affiner. Chaque conclusion dispose d'une justification traçable.

---

## La complémentarité plutôt que la concurrence

| Tâche | Outil adapté |
|---|---|
| Compréhension de texte libre, extraction, génération | LLM |
| Validation de contraintes métier strictes | Chorus |
| Justification et traçabilité des décisions | Chorus |
| Adaptation rapide à un nouveau domaine | LLM |
| Garantie de conformité à une norme | Chorus |

Un LLM peut extraire et structurer les données d'entrée ; Chorus applique
les règles métier et certifie le résultat. Les deux se complètent sans se
concurrencer.

---

## Couplage avec un agent IA — l'architecture assistée par IA

Imaginez la scène : vous avez un PDF de 150 pages — une norme de construction,
un DTU, un cahier des charges technique. D'ici la fin de la session, vous voulez
un pipeline d'inférence Chorus opérationnel qui valide des projets réels contre
cette norme. Pas un prototype : un moteur avec des agents spécialisés, des règles
YAML idempotentes, des tables normatives extraites du document, une infrastructure
Perl correctement câblée, et un rapport de conformité structuré.

Sans assistance : plusieurs jours de travail Perl expert. Avec un agent IA et ses skills
Chorus, c'est l'affaire d'une session.

> **L'agent IA n'est pas une dépendance d'exécution.** Le pipeline qu'il génère est
> du Perl pur — `Feed.pm`, `Agent/*.pm`, `Expert.pm`, `run.pl`. Il tourne sur
> n'importe quelle machine avec Perl installé, sans agent IA, sans connexion réseau.
> Une fois généré, le pipeline est entièrement autonome pour l'exécution.
>
> **L'agent IA est une dépendance de projet.** Adapter un sandbox à un nouveau projet
> — aligner les documents d'ingénieur avec les slots de la KB et produire un
> fichier JSON projet valide — requiert `chorus-create-project` ou
> `chorus-import-project`, deux skills de l'agent IA. La dépendance est réelle et assumée :
> le LLM lit la KB et gère l'écart de terminologie qu'aucun script statique ne
> peut couvrir de façon générique. L'agent IA est aussi nécessaire lorsque le corpus
> normatif évolue — pour relancer `chorus-feed --enrich` puis `chorus-check`.

> **Les agents IA fonctionnent nativement sur Neovim, VS Code, IntelliJ et Emacs** — sans
> dépendance à un éditeur particulier. Les fichiers `AGENTS.md` et skills sont
> du Markdown plain ; ils fonctionnent de façon identique quel que soit l'éditeur.
>
> **Les fichiers KB (`.org`)** sont du texte structuré lisible avec n'importe
> quel éditeur. Les tableaux et headings s'affichent correctement dans
> `nvim-orgmode`, les extensions org de VS Code, et tout éditeur de texte.
> Emacs offre l'expérience org la plus riche, mais il n'est pas requis pour
> lire, modifier ou versionner ces fichiers.
>
> **ECA sous Emacs** s'adapte le mieux aux sessions Chorus longues : les
> fichiers org de la KB s'ouvrent comme buffers vivants, l'agent IA les
> modifie directement, et les récapitulatifs de session permettent de reprendre
> le contexte d'un jour à l'autre. Les autres éditeurs fonctionnent
> correctement ; cette combinaison réduit le plus de friction pour les cycles
> `chorus-feed` et d'enrichissement itératif.

**Ce que la chaîne fait concrètement :**

```
chorus-pdf  norme.pdf --auto
    → extrait le texte page par page (pdfminer pour le texte,
      vision LLM pour les figures et tableaux)
    → corpus/001-norme-vision.md

chorus-feed mon-sandbox corpus/001-norme-vision.md
    → identifie les spécialités → agents
    → conçoit l'ontologie de slots
    → écrit agent/agents/<specialite>.org (KB par agent)
    → génère rules/<specialite>/R01-xxx.yml … (règles YAML)
    → génère lib/MonApp/Agent/<Specialite>/Helpers.pm (tables normatives)

chorus-check mon-sandbox projet.json
    → lit la KB, génère Feed.pm + Agent/*.pm + Expert.pm + run.pl
    → lance perl run.pl projet.json
    → affiche le rapport de conformité
```

Trois commandes. Le reste est géré.

**Ce qui rend ça possible :**

L'astuce centrale est la **base de connaissance locale** — des fichiers org-mode
produits par l'agent IA, un par agent, qui contiennent tout ce que le moteur a besoin de
savoir : l'ontologie du domaine, le dictionnaire des slots, le catalogue des règles
avec leur code, les helpers Perl avec leur source normative (`# §4.2 DTU 31.2`).

Ces fichiers sont lisibles par un ingénieur du domaine sans qu'il sache lire du
Perl. Il peut corriger une table, contester une règle, affiner une contrainte.
L'agent IA relit la KB corrigée et régénère les artefacts en aval. Chorus exécute le
résultat sans jamais impliquer le LLM — de façon déterministe, à l'identique,
autant de fois qu'on veut.

```
norme.pdf
    │ chorus-pdf
    ▼
corpus/
    │ chorus-feed
    ▼
agent/agents/*.org  ←──── l'expert du domaine lit, corrige, affine
rules/**/*.yml
lib/**/Helpers.pm
    │ chorus-check
    ▼
Feed.pm · Agent/*.pm · Expert.pm · run.pl
    │ perl run.pl projet.json
    ▼
✅ CONFORME / ❌ NON_CONFORME  — avec motif, par élément, par agent
```

**Quand la norme change :**

```
chorus-feed mon-sandbox nouveau-corpus.txt --enrich
chorus-check mon-sandbox projet.json
```

La KB est mise à jour de façon incrémentale. L'infrastructure Perl est régénérée.
Le pipeline tourne à nouveau — résultat garanti conforme aux règles telles qu'elles
ont été définies, sans dérive.

**En pratique, sur un vrai domaine :**

Un sandbox de test COB (Construction Ossature Bois, DTU 31.2) a été construit
avec cette chaîne : 7 agents spécialisés, 37 règles YAML, 7 modules de helpers
avec tables EC5 et NF EN 338, un pipeline validant 210 éléments de bâtiment en
une passe. L'intégralité du code Perl et YAML — environ 2 000 lignes — a été
générée par un agent IA depuis le corpus. Aucune ligne écrite à la main.

> Les skills de l'agent IA pour Chorus (`chorus-pdf`, `chorus-feed`, `chorus-check`,
> `chorus-create-project`, `chorus-import-project`) sont versionnés dans
> `$ENGINE/agent/skills/` et documentés dans le dépôt.

> **Explorer le sandbox sans agent IA :** les sandboxes `examples/sandboxes/cob-compliance_fr`
> et `cob-compliance_en` contiennent l'intégralité des artefacts produits par la
> chaîne (corpus, KB org, règles YAML, infrastructure Perl). Ils permettent de
> comprendre ce qu'un agent IA génère et de lancer `perl run.pl project-demo.json` en
> direct — mais avec un JSON projet pré-construit. Adapter un nouveau projet
> requiert un agent IA.

---

## En résumé

Les LLMs excellent à traiter ce qui est **vaste et ambigu**.
Chorus excelle à traiter ce qui est **précis et certifiable**.

Pour un développeur ou un expert qui a besoin de *maîtriser* la connaissance
qu'il modélise — et pas seulement de l'utiliser — Chorus reste un outil
irremplaçable, précisément parce qu'il répond à un problème que les LLMs
ne peuvent pas résoudre par construction.

---

## Les commandes `chorus-*`

> Voir [`04-chorus-commands.md`](04-chorus-commands.md) — référence complète de
> `chorus-pdf`, `chorus-feed`, `chorus-check`, `chorus-create-project`,
> `chorus-import-project` : syntaxe, modes, prérequis, sorties, workflow de bout
> en bout et tableau de référence rapide.

---

## Domaines d'application

> Voir [`03-applications.md`](03-applications.md) — analyse secteur par secteur,
> pattern de compatibilité, temps d'onboarding estimé par domaine.
