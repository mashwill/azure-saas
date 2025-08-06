#!/usr/bin/env bash

# shellcheck disable=SC1091
# include script modules into current shell
source "$SHARED_MODULE_DIR/config-module.sh"
source "$SHARED_MODULE_DIR/log-module.sh"

function create-app-registration() {
    local app_name="$1"
    local app_type="$2"
    local redirect_uri="$3"
    local logout_uri="$4"
    local application_id_uri="$5"
    local sign_in_audience="$6"
    local is_allow_public_client_flows="$7"
    local set_access_token_accepted_version_to_one="$8"

    local display_name="${app_name}"
    local app_json

    echo "Creating app registration: ${display_name}" |
        log-output \
            --level info

    # create app registration with redirect uri if provided
    if [[ -n "${redirect_uri}" &&
        ! "${redirect_uri}" == null &&
        ! "${redirect_uri}" == "null" ]]; then

        if [[ "${app_type}" == "web" ]]; then
            app_json="$(az ad app create \
                --display-name "${display_name}" \
                --web-redirect-uris "${redirect_uri}" \
                --only-show-errors \
                --query "{Id:id, AppId:appId}" ||
                echo "Failed to create app with web redirect uri: ${redirect_uri}" |
                log-output \
                    --level error \
                    --header "Critical error" ||
                exit 1)"

        elif [[ "${app_type}" == "publicClient" ]]; then
            app_json="$(az ad app create \
                --display-name "${display_name}" \
                --public-client-redirect-uris "${redirect_uri}" \
                --only-show-errors \
                --query "{Id:id, AppId:appId}" ||
                echo "Failed to create app with public client redirect uri: ${redirect_uri}" |
                log-output \
                    --level error \
                    --header "Critical error" ||
                exit 1)"
        fi
    else
        # create app registration without redirect uri
        app_json="$(az ad app create \
            --display-name "${display_name}" \
            --only-show-errors \
            --query "{Id:id, AppId:appId}" ||
            echo "Failed to create app without redirect uri" |
            log-output \
                --level error \
                --header "Critical error" ||
            exit 1)"
    fi

    echo "App created: ${app_json}" |
        log-output \
            --level success

    local obj_id=$(jq --raw-output '.Id' <<<"${app_json}")
    local app_id=$(jq --raw-output '.AppId' <<<"${app_json}")

    # add appId to config
    put-app-id "${app_name}" "${app_id}"
    put-app-object-id "${app_name}" "${obj_id}"

    # add application ID URI if provided
    if [[ -n "${application_id_uri}" &&
        ! "${application_id_uri}" == null &&
        ! "${application_id_uri}" == "null" ]]; then

        echo "Adding application ID URI: '${application_id_uri}' for app with id '${app_id}'." |
            log-output \
                --level info

        az ad app update \
            --id "${app_id}" \
            --identifier-uris "${application_id_uri}" \
            --only-show-errors |
            log-output \
                --level info ||
            echo "Failed to add application ID URI for app ${app_name}" |
            log-output \
                --level error \
                --header "Critical error" ||
            exit 1
    fi

    # add logout uri if provided
    if [[ -n "${logout_uri}" &&
        ! "${logout_uri}" == null &&
        ! "${logout_uri}" == "null" ]]; then

        echo "Adding logout url: '${logout_uri}' for app with id '${app_id}'." |
            log-output \
                --level info

        add-signout-url "${obj_id}" "${logout_uri}"
    fi

    # set sign-in audience
    if [[ "${sign_in_audience}" == "single" ]]; then
        az ad app update \
            --id "${app_id}" \
            --set signInAudience="AzureADMyOrg" \
            --only-show-errors |
            log-output \
                --level info ||
            echo "Failed to add single sign-in audience to app ${app_name}" |
            log-output \
                --level error \
                --header "Critical error" ||
            exit 1
    fi

    # set access token accepted version to one if requested
    if [[ "${set_access_token_accepted_version_to_one}" == "true" ]]; then
        set-access-token-accepted-version-to-one "${app_id}"
    fi

    # set allow public client flows if requested
    if [[ "${is_allow_public_client_flows}" == "true" ]]; then
        az ad app update \
            --id "${app_id}" \
            --set isFallbackPublicClient=true \
            --only-show-errors |
            log-output \
                --level info ||
            echo "Failed to set allow public client flows for app ${app_name}" |
            log-output \
                --level error \
                --header "Critical error" ||
            exit 1
    fi

    echo "App registration ${app_name} created successfully." |
        log-output \
            --level success
}

function get-app-registration-id() {
    local app_name="$1"
    get-app-id "${app_name}"
}

function get-app-registration-object-id() {
    local app_name="$1"
    get-app-object-id "${app_name}"
}

function put-app-registration-value() {
    local app_name="$1"
    local key="$2"
    local value="$3"
    put-value ".appRegistrations[] | select(.name==\"${app_name}\").${key}" "${value}"
}

function get-app-registration-value() {
    local app_name="$1"
    local key="$2"
    get-value ".appRegistrations[] | select(.name==\"${app_name}\").${key}"
}

function add-certificate-to-app-registration() {
    local app_name="$1"
    local certificate_path="$2"
    
    local app_id
    app_id="$(get-app-registration-id "${app_name}")"
    
    echo "Adding certificate to app registration: ${app_name}" |
        log-output \
            --level info

    az ad app credential reset \
        --id "${app_id}" \
        --cert "@${certificate_path}" \
        --only-show-errors |
        log-output \
            --level info ||
        echo "Failed to add certificate to app registration ${app_name}" |
        log-output \
            --level error \
            --header "Critical error" ||
        exit 1
}

function add-secret-to-app-registration() {
    local app_name="$1"
    
    local app_id
    app_id="$(get-app-registration-id "${app_name}")"
    
    echo "Adding secret to app registration: ${app_name}" |
        log-output \
            --level info

    local secret_json
    secret_json="$(az ad app credential reset \
        --id "${app_id}" \
        --only-show-errors \
        --query "{password:password}" ||
        echo "Failed to create secret for app registration ${app_name}" |
        log-output \
            --level error \
            --header "Critical error" ||
        exit 1)"

    local secret_value
    secret_value="$(jq --raw-output '.password' <<<"${secret_json}")"
    
    put-app-registration-value "${app_name}" "secretText" "${secret_value}"
    
    echo "Secret added to app registration: ${app_name}" |
        log-output \
            --level success
}

function add-scopes-to-app-registration() {
    local app_name="$1"
    local app_config="$2"
    
    local obj_id
    obj_id="$(get-app-registration-object-id "${app_name}")"
    
    local scopes
    scopes="$(jq '.scopes' <<<"${app_config}")"
    
    if [[ -n "${scopes}" && "${scopes}" != "null" ]]; then
        add-permission-scopes "${obj_id}" "${app_name}" "${scopes}"
    fi
}

function add-permissions-to-app-registration() {
    local app_name="$1"
    local app_config="$2"
    
    local app_id
    app_id="$(get-app-registration-id "${app_name}")"
    
    local permissions
    permissions="$(jq '.permissions' <<<"${app_config}")"
    
    if [[ -n "${permissions}" && "${permissions}" != "null" ]]; then
        add-required-resource-access "${permissions}" "${app_id}"
    fi
}

function app-exist() {
    local app_id="$1"

    if [[ -z "${app_id}" ||
        "${app_id}" == null ||
        "${app_id}" == "null" ]]; then

        false
        return
    fi

    app_exist="$(
        az ad app show \
            --id "${app_id}" \
            --query "appId=='${app_id}'" 2>/dev/null ||
            false
        return
    )"

    if [ "${app_exist}" == "true" ]; then
        true
        return
    else
        false
        return
    fi
}

function get-scope-permission-id() {
    local resource_id="$1"
    local permission_name="$2"

    permission_id="$(az ad sp show \
        --id "${resource_id}" \
        --query "oauth2PermissionScopes[?value=='${permission_name}'].id" \
        --output tsv ||
        echo "Failed to get permission id for ${permission_name}" ||
        exit 1)"

    echo "${permission_id}"
}

function get-app-role-permission-id() {
    local resource_id="$1"
    local permission_name="$2"

    permission_id="$(az ad sp show \
        --id "${resource_id}" \
        --query "appRoles[?value=='${permission_name}'].id" \
        --output tsv ||
        echo "Failed to get permission id for ${permission_name}" ||
        exit 1)"

    echo "${permission_id}"
}

function add-permission-scopes() {
    local obj_id="$1"
    local app_name="$2"
    local scopes="$3"

    # create persmission scopes json
    oauth_permissions_json=$(init-oauth-permissions)

    # read each item in the JSON array to an item in the Bash array
    readarray -t scope_array < <(jq --compact-output '.[]' <<<"${scopes}")

    # iterate through the Bash array
    for scope in "${scope_array[@]}"; do
        scope_name=$(jq --raw-output '.name' <<<"${scope}")
        scope_description=$(jq --raw-output '.description' <<<"${scope}")

        # create permission json
        permission_json=$(create-oauth-permission \
            "${app_name}" \
            "${scope_name}" \
            "${scope_description}")

        # add permission json to oauth permissions json
        oauth_permissions_json=$(jq --compact-output \
            --argjson permission_scope "${permission_json}" \
            '.api.oauth2PermissionScopes += [$permission_scope]' \
            <<<"${oauth_permissions_json}")
    done

    # Microsoft Graph API for applications
    graph_url="https://graph.microsoft.com/v1.0/applications/${obj_id}"

    # add permissions to app registration using Microsoft Graph API
    az rest \
        --method "PATCH" \
        --uri "${graph_url}" \
        --body "${oauth_permissions_json}" \
        --only-show-errors |
        log-output ||
        echo "Failed to add permissions: $?" |
        log-output \
            --level error \
            --header "Critical error"
    return
}

function add-required-resource-access() {
    local permissions="$1"
    local app_id="$2"

    local endpoint
    local scope_name

    declare -i permission_scopes_length
    declare -i permission_app_roles_length

    required_resource_access_json_request=[]

    readarray -t permissions_array < <(jq --compact-output '.[]' <<<"${permissions}")

    # iterate through the items in the array
    for permission in "${permissions_array[@]}"; do

        grant_admin_consent=$(jq --compact-output '.grantAdminConsent' <<<"${permission}")

        # get the permission scopes
        permission_scopes=$(jq --raw-output '.scopes' <<<"${permission}")
        permission_scopes_length=$(jq --raw-output '.scopes | length' <<<"${permission}")

        permission_app_roles=$(jq --raw-output '.appRoles' <<<"${permission}")
        permission_app_roles_length=$(jq --raw-output '.appRoles | length' <<<"${permission}")

        # get the permission endpoint
        endpoint=$(jq --raw-output '.endpoint' <<<"${permission}")

        if [[ -n "${endpoint}" &&
            ! "${endpoint}" == "null" ]]; then
            resource_id=$(get-app-id "${endpoint}")
            is_custom_resource=true
            
            # Check if we got a valid resource_id
            if [[ -z "${resource_id}" || "${resource_id}" == "null" ]]; then
                echo "Warning: Could not find app with name '${endpoint}'. Skipping this permission." |
                    log-output \
                        --level warning
                continue
            fi
        else
            resource_id=$(jq --raw-output '.resourceId' <<<"${permission}")
            is_custom_resource=false
        fi

        if [[ -n "${resource_id}" &&
            ! "${resource_id}" == "null" ]]; then

            echo "Resource id: '${resource_id}'" |
                log-output \
                    --level info
        else
            echo "Warning: No valid resource ID found. Skipping this permission." |
                log-output \
                    --level warning
            continue
        fi

        echo "Is custom resource: '${is_custom_resource}'" |
            log-output \
                --level info

        # initialize required resource access json request
        required_resource_access_array_json="$(init-required-resource-access "${resource_id}")"

        # adding permission scopes to required resource access json request
        if [[ -n $permission_scopes && ! $permission_scopes == null ]] &&
            [[ (($permission_scopes_length -gt 0)) ]]; then

            required_resource_access_array_json="$(add-permission-scopes-to-required-access \
                "${permission_scopes}" \
                "${endpoint}" \
                "${resource_id}" \
                "${required_resource_access_array_json}" \
                "${is_custom_resource}")"
        fi

        # adding permission app roles to required resource access json request
        if [[ -n $permission_app_roles && ! $permission_app_roles == null ]] &&
            [[ (($permission_app_roles_length -gt 0)) ]]; then

            required_resource_access_array_json="$(add-permission-app-roles-to-required-access \
                "${permission_app_roles}" \
                "${endpoint}" \
                "${resource_id}" \
                "${required_resource_access_array_json}" \
                "${is_custom_resource}")"
        fi

        required_resource_access_json_request="$(jq --raw-output \
            --argjson required_resource_access "${required_resource_access_array_json}" \
            '. += [$required_resource_access]' \
            <<<"${required_resource_access_json_request}")"

        # Grant admin consent if requested for this permission
        if [[ "${grant_admin_consent}" == "true" ]]; then
            echo "Waiting 60 seconds to allow the permissions to propagate before granting admin consent." |
                log-output --level info

            sleep 60

            echo "Granting admin consent" | log-output --level info
            az ad app permission admin-consent \
                --id "${app_id}" \
                --only-show-errors |
                log-output ||
                echo "Failed to grant admin consent: $?" |
                log-output \
                    --level error \
                    --header "Critical error"
        fi
    done

    echo "Required Resource Accesses request: '${required_resource_access_json_request}'" |
        log-output \
            --level info

    az ad app update \
        --id "${app_id}" \
        --required-resource-accesses "${required_resource_access_json_request}" \
        --only-show-errors |
        log-output ||
        echo "Failed to add required resource access: $?" |
        log-output \
            --level error \
            --header "Critical error"

    return
}

function add-permission-scopes-to-required-access() {
    local scopes="${1}"
    local endpoint="${2}"
    local resource_id="${3}"
    local required_resource_access_array_json="${4}"
    local is_custom_resource="${5}"

    echo "Permission scopes: '${scopes}'" |
        log-output \
            --level info

    readarray -t scope_array < <(jq --compact-output '.[]' <<<"${scopes}")

    if [[ ${#scope_array[@]} == 0 ]]; then
        echo "No scopes to add." |
            log-output \
                --level info

        echo "${required_resource_access_array_json}"
        return
    fi

    # iterate through the scopes in the permission
    for scope_name in "${scope_array[@]}"; do

        # removing double quotes from scope name
        scope_name=$(jq --raw-output '.' <<<"${scope_name}")

        if [[ $scope_name == null || -z $scope_name ]]; then
            continue
        fi

        if [[ "${is_custom_resource}" == "true" ]]; then
            scope_guid=$(get-scope-guid "${endpoint}" "${scope_name}")
        else
            scope_guid=$(get-scope-permission-id "${resource_id}" "${scope_name}")
        fi

        echo "Adding scope name: '${scope_name}', Scope guid: '${scope_guid}'" |
            log-output \
                --level info

        required_resource_access_json="$(create-required-resource-access "${scope_guid}" "Scope")"

        required_resource_access_array_json="$(jq --raw-output \
            --argjson required_resource_access "${required_resource_access_json}" \
            '.resourceAccess += [$required_resource_access]' \
            <<<"${required_resource_access_array_json}")"
    done

    echo "${required_resource_access_array_json}"
    return
}

function add-permission-app-roles-to-required-access() {
    local app_roles="${1}"
    local endpoint="${2}"
    local resource_id="${3}"
    local required_resource_access_array_json="${4}"
    local is_custom_resource="${5}"

    echo "Permission app roles: ${app_roles}" |
        log-output \
            --level info

    readarray -t app_role_array < <(jq --compact-output '.[]' <<<"${app_roles}")

    if [[ ${#app_role_array[@]} == 0 ]]; then
        echo "No app roles to add." |
            log-output \
                --level info

        echo "${required_resource_access_array_json}"
        return
    fi

    # iterate through the scopes in the permission
    for app_role_name in "${app_role_array[@]}"; do

        # removing double quotes from app role name
        app_role_name=$(jq --raw-output '.' <<<"${app_role_name}")

        if [[ $app_role_name == null || -z $app_role_name ]]; then
            continue
        fi

        if [[ "${is_custom_resource}" == "true" ]]; then
            app_role_guid=$(get-app-role-guid "${endpoint}" "${app_role_name}")
        else
            app_role_guid=$(get-app-role-permission-id "${resource_id}" "${app_role_name}")
        fi

        echo "App role name: '${app_role_name}', App role guid: '${app_role_guid}'" |
            log-output \
                --level info

        required_resource_access_json="$(create-required-resource-access "${app_role_guid}" "Role")"

        required_resource_access_array_json="$(jq --raw-output \
            --argjson required_resource_access "${required_resource_access_json}" \
            '.resourceAccess += [$required_resource_access]' \
            <<<"${required_resource_access_array_json}")"

    done

    echo "${required_resource_access_array_json}"
    return
}

function create-required-resource-access() {
    local scope_guid="$1"
    local permission_type="$2"

    # create empty oauth permissions json
    required_resource_access_json="$(
        cat <<-END
{
    "id": "${scope_guid}",
    "type": "${permission_type}"
}
END
    ) "
    echo "${required_resource_access_json}"
    return
}

function create-oauth-permission() {
    local app_name="$1"
    local scope_name="$2"
    local scope_description="$3"

    # get scope guid from deployment state if exists
    scope_guid=$(get-scope-guid "${app_name}" "${scope_name}")

    # if scope guid does not exist, create a new guid and add it
    if [[ -z "${scope_guid}" || "${scope_guid}" == null ]]; then

        scope_guid=$(uuidgen)

        echo "Created new scope guid for scope: '${scope_name}' : '${scope_guid}'" |
            log-output \
                --level info

        put-scope-guid "${app_name}" "${scope_name}" "${scope_guid}"
    fi

    # create permission json
    permission_json="$(
        cat <<-END
{
    "adminConsentDescription": "${scope_description}",
    "adminConsentDisplayName": "${scope_description}",
    "id": "${scope_guid}",
    "isEnabled": true,
    "type": "User",
    "userConsentDescription": "${scope_description}",
    "userConsentDisplayName": "${scope_description}",
    "value": "${scope_name}"
} 
END
    )"

    echo "${permission_json}"
    return
}

function init-oauth-permissions() {

    oauth_permissions_json="$(
        cat <<-END
{   "api": {
        "oauth2PermissionScopes": [
        ] 
    }
}
END
    )"
    echo "${oauth_permissions_json}"
    return
}

function init-required-resource-access() {
    local resource_id="$1"

    required_resource_access_json="$(
        cat <<-END
{
    "resourceAppId": "${resource_id}",
    "resourceAccess": [
    ]
}
END
    ) "
    echo "${required_resource_access_json}"
    return
}

function set-access-token-accepted-version-to-one() {
    local obj_id="$1"

    body=$("create-access-token-accepted-version-to-one-body")
    # Microsoft Graph API for applications
    graph_url="https://graph.microsoft.com/v1.0/applications/${obj_id}"

    # add permissions to app registration using Microsoft Graph API
    az rest \
        --method "PATCH" \
        --uri "${graph_url}" \
        --headers "Content-Type=application/json" \
        --body "${body}" \
        --only-show-errors |
        log-output ||
        echo "Failed to set access token accepted version to 'null'" |
        log-output \
            --level error \
            --header "Critical error"
    return
}

function add-signout-url() {
    local obj_id="$1"
    local signout_url="$2"

    body=$(create-signout-body "${signout_url}")
    # Microsoft Graph API for applications
    graph_url="https://graph.microsoft.com/v1.0/applications/${obj_id}"

    # add permissions to app registration using Microsoft Graph API
    az rest \
        --method "PATCH" \
        --uri "${graph_url}" \
        --headers "Content-Type=application/json" \
        --body "${body}" \
        --only-show-errors |
        log-output ||
        echo "Failed to add permissions: $?" |
        log-output \
            --level error \
            --header "Critical error"
    return
}

function create-signout-body() {
    local signout_url="$1"

    signout_body="$(
        cat <<-END
{
    "web": {
        "logoutUrl": "${signout_url}"
    }
}
END
    )"
    echo "${signout_body}"
    return
}

function create-access-token-accepted-version-to-one-body() {

    access_token_accepted_version_body="$(
        cat <<-END
{
    "api": {
        "requestedAccessTokenVersion": 1
    }
}
END
    )"
    echo "${access_token_accepted_version_body}"
    return
}
