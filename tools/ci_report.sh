#!/bin/sh
# Affiche le résultat et les annotations (version de Xcode, erreurs, avertissements) du dernier build GitHub.
R=rubenmfp/iptvapple
RUN=${1:-$(gh run list -R $R -L 1 --json databaseId --jq '.[0].databaseId')}
gh run watch "$RUN" -R $R --exit-status >/dev/null 2>&1; echo "run $RUN exit=$?"
JOB=$(gh api repos/$R/actions/runs/$RUN/jobs --jq '.jobs[0].id')
gh api repos/$R/actions/runs/$RUN/jobs --jq '.jobs[0].steps[] | "\(.name): \(.conclusion)"'
gh api repos/$R/check-runs/$JOB/annotations --paginate --jq '.[] | "[\(.annotation_level)] \(.title): \(.message)"'
