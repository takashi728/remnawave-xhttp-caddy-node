# Remnawave Node Deployment

This context defines the deployment and configuration concepts used when connecting Remnawave, Xray, public hosts, and client applications.

## Language

**Node profile**:
The server configuration assigned by Remnawave Panel to one or more Remnawave Nodes.
_Avoid_: Client profile, Host profile

**Host override**:
A public connection setting that Remnawave incorporates into generated client subscriptions.
_Avoid_: Node setting, server override

**XMUX**:
XHTTP's own connection-management policy carried inside a Host's XHTTP extra parameters. It is the only multiplexing control used by the recommended XHTTP profile.
_Avoid_: MUX, general MUX

**MUX**:
The separate Xray outbound multiplexing policy exposed by Remnawave Host settings. It is distinct from XMUX and remains unset for the recommended XHTTP profile.
_Avoid_: XMUX, XHTTP XMUX

**Client core**:
The proxy core embedded in or used by a subscriber's client application.
_Avoid_: Node core, server core

**Supported client baseline**:
A client application using Xray-core v26.6.27 or newer and capable of preserving the recommended Host XMUX and XHTTP extra parameters.
_Avoid_: Any Xray-compatible client, legacy client

**Anti-censorship baseline**:
The explicit connection policy recommended by this project for censorship-sensitive deployments. For XHTTP, it includes the established padding and obfuscation preset plus a six-connection XMUX limit rather than relying on version-dependent defaults.
_Avoid_: Xray default, automatic default

**Throughput profile**:
A supported connection profile optimized for direct-transfer performance where censorship resistance is not the primary requirement. XTLS-Vision is maintained in this category as a deprecated option.
_Avoid_: Recommended profile, anti-censorship profile

**Deprecated profile**:
A profile retained for existing deployments and deliberate legacy use, without receiving new features. It remains eligible for critical security and compatibility fixes until removal.
_Avoid_: Recommended profile, deleted profile

**Multihop topology**:
A deployment in which a public entry node forwards accepted traffic through one or more separately managed destination nodes. Destination selection may use routing or balancing and is not assumed to be a fixed node pair.
_Avoid_: Bridge Node, relay combo

**Cover service**:
A credible HTTPS application served to requests that do not match the private XHTTP route. In the recommended topology, Caddy routes these requests to Element Web before they reach Xray.
_Avoid_: Xray fallback, fake page

**Fallback**:
An Xray protocol action that forwards traffic rejected by an inbound to another local service. It belongs only to the deprecated XTLS-Vision profile and is distinct from the recommended XHTTP cover service.
_Avoid_: Cover service, fallback page
