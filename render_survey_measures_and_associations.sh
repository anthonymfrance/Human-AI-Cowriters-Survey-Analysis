#!/bin/bash
# Render the survey measures and associations report.

set -euo pipefail

export XDG_CACHE_HOME="${XDG_CACHE_HOME:-/tmp/quarto-cache}"

quarto render survey_measures_and_associations.qmd --output-dir survey_measures_and_associations
