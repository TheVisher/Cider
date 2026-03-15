# Authentication

> Cross-platform auth specification for all three Cider apps. Read this before working on auth, login, sync credentials, or account management.
>
> **Last updated**: 2026-03-15

## Overview

Users create an account with email + password. All three apps authenticate against the same Convex backend. Desktop and iOS use REST endpoints to sign in and receive a sync token. Web uses `@convex-dev/auth` session cookies directly.

```
Desktop (macOS)  ── /api/auth/login ──>  Convex Backend  <── /api/auth/login ──  iOS
                         |                     ^                    |
                    sync token             session cookie       sync token
                    (Keychain)          (@convex-dev/auth)     (Keychain)
                         |                     |                    |
                    /api/sync/*           direct mutations     /api/sync/*
                                              |
                                         Cider Web
```

## Auth Flow (Desktop + iOS)

1. User opens Settings → Account → enters email + password
2. App calls `POST /api/auth/login` (or `/api/auth/signup`)
3. Server verifies credentials (Scrypt password hash via Lucia)
4. Server creates or reuses a device-named sync token
5. App stores token in Keychain, stores email in UserDefaults
6. App sets `syncEnabled = true` and starts sync
7. All sync requests include `Authorization: Bearer <token>`

## Auth Flow (Web)

Web uses `@convex-dev/auth` Password provider with React hooks (`useAuthActions().signIn()`). Session management is handled automatically via Convex session cookies. Web never uses sync tokens — it talks to Convex directly via subscriptions and mutations.

## Endpoints

| Method | Path | Purpose | Auth Required |
|--------|------|---------|---------------|
| POST | `/api/auth/login` | Sign in → returns sync token | No (credentials in body) |
| POST | `/api/auth/signup` | Create account → returns sync token | No (credentials in body) |
| POST | `/api/auth/account` | Get account info (email) | Bearer token |
| POST | `/api/auth/devices` | List connected devices | Bearer token |
| POST | `/api/auth/devices/revoke` | Remove a device | Bearer token |

### Login / Signup Request

```json
{
  "email": "user@example.com",
  "password": "password123",
  "deviceName": "MacBook Pro"
}
```

### Login / Signup Response (200)

```json
{
  "token": "aBcDeFgH-iJkLmNoP-qRsTuVwX-yZaBcDeF",
  "userId": "convex_user_id",
  "email": "user@example.com"
}
```

### Error Response

```json
{
  "error": "Invalid email or password"
}
```

## Device Naming

Each sync token is associated with a device name. When a device logs in:
- If a non-revoked token with the same device name exists, it's reused
- Otherwise, a new token is created

Device names come from:
- **macOS**: `Host.current().localizedName` (e.g., "VishMac")
- **iOS**: `UIDevice.current.name` (e.g., "iPhone")

## Token Storage

| Platform | Token Storage | Email Storage |
|----------|--------------|---------------|
| Desktop | Keychain (`SyncService.saveSyncToken`) | UserDefaults (`CiderAccountEmail`) |
| iOS | Keychain (`KeychainHelper`) | UserDefaults App Group (`cider_account_email`) |
| Web | N/A (session cookies) | N/A (Convex auth) |

## Sign Out

Desktop/iOS:
1. Clear token from Keychain
2. Clear email from UserDefaults
3. Set `syncEnabled = false`
4. Stop sync service
5. Token remains valid on server (can be revoked via Connected Devices)

Web:
1. Call `signOut()` from `@convex-dev/auth`

## Password Hashing

All platforms use the same password hash format (Lucia Scrypt):

```
<salt_hex>:<key_hex>
```

- Salt: 16 random bytes, hex-encoded (32 chars)
- Key: scrypt with `N=16384, r=16, p=1, dkLen=64`
- Salt is passed to scrypt as TEXT STRING (hex chars as UTF-8 bytes)
- Password is NFKC-normalized before hashing

Password verification runs in a `"use node"` Convex action (`nativeAuthNode.ts`) because it needs Node.js `crypto.scryptSync`.

## Backend Files

| File | Purpose |
|------|---------|
| `convex/auth.ts` | `@convex-dev/auth` config (Password provider, session settings) |
| `convex/auth.config.ts` | OIDC provider config |
| `convex/nativeAuth.ts` | DB helpers: findAuthAccount, createTokenForUser, createUserAndToken, listDevices, revokeDevice |
| `convex/nativeAuthNode.ts` | `"use node"` actions: verifyCredentials, createAccount (Scrypt crypto) |
| `convex/http.ts` | HTTP routes: /api/auth/* |
| `convex/syncTokens.ts` | Legacy token CRUD (used by web settings page — to be replaced with Connected Devices) |

## Client Files

| Platform | Auth Service | Settings UI |
|----------|-------------|-------------|
| Desktop | `Services/AuthService.swift` | `Views/Settings/SettingsComponents.swift` (SettingsAccountOverviewView) |
| iOS | `CiderApp/Services/AuthService.swift` | `CiderApp/Views/SettingsView.swift` |
| Web | `@convex-dev/auth` hooks | `src/pages/login-form.tsx`, `src/pages/signup-form.tsx` |

## Connected Devices

The "Connected Devices" view shows all devices with active sync tokens. Users can remove devices (revokes their token — that device will need to sign in again).

- Desktop: `Views/Settings/ConnectedDevicesView.swift`
- Web: To be implemented (can use `syncTokens.list` query or `/api/auth/devices` endpoint)
- iOS: To be implemented

## Security Notes

- Sync tokens are random 32-character strings (4 segments of 8 alphanumeric chars)
- Tokens are stored in Keychain on native clients (not UserDefaults)
- Token lookup uses an indexed query (`by_token`) — O(1) at any scale
- Passwords are never stored on the client
- HTTPS enforced for all auth endpoints (Desktop validates URL scheme before sending credentials)
- Revoking a device immediately invalidates its token — next sync request will fail with 401

## Future Considerations

- OAuth providers (Google, Apple Sign In) — would go through `@convex-dev/auth` on web, need equivalent native flows
- Password reset flow — currently manual ("contact support"), needs self-service email reset
- Email verification — `@convex-dev/auth` supports it, not currently enforced
- JWT migration — could replace sync tokens with JWTs for a more standard approach, but sync tokens work fine at scale (indexed lookup, same pattern as Stripe/GitHub API keys)
