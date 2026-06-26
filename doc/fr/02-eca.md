# Chorus à l'ère des LLMs

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

## Couplage avec un outil LLM — l'architecture ECA

Imaginez la scène : vous avez un PDF de 150 pages — une norme de construction,
un DTU, un cahier des charges technique. D'ici la fin de la session, vous voulez
un pipeline d'inférence Chorus opérationnel qui valide des projets réels contre
cette norme. Pas un prototype : un moteur avec des agents spécialisés, des règles
YAML idempotentes, des tables normatives extraites du document, une infrastructure
Perl correctement câblée, et un rapport de conformité structuré.

Sans assistance : plusieurs jours de travail Perl expert. Avec ECA et ses skills
Chorus, c'est l'affaire d'une session.

> **ECA est un outil de développement, pas une dépendance d'exécution.** Le
> pipeline qu'il génère est du Perl pur — `Feed.pm`, `Agent/*.pm`, `Expert.pm`,
> `run.pl`. Il tourne sur n'importe quelle machine avec Perl installé, sans ECA,
> sans connexion réseau. Une fois généré, le pipeline est entièrement autonome.

> **Les fichiers KB (`.org`)** sont du texte structuré lisible avec n'importe
> quel éditeur — vim, VSCode, nano. Emacs offre le meilleur rendu des tableaux
> et du balisage, mais il n'est pas requis pour lire, modifier ou versionner ces
> fichiers.

**Ce que la chaîne fait concrètement :**

```
chorus-pdf  norme.pdf --auto
    → extrait le texte page par page (pdfminer pour le texte,
      vision LLM pour les figures et tableaux)
    → corpus/001-norme-vision.md

chorus-feed mon-sandbox corpus/001-norme-vision.md
    → identifie les spécialités → agents
    → conçoit l'ontologie de slots
    → écrit eca/agents/<specialite>.org (KB par agent)
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
produits par ECA, un par agent, qui contiennent tout ce que le moteur a besoin de
savoir : l'ontologie du domaine, le dictionnaire des slots, le catalogue des règles
avec leur code, les helpers Perl avec leur source normative (`# §4.2 DTU 31.2`).

Ces fichiers sont lisibles par un ingénieur du domaine sans qu'il sache lire du
Perl. Il peut corriger une table, contester une règle, affiner une contrainte.
ECA relit la KB corrigée et régénère les artefacts en aval. Chorus exécute le
résultat sans jamais impliquer le LLM — de façon déterministe, à l'identique,
autant de fois qu'on veut.

```
norme.pdf
    │ chorus-pdf
    ▼
corpus/
    │ chorus-feed
    ▼
eca/agents/*.org  ←──── l'expert du domaine lit, corrige, affine
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
générée par ECA depuis le corpus. Aucune ligne écrite à la main.

> Les skills ECA pour Chorus (`chorus-pdf`, `chorus-feed`, `chorus-check`,
> `chorus-create-project`, `chorus-import-project`) sont versionnés dans
> `$ENGINE/eca/skills/` et documentés dans le dépôt.

> **Explorer sans ECA :** les sandboxes `examples/sandboxes/cob-compliance_fr`
> et `cob-compliance_en` contiennent l'intégralité des artefacts produits par la
> chaîne (corpus, KB org, règles YAML, infrastructure Perl). Ils permettent de
> comprendre ce qu'ECA génère avant même de l'installer — et de lancer
> `perl run.pl project-demo.json` pour voir le résultat en direct.

---

## En résumé

Les LLMs excellent à traiter ce qui est **vaste et ambigu**.
Chorus excelle à traiter ce qui est **précis et certifiable**.

Pour un développeur ou un expert qui a besoin de *maîtriser* la connaissance
qu'il modélise — et pas seulement de l'utiliser — Chorus reste un outil
irremplaçable, précisément parce qu'il répond à un problème que les LLMs
ne peuvent pas résoudre par construction.

---

## Domaines d'application

> Voir [`03-applications.md`](03-applications.md) — analyse secteur par secteur,
> pattern de compatibilité, temps d'onboarding estimé par domaine.
