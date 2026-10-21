fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## Android

### android validate_key

```sh
[bundle exec] fastlane android validate_key
```

Verify that Google Play service account JSON key exists and is valid

### android build

```sh
[bundle exec] fastlane android build
```

Build Flutter Release Android App Bundle (AAB)

### android internal

```sh
[bundle exec] fastlane android internal
```

Build and upload release to Google Play Internal Testing track

### android alpha

```sh
[bundle exec] fastlane android alpha
```

Build and upload release to Google Play Closed Testing (Alpha) track

### android closed

```sh
[bundle exec] fastlane android closed
```

Alias for alpha track (Closed Testing)

### android beta

```sh
[bundle exec] fastlane android beta
```

Build and upload release to Google Play Open Testing (Beta) track

### android production

```sh
[bundle exec] fastlane android production
```

Build and upload release to Google Play Production track

### android promote_internal_to_production

```sh
[bundle exec] fastlane android promote_internal_to_production
```

Promote an existing release from Internal track to Production

### android status

```sh
[bundle exec] fastlane android status
```

Check current status of releases across all tracks

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
