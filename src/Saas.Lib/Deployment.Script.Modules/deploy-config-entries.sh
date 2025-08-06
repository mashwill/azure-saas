#!/usr/bin/env bash

set -u -e -o pipefail

# shellcheck disable=SC1091
{
    # include script modules into current shell
    source "${ASDK_DEPLOYMENT_SCRIPT_PROJECT_BASE}/constants.sh"
    source "$SHARED_MODULE_DIR/log-module.sh"
    source "$SHARED_MODULE_DIR/config-module.sh"
    source "$SHARED_MODULE_DIR/deploy-service-module.sh"
}

prepare-parameters-file "${BICEP_PARAMETERS_TEMPLATE_FILE}" "${BICEP_CONFIG_ENTRIES_DEPLOY_PARAMETERS_FILE}"

resource_group="$(get-value ".deployment.resourceGroup.name")"
identity_foundation_deployment_name="$(get-value ".deployment.identityFoundation.name")"
subscriptionId="$(get-value ".initConfig.subscriptionId")"

echo "Deploying Config Entries: Using mock Identity Foundation outputs since Bicep deployment was skipped..." |
    log-output \
        --level info

# Since we skipped the Bicep deployment, use our mock output file
if [[ -f "${BICEP_IDENTITY_FOUNDATION_OUTPUT_FILE}" ]]; then
    echo "Using existing mock Identity Foundation outputs file" |
        log-output \
            --level info
else
    echo "Creating mock Identity Foundation outputs file..." |
        log-output \
            --level info
    
    # Create the mock output file with our deployment values
    cat > "${BICEP_IDENTITY_FOUNDATION_OUTPUT_FILE}" << 'EOF'
{
  "version": {
    "value": "0.8.0"
  },
  "environment": {
    "value": "Production"
  },
  "appServicePlanName": {
    "value": "asp-amtc-dev-tx5l"
  },
  "keyVaultName": {
    "value": "kv-amtc-dev-tx5l"
  },
  "keyVaultUri": {
    "value": "https://kv-amtc-dev-tx5l.vault.azure.net/"
  },
  "location": {
    "value": "southafricanorth"
  },
  "userAssignedIdentityName": {
    "value": "id-amtc-dev-tx5l"
  },
  "appConfigurationName": {
    "value": "appcs-amtc-dev-tx5l"
  },
  "logAnalyticsWorkspaceName": {
    "value": "law-amtc-dev-tx5l"
  },
  "applicationInsightsName": {
    "value": "appi-amtc-dev-tx5l"
  }
}
EOF
fi

echo "Provisioning the ${APP_NAME} Configuration Entries." |
    log-output \
        --level info

"${SCRIPT_DIR}/"map-to-config-entries-parameters.py \
    "${APP_NAME}" \
    "${BICEP_IDENTITY_FOUNDATION_OUTPUT_FILE}" \
    "${BICEP_CONFIG_ENTRIES_DEPLOY_PARAMETERS_FILE}" \
    "${CONFIG_FILE}" |
    log-output \
        --level info ||
    echo "Failed to map ${APP_NAME} services parameters" |
    log-output \
        --level error \
        --header "Critical Error"

deployment_name="$(get-value ".deployment.${APP_DEPLOYMENT_NAME}.name")"
deployment_name="${deployment_name}-config-entries"

echo "Provisioning '${deployment_name}' to resource group ${resource_group}..." |
    log-output \
        --level info

deploy-service \
    "${resource_group}" \
    "${BICEP_CONFIG_ENTRIES_DEPLOY_PARAMETERS_FILE}" \
    "${DEPLOY_CONFIG_ENTRIES_BICEP_FILE}" \
    "${deployment_name}"

echo "Done. '${deployment_name}' was successfully provisioned to resource group ${resource_group}..." |
    log-output \
        --level success
