#!/usr/bin/env bash
#
# build-runtime-tarball.sh — Génère un tarball runtime autonome pour une sandbox
#                             Chorus, exécutable sans installation Makefile.PL
#                             préalable (Chorus::* pur Perl, pas de XS/.so).
#
# Usage:
#   scripts/build-runtime-tarball.sh <sandbox-slug> [output-dir]
#
# Exemple:
#   scripts/build-runtime-tarball.sh 09-cyber-sec-ANSII-CBOM
#   scripts/build-runtime-tarball.sh 09-cyber-sec-ANSII-CBOM /tmp/out
#
# Prérequis:
#   - Le script doit être lancé depuis n'importe où — $ENGINE_ROOT est calculé
#     relativement à l'emplacement du script (scripts/ → racine du dépôt).
#   - La sandbox <slug>/ doit exister quelque part sous un des racines connues
#     (auto-détection, aucun argument requis) : sandboxes-cyber-sec/, sandboxes/,
#     sandboxes-misc/ — recherche par ordre de priorité, premier match retenu.
#     Si le même slug existe sous plusieurs racines → erreur (ambiguïté).
#   - run.pl doit utiliser "use lib \"\$Bin/../../lib\";" (pas "Engine/lib").
#
# Sortie:
#   <output-dir>/chorus-runtime-<slug>.tar.gz
#   (output-dir par défaut : la racine détectée contenant la sandbox)
#
# Structure produite (voir $ENGINE_ROOT/AGENTS.md — section runtime packaging):
#   lib/Chorus/...                              (moteur générique, partagé)
#   <sandboxes-root>/<slug>/run.pl
#   <sandboxes-root>/<slug>/lib/<Namespace>/...
#   <sandboxes-root>/<slug>/rules/...
#
# Explicitement exclu (non nécessaire à l'exécution):
#   agent/, corpus/, .eca/, README.org, SCOPING*.md, CORPUS-DIRECTIVES.md,
#   enterprise/, projet-*.json (fichiers projet — fournis par l'utilisateur final)

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────
# Résolution des chemins
# ─────────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

SANDBOX_SLUG="${1:-}"

print_usage() {
    cat <<EOF
Usage: $0 <sandbox-slug> [output-dir]

  <sandbox-slug>   Nom du dossier sandbox à packager (auto-détecté sous
                   sandboxes-cyber-sec/, sandboxes/, ou sandboxes-misc/ —
                   ordre de priorité, aucun argument de racine requis).
  [output-dir]     Répertoire de sortie du tarball (défaut : la racine
                   où la sandbox a été détectée).

Exemples:
  $0 09-cyber-sec-ANSII-CBOM
  $0 09-cyber-sec-ANSII-CBOM /tmp/out

Options:
  -h, --help       Affiche cette aide et quitte.

Sortie: <output-dir>/chorus-runtime-<slug>.tar.gz
EOF
}

if [[ -z "$SANDBOX_SLUG" || "$SANDBOX_SLUG" == "-h" || "$SANDBOX_SLUG" == "--help" ]]; then
    print_usage
    if [[ -z "$SANDBOX_SLUG" ]]; then exit 1; else exit 0; fi
fi

ENGINE_LIB_SRC="$ENGINE_ROOT/lib/Chorus"
if [[ ! -d "$ENGINE_LIB_SRC" ]]; then
    echo "❌ Moteur introuvable : $ENGINE_LIB_SRC" >&2
    exit 1
fi

# ─────────────────────────────────────────────────────────────────────────
# Auto-détection de la racine des sandboxes (aucun argument requis)
# Ordre de priorité : sandboxes-cyber-sec/ > sandboxes/ > sandboxes-misc/
# ─────────────────────────────────────────────────────────────────────────
SANDBOX_ROOTS_CANDIDATES=(
    "$ENGINE_ROOT/sandboxes-cyber-sec"
    "$ENGINE_ROOT/sandboxes"
    "$ENGINE_ROOT/sandboxes-misc"
)

MATCHES=()
for root in "${SANDBOX_ROOTS_CANDIDATES[@]}"; do
    if [[ -d "$root/$SANDBOX_SLUG" ]]; then
        MATCHES+=("$root")
    fi
done

if [[ ${#MATCHES[@]} -eq 0 ]]; then
    echo "❌ Sandbox '$SANDBOX_SLUG' introuvable sous aucune racine connue :" >&2
    for root in "${SANDBOX_ROOTS_CANDIDATES[@]}"; do
        echo "     - $root/$SANDBOX_SLUG" >&2
    done
    exit 1
fi
if [[ ${#MATCHES[@]} -gt 1 ]]; then
    echo "❌ Ambiguïté : '$SANDBOX_SLUG' existe sous plusieurs racines :" >&2
    for m in "${MATCHES[@]}"; do
        echo "     - $m/$SANDBOX_SLUG" >&2
    done
    echo "   Renommer l'une des deux sandboxes pour lever l'ambiguïté." >&2
    exit 1
fi

SANDBOX_ROOT="${MATCHES[0]}"
SANDBOX_ROOT_NAME="$(basename "$SANDBOX_ROOT")"
SANDBOX_SRC="$SANDBOX_ROOT/$SANDBOX_SLUG"
OUTPUT_DIR="${2:-$SANDBOX_ROOT}"

echo "[build-runtime] Racine détectée : $SANDBOX_ROOT_NAME/"

if [[ ! -f "$SANDBOX_SRC/run.pl" ]]; then
    echo "❌ run.pl introuvable dans $SANDBOX_SRC" >&2
    exit 1
fi

# ─────────────────────────────────────────────────────────────────────────
# Garde-fou : run.pl doit référencer "../../lib" (pas "../../Engine/lib")
# ─────────────────────────────────────────────────────────────────────────
if grep -q '\.\./\.\./Engine/lib' "$SANDBOX_SRC/run.pl"; then
    cat >&2 <<EOF
❌ $SANDBOX_SRC/run.pl utilise encore "\$Bin/../../Engine/lib" (chemin invalide).
   Corriger d'abord la ligne "use lib" vers "\$Bin/../../lib" avant de générer
   le tarball — sinon le run.pl embarqué ne trouvera pas Chorus::Engine/Expert/Frame
   une fois extrait ailleurs.
EOF
    exit 1
fi
if ! grep -q '\.\./\.\./lib' "$SANDBOX_SRC/run.pl"; then
    echo "⚠️  Avertissement : aucun \"use lib .../../lib\" détecté dans run.pl — vérifier manuellement." >&2
fi

# ─────────────────────────────────────────────────────────────────────────
# Staging
# ─────────────────────────────────────────────────────────────────────────
STAGE="$(mktemp -d /tmp/chorus-runtime-staging.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT

echo "[build-runtime] Staging → $STAGE"

mkdir -p "$STAGE/lib/Chorus" "$STAGE/$SANDBOX_ROOT_NAME/$SANDBOX_SLUG"

# Moteur générique (partagé)
cp -a "$ENGINE_LIB_SRC/." "$STAGE/lib/Chorus/"

# Sandbox : run.pl + lib/<Namespace> + rules/
cp -a "$SANDBOX_SRC/run.pl" "$STAGE/$SANDBOX_ROOT_NAME/$SANDBOX_SLUG/"

if [[ -d "$SANDBOX_SRC/lib" ]]; then
    cp -a "$SANDBOX_SRC/lib" "$STAGE/$SANDBOX_ROOT_NAME/$SANDBOX_SLUG/"
else
    echo "⚠️  Avertissement : pas de dossier lib/ dans la sandbox — run.pl risque d'échouer (namespace agents manquant)." >&2
fi

if [[ -d "$SANDBOX_SRC/rules" ]]; then
    cp -a "$SANDBOX_SRC/rules" "$STAGE/$SANDBOX_ROOT_NAME/$SANDBOX_SLUG/"
else
    echo "⚠️  Avertissement : pas de dossier rules/ dans la sandbox — le moteur n'aura aucune règle à évaluer." >&2
fi

# ─────────────────────────────────────────────────────────────────────────
# Test de fumée (smoke test) — exécution avec PERL5LIB vidé, depuis le staging
# ─────────────────────────────────────────────────────────────────────────
echo "[build-runtime] Smoke test (perl -c) sans PERL5LIB..."
if ! ( cd "$STAGE/$SANDBOX_ROOT_NAME/$SANDBOX_SLUG" && \
       env -i PATH="/usr/bin:/bin" HOME="$HOME" PERL5LIB="" perl -c run.pl >/tmp/chorus-runtime-smoketest.log 2>&1 ); then
    echo "❌ Échec du smoke test (perl -c run.pl) :" >&2
    cat /tmp/chorus-runtime-smoketest.log >&2
    exit 1
fi
echo "[build-runtime] ✅ Smoke test OK"

# ─────────────────────────────────────────────────────────────────────────
# Archive finale
# ─────────────────────────────────────────────────────────────────────────
mkdir -p "$OUTPUT_DIR"
TARBALL="$OUTPUT_DIR/chorus-runtime-${SANDBOX_SLUG}.tar.gz"

( cd "$STAGE" && tar -czf "$TARBALL" lib/ "$SANDBOX_ROOT_NAME/" )

echo "[build-runtime] ✅ Tarball généré : $TARBALL"
echo "[build-runtime]    $(du -h "$TARBALL" | cut -f1)"
echo
echo "Utilisation par le tiers :"
echo "  tar -xzf $(basename "$TARBALL")"
echo "  cp my-project.json $SANDBOX_ROOT_NAME/$SANDBOX_SLUG/"
echo "  cd $SANDBOX_ROOT_NAME/$SANDBOX_SLUG"
echo "  perl run.pl my-project.json"
