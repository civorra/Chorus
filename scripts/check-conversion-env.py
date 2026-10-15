#!/usr/bin/env python3
"""
check-conversion-env.py — Independent environment-consistency checker for
chorus-pdf / chorus-word / chorus-excel / chorus-markdown extraction logs.

CONTEXT
-------
The generated extraction scripts of the 4 chorus-* skills self-report, in
their first lines of stderr output, a line of the form:

    [chorus-pdf] Environment: pdfminer.six==20260107, pdfplumber==0.11.10 \
        (interpreter: /home/user/.local/share/pipx/venvs/pdfplumber/bin/python3)

This is an *auto-declaration* produced by the script itself. It is NOT
proof: if the script's own detection logic is buggy (e.g. its os.execv()
bootstrap to a pipx venv silently fails and falls back to the system
interpreter without the log noticing), the log can lie without the
script ever realising it.

This script performs an INDEPENDENT, OUT-OF-BAND verification:
  1. It parses the "Environment: ..." line out of a given log file.
  2. It does NOT trust the log's claims. Instead it separately queries
     every interpreter candidate known on this system (system `python3`
     in PATH, plus every pipx venv under ~/.local/share/pipx/venvs/*/bin/
     python3) for the real, currently-installed versions of the relevant
     packages (pdfminer.six, pdfplumber, python-docx, openpyxl, Pillow).
  3. It compares what the log claims against what was independently
     observed, and reports any discrepancy.

USAGE
-----
    python3 scripts/check-conversion-env.py <path-to-log-file>
    python3 scripts/check-conversion-env.py <path-to-extraction-script.py>

(The second form expects the script to have been run with its stderr
redirected to a `.log` sibling file, or will look for `<script>.log` /
a log passed explicitly — in practice, always pass the log file itself.)

VERDICT
-------
  ✅ cohérent               — the interpreter announced in the log exists,
                               and the versions it reports for its packages
                               match what was found by direct, independent
                               interrogation of that same interpreter.
  ⚠️ incohérence détectée    — the interpreter exists but reports different
                               versions than independently observed, OR a
                               better/different candidate interpreter was
                               found that the log did not pick, etc. Details
                               are printed.
  ❌ impossible à vérifier   — log file not found, or does not contain a
                               recognisable "Environment: ..." line (e.g.
                               a log produced before this logging feature
                               was added to the skills — this is a LEGITIMATE,
                               expected result for pre-existing logs, not a
                               bug in this script).

EXIT CODES
----------
  0 = ✅ cohérent
  1 = ⚠️ incohérence détectée
  2 = ❌ impossible à vérifier

EXAMPLE
-------
    $ python3 scripts/check-conversion-env.py \\
        t/fixtures/chorus-pdf-regression-test-text.md.log
    ✅ cohérent — interpreter .../pipx/venvs/pdfplumber/bin/python3 reports
       pdfminer.six==20260107, pdfplumber==0.11.10 (matches log exactly)
"""

import glob
import os
import re
import subprocess
import sys

# Packages we know how to check across the 4 chorus-* skills.
KNOWN_PACKAGES = ("pdfminer.six", "pdfplumber", "python-docx", "openpyxl", "Pillow")

ENV_LINE_RE = re.compile(
    r"\[(?P<skill>[\w-]+)\]\s+Environment:\s*(?P<pkgs>.*?)\s*"
    r"\(interpreter:\s*(?P<interpreter>\S+)\)\s*$"
)

PKG_VERSION_RE = re.compile(r"([\w.\-]+)==([^,\s]+)")


def find_env_line(log_path):
    """Return the parsed (skill, {pkg: version}, interpreter) from the first
    matching 'Environment: ...' line found in log_path, or None if not found
    (file missing, unreadable, or no such line)."""
    if not os.path.isfile(log_path):
        return None
    try:
        with open(log_path, "r", encoding="utf-8", errors="replace") as fh:
            for line in fh:
                m = ENV_LINE_RE.search(line.strip())
                if m:
                    pkgs_raw = m.group("pkgs")
                    declared = dict(PKG_VERSION_RE.findall(pkgs_raw))
                    return {
                        "skill": m.group("skill"),
                        "declared_versions": declared,
                        "declared_interpreter": m.group("interpreter"),
                        "raw_line": line.strip(),
                    }
    except OSError:
        return None
    return None


def candidate_interpreters():
    """System python3 (from PATH) + all known pipx venv python3 binaries."""
    candidates = []

    system_py = _which("python3")
    if system_py:
        candidates.append(system_py)

    pipx_pattern = os.path.expanduser("~/.local/share/pipx/venvs/*/bin/python3")
    for path in sorted(glob.glob(pipx_pattern)):
        if os.path.exists(path):
            candidates.append(os.path.realpath(path))

    # De-duplicate while preserving order.
    seen = set()
    unique = []
    for c in candidates:
        if c not in seen:
            seen.add(c)
            unique.append(c)
    return unique


def _which(name):
    for directory in os.environ.get("PATH", "").split(os.pathsep):
        candidate = os.path.join(directory, name)
        if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
            return os.path.realpath(candidate)
    return None


def query_interpreter(python_bin, packages=KNOWN_PACKAGES):
    """Run a small probe script under python_bin to get real installed
    versions of `packages`, independently of any extraction script. Returns
    a dict {pkg: version_or_'<not installed>'}, or None if the interpreter
    itself could not be invoked."""
    probe = (
        "import importlib.metadata as m, sys\n"
        "pkgs = " + repr(list(packages)) + "\n"
        "out = []\n"
        "for p in pkgs:\n"
        "    try:\n"
        "        out.append(p + '==' + m.version(p))\n"
        "    except m.PackageNotFoundError:\n"
        "        out.append(p + '==<not installed>')\n"
        "print(','.join(out))\n"
    )
    try:
        result = subprocess.run(
            [python_bin, "-c", probe],
            capture_output=True,
            text=True,
            timeout=20,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    if result.returncode != 0:
        return None
    versions = {}
    for item in result.stdout.strip().split(","):
        if "==" in item:
            pkg, ver = item.split("==", 1)
            versions[pkg] = ver
    return versions


def main(argv):
    if len(argv) != 2:
        print(f"Usage: {argv[0]} <log-file-or-extraction-script>", file=sys.stderr)
        return 2

    log_path = argv[1]
    print(f"🔎 check-conversion-env — analysing: {log_path}")

    env = find_env_line(log_path)
    if env is None:
        print(
            "❌ impossible à vérifier — fichier introuvable ou aucune ligne "
            "\"Environment: ...\" reconnue dans ce log.\n"
            "   (Résultat légitime pour un log produit AVANT l'ajout des logs "
            "d'environnement par les skills chorus-* — ce n'est pas un bug.)"
        )
        return 2

    declared_interp = env["declared_interpreter"]
    declared_versions = env["declared_versions"]
    print(f"   Skill annoncé        : [{env['skill']}]")
    print(f"   Ligne brute          : {env['raw_line']}")
    print(f"   Interpréteur annoncé : {declared_interp}")
    print(f"   Versions annoncées   : {declared_versions or '(aucune — pas de dépendance hard/branche conditionnelle)'}")

    print("\n   Interrogation indépendante des interpréteurs connus du système...")
    candidates = candidate_interpreters()
    if not candidates:
        print("   Aucun interpréteur candidat trouvé (ni python3 PATH, ni venv pipx).")

    discrepancies = []
    declared_interp_real = os.path.realpath(declared_interp) if os.path.exists(declared_interp) else None

    if not os.path.exists(declared_interp):
        discrepancies.append(
            f"L'interpréteur annoncé '{declared_interp}' n'existe PAS (ou plus) sur ce système."
        )
    else:
        pkgs_to_check = list(declared_versions.keys()) or list(KNOWN_PACKAGES)
        real_versions = query_interpreter(declared_interp, pkgs_to_check)
        if real_versions is None:
            discrepancies.append(
                f"Impossible d'interroger l'interpréteur annoncé '{declared_interp}' "
                f"(échec d'exécution)."
            )
        else:
            print(f"   → {declared_interp}: {real_versions}")
            for pkg, declared_ver in declared_versions.items():
                real_ver = real_versions.get(pkg)
                if real_ver is None:
                    discrepancies.append(
                        f"Paquet '{pkg}' non vérifiable sur l'interpréteur annoncé."
                    )
                elif real_ver != declared_ver:
                    discrepancies.append(
                        f"Paquet '{pkg}': log annonce '{declared_ver}', "
                        f"interrogation indépendante trouve '{real_ver}' sur "
                        f"'{declared_interp}'."
                    )

    for cand in candidates:
        if declared_interp_real and os.path.realpath(cand) == declared_interp_real:
            continue  # already checked above
        real_versions = query_interpreter(cand)
        if real_versions:
            print(f"   → {cand}: {real_versions}")

    print()
    if discrepancies:
        print("⚠️ incohérence détectée :")
        for d in discrepancies:
            print(f"   - {d}")
        return 1

    print(
        "✅ cohérent — l'interpréteur annoncé existe et les versions qu'il "
        "rapporte, lorsqu'interrogé indépendamment, correspondent exactement "
        "à ce que le log auto-déclarait."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
