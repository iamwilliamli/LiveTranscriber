# TestFlight release from GitHub Actions

The `Upload iOS to TestFlight` workflow archives the iOS app with automatic
signing and uploads it to App Store Connect. It is intentionally available only
through manual dispatch and uses the protected `app-store-production`
environment.

## One-time Apple setup

1. In App Store Connect, create the LiveTranscriber app with bundle identifier
   `com.iamwilliamli.LiveTranscriber`.
2. In Certificates, Identifiers & Profiles, confirm that the following
   identifiers and capabilities exist for team `F8M4T754W4`:
   - `com.iamwilliamli.LiveTranscriber`
   - `com.iamwilliamli.LiveTranscriber.Widget`
   - `com.iamwilliamli.LiveTranscriber.BroadcastUpload`
   - App Group `group.com.iamwilliamli.LiveTranscriber`
   - iCloud container `iCloud.com.iamwilliamli.LiveTranscriber`
   `LiveTranscriberStructuredFoundationModels` is an embedded framework, not an
   app extension, so it does not need its own provisioning profile.
3. Deploy the production CloudKit schema before releasing an App Store build.
4. In App Store Connect, open **Users and Access → Integrations**, request API
   access if necessary, and create a **Team API Key**. Automatic provisioning
   cannot use an Individual API Key. Use the **Admin** access level for this
   dedicated CI key because the first run may need to create distribution
   signing resources as well as upload the build.
5. Download the `.p8` private key. Apple only offers the download once.

## One-time GitHub setup

Create an environment named `app-store-production` under
**Repository Settings → Environments**. Add these environment secrets:

- `ASC_KEY_ID`: the API key ID
- `ASC_ISSUER_ID`: the App Store Connect issuer ID
- `ASC_PRIVATE_KEY_BASE64`: the `.p8` file encoded as one base64 line

For a production repository, add a required reviewer to the environment so that
every upload needs explicit approval.

To encode the key on macOS without copying its plaintext into the repository:

```sh
/usr/bin/base64 -i /absolute/path/to/AuthKey_KEYID.p8 | tr -d '\n'
```

Paste the resulting single line into `ASC_PRIVATE_KEY_BASE64`.

## Upload a build

Open **Actions → Upload iOS to TestFlight → Run workflow**. Normally leave the
build number empty; the workflow uses `1000 + GitHub workflow run number`.
Specify a larger positive integer only when App Store Connect already contains
that generated build number.

The upload completes before App Store Connect finishes processing. Processing
can take several minutes, after which the build appears under TestFlight.
