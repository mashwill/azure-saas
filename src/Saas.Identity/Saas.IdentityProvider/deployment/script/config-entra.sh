#!/usr/bin/env bash

set -u -e -o pipefail

# shellcheck disable=SC1091
{
    # include script modules into current shell
    source "${ASDK_DEPLOYMENT_SCRIPT_PROJECT_BASE}/constants.sh"
    source "$SHARED_MODULE_DIR/config-module.sh"
    source "$SHARED_MODULE_DIR/colors-module.sh"
    source "$SHARED_MODULE_DIR/log-module.sh"
    source "$SHARED_MODULE_DIR/user-module.sh"
    source "$SHARED_MODULE_DIR/key-vault-module.sh"
}

# setting user context to the user that will be used to configure Entra ID
entra_config_usr_name="$(get-value ".deployment.entraId.username")"
set-user-context "${entra_config_usr_name}"

# run the shell script for provisioning the Entra ID app registrations
"${SCRIPT_DIR}/entra-app-registrations.sh" ||
    echo "Entra ID app registrations failed." |
    log-output \
        --level Error \
        --header "Critical Error" ||
    exit 1

echo "Entra ID app registrations have completed." |
    log-output \
        --level success

# resetting user context to the default User
reset-user-context

echo "Adding secrets to KeyVault" |
    log-output \
        --level info

key_vault_name="$(get-value ".deployment.keyVault.name")"

# read each item in the JSON array to an item in the Bash array
readarray -t app_reg_array < <(jq --compact-output '.appRegistrations[]' "${CONFIG_FILE}")

for app in "${app_reg_array[@]}"; do
    
    app_name="$(jq --raw-output '.name' <<<"${app}")"
    has_secret="$(jq --raw-output '.hasSecret' <<<"${app}")"
    secret_path="$(jq --raw-output '.secretPath' <<<"${app}")"

    if [[ "${has_secret}" == "true" && "${secret_path}" != "null" ]]; then
        echo "Adding secret for ${app_name} to KeyVault" |
            log-output \
                --level info

        add-secret-to-vault "${app_name}" "${key_vault_name}" "${secret_path}" ||
            echo "Failed to add secret for ${app_name} to KeyVault." |
            log-output \
                --level error \
                --header "Critical error" ||
            exit 1
    fi
done

echo "Entra ID configuration has completed." |
    log-output \
        --level success 