# StockedMac App Store compliance

Sources: see `/Users/key/Documents/StudioCompliance/APP_STORE_COMPLIANCE_TEMPLATE.md` for Apple references and the current Studio checklist.

- Platforms: macOS
- Privacy manifest: StockedMac/PrivacyInfo.xcprivacy
- Privacy Policy URL: use the current Sowens Studios privacy policy URL before App Store submission.
- User Privacy Choices URL: optional unless this app has a live account/data-deletion page.
- Tracking: No, unless a future build adds cross-app/site tracking. Re-review before upload.
- Encryption/export compliance: Info.plist contains ITSAppUsesNonExemptEncryption.
- QA access code: `6352`
- QA suite/evidence: Tests, scripts, snapshots present; no QA code 6352 marker in audit

## App Store Connect answers to confirm per build

- Data collection categories match the shipped features and any enabled server/API providers.
- Diagnostics/logs are declared if uploaded off-device.
- User content, photos, location, financial, health, contact, account, or purchase data are declared only if the current build actually collects them.
- Privacy manifest and App Store Connect privacy nutrition answers agree.
- Export compliance answer still matches current encryption use.

## Current limitation

This file is a compliance working record. Final App Store Connect answers must be checked against the exact archived build before submission.
