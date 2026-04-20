{
  "realm": "${KEYCLOAK_BOOTSTRAP_REALM_NAME}",
  "enabled": true,
  "displayName": "${KEYCLOAK_BOOTSTRAP_REALM_NAME}",
  "sslRequired": "external",
  "registrationAllowed": false,
  "registrationEmailAsUsername": false,
  "rememberMe": false,
  "verifyEmail": false,
  "loginWithEmailAllowed": true,
  "duplicateEmailsAllowed": false,
  "resetPasswordAllowed": true,
  "editUsernameAllowed": false,
  "bruteForceProtected": false,
  "groups": [
    {
      "name": "${KEYCLOAK_BOOTSTRAP_GROUP_NAME}"
    }
  ],
  "clients": [
    {
      "clientId": "${KEYCLOAK_BOOTSTRAP_CLIENT_ID}",
      "name": "${KEYCLOAK_BOOTSTRAP_CLIENT_ID}",
      "enabled": true,
      "protocol": "openid-connect",
      "publicClient": false,
      "secret": "${KEYCLOAK_BOOTSTRAP_CLIENT_SECRET}",
      "standardFlowEnabled": true,
      "implicitFlowEnabled": false,
      "directAccessGrantsEnabled": false,
      "serviceAccountsEnabled": false,
      "frontchannelLogout": true,
      "redirectUris": [
        ${KEYCLOAK_BOOTSTRAP_CLIENT_REDIRECT_URIS_JSON}
      ],
      "webOrigins": [
        "+"
      ],
      "protocolMappers": [
        {
          "name": "groups",
          "protocol": "openid-connect",
          "protocolMapper": "oidc-group-membership-mapper",
          "consentRequired": false,
          "config": {
            "full.path": "false",
            "id.token.claim": "true",
            "access.token.claim": "true",
            "userinfo.token.claim": "true",
            "claim.name": "groups"
          }
        }
      ],
      "defaultClientScopes": [
        "web-origins",
        "profile",
        "email",
        "roles"
      ],
      "optionalClientScopes": [
        "address",
        "phone",
        "offline_access",
        "microprofile-jwt"
      ],
      "attributes": {
        "pkce.code.challenge.method": "S256",
        "backchannel.logout.session.required": "true",
        "backchannel.logout.revoke.offline.tokens": "false"
      }
    }
  ]${KEYCLOAK_BOOTSTRAP_USERS_BLOCK}
}
