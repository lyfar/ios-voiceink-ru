fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

### wire_sherpa

```sh
[bundle exec] fastlane wire_sherpa
```



### strip_whisper

```sh
[bundle exec] fastlane strip_whisper
```



### register_app_group

```sh
[bundle exec] fastlane register_app_group
```



### register_app_group_v2

```sh
[bundle exec] fastlane register_app_group_v2
```



### probe_capabilities

```sh
[bundle exec] fastlane probe_capabilities
```



### probe_methods

```sh
[bundle exec] fastlane probe_methods
```



### register_app_group_raw

```sh
[bundle exec] fastlane register_app_group_raw
```



### test_appgroup_post

```sh
[bundle exec] fastlane test_appgroup_post
```



### enable_app_groups

```sh
[bundle exec] fastlane enable_app_groups
```



### probe_appgroup_via_capabilities

```sh
[bundle exec] fastlane probe_appgroup_via_capabilities
```



### probe_api_key_role

```sh
[bundle exec] fastlane probe_api_key_role
```



### fix_header_paths

```sh
[bundle exec] fastlane fix_header_paths
```



----


## iOS

### ios ship

```sh
[bundle exec] fastlane ios ship
```

End-to-end: register IDs, profiles, build IPA, push to R2, publish.

### ios register_or_skip

```sh
[bundle exec] fastlane ios register_or_skip
```

Create Bundle IDs in Apple Dev portal if missing.

### ios sync_profiles

```sh
[bundle exec] fastlane ios sync_profiles
```

Sync ad-hoc provisioning profiles via match-style auto sigh.

### ios build_adhoc

```sh
[bundle exec] fastlane ios build_adhoc
```

Build signed ad-hoc IPA

### ios push_to_r2

```sh
[bundle exec] fastlane ios push_to_r2
```

Upload IPA + manifest to Cloudflare R2 (beta.voice.egor.lol).

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
