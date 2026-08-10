> **Reference material (RFC-0024).** Slide notes from the KubeCon EU 2025 talk
> *"Securing the Gateway: A Deep Dive into Envoy Gateway's Advanced Security Policy"*
> (Robin Zhao, Tetrate — Envoy Gateway maintainer). Kept verbatim as imported by the
> owner; notable for this platform: the SecurityPolicy feature census and the
> **Backend + BackendTLSPolicy pattern for an in-cluster Keycloak with a self-signed
> certificate** — the exact RFC-0022 integration shape.

Securing the Gateway

A Deep Dive into Envoy Gateway's
## Advanced Security Policy
## Robin Zhao, Tetrate

## Envoy Gateway Maintainer
## Envoy Contributor

## Background: Envoy Gateway
●Envoy Gateway is an open source project for managing Envoy Proxy as a standalone or
Kubernetes-based application gateway.
●Kubernetes Gateway API resources are used to automatically provision and configure the
managed Envoy Proxies.

SecurityPolicy - Secure your Gateway
Security Policy is a Gateway API extension to provide advanced security features for the ingress
traffic.
SecurityPolicy
## Configure
## Access Control
## Enforce
Note: This diagram represents a logical structure rather than an actual
deployment. There is no standalone ‘Access Control’ component in the traffic path;
it is implemented as part of the Envoy using HTTP filters.
## Watch

## Title
SecurityPolicy
Secure Your Gateway with Envoy Gateway’s Security Policy
 CORS (Cross-Origin Resource Sharing)
- Restrict or allow access based on request origin to prevent unauthorized cross-site requests.
##  Authentication - Verify Who’s Accessing
• HTTP Basic Auth – Simple username/password protection.
• JWT (JSON Web Token) – Secure, token-based authentication.
• API Key Authentication – Control access with API keys.
• OIDC (OpenID Connect) – Federated authentication with Google, AWS, Azure AD, Auth0, Keycloak, Okta,
and more.
##  Authorization - Control What Users Can Do
• Principal – Identify users based on IP, JWT claims, Basic Auth credentials, HTTP header and method, etc.
• Action – Allow/Deny access to specific HTTP routes based on rules.
 Ext Auth – Seamlessly integrate with custom authorization systems for customized security requirements.


## Targets
●Gateway: SecurityPolicy applies on all xRoute on the targeted Gateway
●xRoute:  SecurityPolicy applies on the specified xRoute only

How SecurityPolicy Works

SecurityPolicy Example
## CORS
Basic AuthAPI Key Auth

## Configure
## Configure
## Application
## Configure
ID token

SecurityPolicy
## Watch
## Administrator
## End User
## Authorization
code

## Data Plane:
1.The user sends a request to the Envoy without an ID Token.
2.The user is redirected to the Cognito login page for authentication.
3.After successful authentication, the user is redirected back to the
Envoy with an Authorization Code.
4.Envoy exchanges the Authorization Code for an Access Token
and ID Token.
5.The user’s request is then proxied to the application.
## 1
## 2
## 3
## 4
## 5
## Control Plane:
1.The admin configures OIDC authentication using a
SecurityPolicy.
2.Envoy Gateway translates the SecurityPolicy into
Envoy configuration and applies it to the Envoy Proxy.
Demo: OIDC Auth with Amazon Cognito

## 1
## 2

Demo: JWT Claim Authorization
●The ID Token is a JWT token that contains claims about the authenticated user.
●These claims can be used to enforce fine-grained access control at the HTTPRoute level.

(Note: This applies not only to OIDC, but to any JWT token, and it also supports authorization on JWT scopes.

SecurityPolicy
Demo: Work with Self-Signed Certificate
## 2
## Backend
## Configure
## Configure
## Application
## Configure
Access &ID token

## Watch
## Backend
## Administrator
## Authorization
code

TLS with Self-signed
certificate

BackendTLSPolicy
Keycloak is deployed as an IDP using a self-signed certificate.

## TLS
## Secret
To connect to it:
1.Create a Backend resource pointing to Keycloak.
2.Reference that Backend as the OIDC provider in the
SecurityPolicy.
3.Use a BackendTLSPolicy to configure the required CA
certificate for establishing a TLS connection with Keycloak.
## End User
Note: In this demo, a Backend resource is not a must because Keycloak is
deployed inside the cluster. However, if Keycloak is deployed outside the
cluster, you will need to define a Backend to connect to it properly.


OIDC Provider with Self-Signed Certificate
●Use the Backend API to reference to a Keycloak deployed within the cluster.
●Use the BackendTLSPolicy API to configure CA for TLS.

## Title
## ●CORS
●Basic Authn
●API Key Authn
●JWT Authn
●OIDC Authn
●Client IP Authz
●JWT Claim/Scope Authz
●HTTP Header/Method Authz
Thank you
attend Docker’s Envoy Gateway Journey
15:00 - 15:30 Level 3 | ICC Capital Suite 14-16

Join us in the envoy #gateway-users slack channel

