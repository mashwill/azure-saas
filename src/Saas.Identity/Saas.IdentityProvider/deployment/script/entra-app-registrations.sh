#!/usr/bin/env bash

set -u -e -o pipefail

# shellcheck disable=SC1091
{
    # include script modules into current shell
    source "${ASDK_DEPLOYMENT_SCRIPT_PROJECT_BASE}/constants.sh"
    source "$SHARED_MODULE_DIR/config-module.sh"
    source "$SHARED_MODULE_DIR/app-reg-module.sh"
    source "$SHARED_MODULE_DIR/colors-module.sh"
    source "$SHARED_MODULE_DIR/log-module.sh"
    source "$SHARED_MODULE_DIR/tenant-login-module.sh"
}

entra_tenant_name="$(get-value ".initConfig.entraId.domainName")"

# login to the Entra ID tenant
echo "Logging into Entra ID tenant ${entra_tenant_name}." |
    log-output \
        --level info \
        --header "Entra ID Tenant Login"

log-into-entra "${entra_tenant_name}" ||
    echo "Entra ID tenant login failed." |
    log-output \
        --level error \
        --header "Critical error" ||
    exit 1

echo "Entra ID tenant login successful." |
    log-output \
        --level success

echo "Adding app registrations to Entra ID tenant." |
    log-output \
        --level info \
        --header "Entra ID App Registrations"

# create the app registrations
declare -i scopes_length
declare -i permissions_length

# read each item in the JSON array to an item in the Bash array
readarray -t app_reg_array < <(jq --compact-output '.appRegistrations[]' "${CONFIG_FILE}")

entra_tenant_name="$(get-value ".deployment.entraId.name")" ||
    echo "Entra ID tenant name not found." |
    log-output \
        --level error \
        --header "Critical error" ||
    exit 1

echo "Setting instance https://login.microsoftonline.com" |
    log-output \
        --level info \
        --header "Entra ID Instance"

put-value ".deployment.entraId.instance" "https://login.microsoftonline.com"

# iterate through the Bash array of app registrations
for app in "${app_reg_array[@]}"; do
    
    app_name="$(jq --raw-output '.name' <<<"${app}")"
    app_type="$(jq --raw-output '.redirectType' <<<"${app}")"
    redirect_uri="$(jq --raw-output '.redirectUri' <<<"${app}")"
    logout_uri="$(jq --raw-output '.logoutUri' <<<"${app}")"
    application_id_uri="$(jq --raw-output '.applicationIdUri' <<<"${app}")"
    has_certificate="$(jq --raw-output '.certificate' <<<"${app}")"
    has_secret="$(jq --raw-output '.hasSecret' <<<"${app}")"
    sign_in_audience="$(jq --raw-output '.signInAudience' <<<"${app}")"
    is_allow_public_client_flows="$(jq --raw-output '.isAllowPublicClientFlows' <<<"${app}")"
    set_access_token_accepted_version_to_one="$(jq --raw-output '.setAccessTokenAcceptedVersionToOne' <<<"${app}")"

    echo "Creating app registration: ${app_name}" |
        log-output \
            --level info

    # create the app registration
    create-app-registration "${app_name}" "${app_type}" "${redirect_uri}" "${logout_uri}" "${application_id_uri}" "${sign_in_audience}" "${is_allow_public_client_flows}" "${set_access_token_accepted_version_to_one}" ||
        echo "Failed to create app registration ${app_name}." |
        log-output \
            --level error \
            --header "Critical error" ||
        exit 1

    # get the app registration details
    app_id="$(get-app-registration-id "${app_name}")"
    object_id="$(get-app-registration-object-id "${app_name}")"

    # update the config with the app registration details
    put-app-registration-value "${app_name}" "appId" "${app_id}"
    put-app-registration-value "${app_name}" "objectId" "${object_id}"

    # add certificate if needed
    if [[ "${has_certificate}" == "true" ]]; then
        certificate_path="$(get-app-registration-value "${app_name}" "publicKeyPath")"
        certificate_key_name="$(get-app-registration-value "${app_name}" "certificateKeyName")"

        if [[ -f "${certificate_path}" ]]; then
            echo "Adding certificate to app registration: ${app_name}" |
                log-output \
                    --level info

            add-certificate-to-app-registration "${app_name}" "${certificate_path}" ||
                echo "Failed to add certificate to app registration ${app_name}." |
                log-output \
                    --level error \
                    --header "Critical error" ||
                exit 1
        fi
    fi

    # add secret if needed
    if [[ "${has_secret}" == "true" ]]; then
        echo "Adding secret to app registration: ${app_name}" |
            log-output \
                --level info

        add-secret-to-app-registration "${app_name}" ||
            echo "Failed to add secret to app registration ${app_name}." |
            log-output \
                --level error \
                --header "Critical error" ||
            exit 1
    fi

    # add scopes if they exist
    scopes_length=$(jq '.scopes | length' <<<"${app}")
    if [[ "${scopes_length}" -gt 0 ]]; then
        echo "Adding scopes to app registration: ${app_name}" |
            log-output \
                --level info

        add-scopes-to-app-registration "${app_name}" "${app}" ||
            echo "Failed to add scopes to app registration ${app_name}." |
            log-output \
                --level error \
                --header "Critical error" ||
            exit 1
    fi

    # add permissions if they exist
    permissions_length=$(jq '.permissions | length' <<<"${app}")
    if [[ "${permissions_length}" -gt 0 ]]; then
        echo "Adding permissions to app registration: ${app_name}" |
            log-output \
                --level info

        add-permissions-to-app-registration "${app_name}" "${app}" ||
            echo "Failed to add permissions to app registration ${app_name}." |
            log-output \
                --level error \
                --header "Critical error" ||
            exit 1
    fi

    echo "App registration ${app_name} created successfully." |
        log-output \
            --level success
done

echo "Entra ID app registrations have completed." |
    log-output \
        --level success 