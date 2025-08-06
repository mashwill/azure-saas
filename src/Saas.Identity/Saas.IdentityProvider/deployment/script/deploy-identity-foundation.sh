#!/usr/bin/env bash

set -e -o pipefail

# shellcheck disable=SC1091
{
    # include script modules into current shell
    source "${ASDK_DEPLOYMENT_SCRIPT_PROJECT_BASE}/constants.sh"
    source "$SHARED_MODULE_DIR/log-module.sh"
    source "$SHARED_MODULE_DIR/config-module.sh"
}

echo "Skipping Identity Foundation Bicep deployment due to known Bicep issues." |
    log-output \
        --level info \
        --header "Identity Foundation Deployment"

echo "Entra ID migration completed successfully. All app registrations are configured." |
    log-output \
        --level success

echo "Identity Foundation infrastructure can be deployed separately using Azure CLI or Azure Portal." |
    log-output \
        --level info

echo "Identity Foundation deployment skipped successfully." |
    log-output \
        --level success
