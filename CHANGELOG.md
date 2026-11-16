## [1.2.1](https://github.com/deanjstone/sys-admin/compare/v1.2.0...v1.2.1) (2026-11-11)


### Bug Fixes

* guard fnm install with the one-node check and pin node v24.18.0 ([ac86187](https://github.com/deanjstone/sys-admin/commit/ac8618716acef59dc972900f28af7389a65c0867)), closes [deanjstone/argus-config#1164](https://github.com/deanjstone/argus-config/issues/1164)

# [1.2.0](https://github.com/deanjstone/sys-admin/compare/v1.1.2...v1.2.0) (2026-10-16)


### Features

* add a Syncthing GUI password reset script ([#157](https://github.com/deanjstone/sys-admin/issues/157)) ([b4db081](https://github.com/deanjstone/sys-admin/commit/b4db0817c371f6bff760096d18113a67aaf7ef3a))

## [1.1.2](https://github.com/deanjstone/sys-admin/compare/v1.1.1...v1.1.2) (2026-09-07)


### Bug Fixes

* **config:** apply Dimidium's contrast targets to the Zed and Terminal themes ([#108](https://github.com/deanjstone/sys-admin/issues/108)) ([22d5ef2](https://github.com/deanjstone/sys-admin/commit/22d5ef2b02c5370bcc394dce68e42ab76359b433)), closes [#107](https://github.com/deanjstone/sys-admin/issues/107) [#1A8E46](https://github.com/deanjstone/sys-admin/issues/1A8E46) [#0575D8](https://github.com/deanjstone/sys-admin/issues/0575D8) [#CF494C](https://github.com/deanjstone/sys-admin/issues/CF494C) [#F5F3F1](https://github.com/deanjstone/sys-admin/issues/F5F3F1)

## [1.1.1](https://github.com/deanjstone/sys-admin/compare/v1.1.0...v1.1.1) (2026-09-07)


### Bug Fixes

* **config:** raise Dimidium's contrast so the app slider can stay at 100% ([#107](https://github.com/deanjstone/sys-admin/issues/107)) ([7d38608](https://github.com/deanjstone/sys-admin/commit/7d38608022d3ff74eb653506a39cd51166d00734)), closes [#1a8e46](https://github.com/deanjstone/sys-admin/issues/1a8e46)

# [1.1.0](https://github.com/deanjstone/sys-admin/compare/v1.0.5...v1.1.0) (2026-09-06)


### Features

* **config:** track the Dimidium theme for T3 Code ([#106](https://github.com/deanjstone/sys-admin/issues/106)) ([f8b037e](https://github.com/deanjstone/sys-admin/commit/f8b037e09bae668691f7a7db550ef5a5614d3aec))

## [1.0.5](https://github.com/deanjstone/sys-admin/compare/v1.0.4...v1.0.5) (2026-08-17)


### Bug Fixes

* complete the wsl-root rename — content changes, not just the move ([#96](https://github.com/deanjstone/sys-admin/issues/96)) ([2cd5a6b](https://github.com/deanjstone/sys-admin/commit/2cd5a6b72015f66735f72863202265a65796da87)), closes [#95](https://github.com/deanjstone/sys-admin/issues/95) [#95](https://github.com/deanjstone/sys-admin/issues/95) [#92](https://github.com/deanjstone/sys-admin/issues/92)

## [1.0.4](https://github.com/deanjstone/sys-admin/compare/v1.0.3...v1.0.4) (2026-08-17)


### Bug Fixes

* **bw-sudo:** document the route that actually escalates on WSL2 ([#93](https://github.com/deanjstone/sys-admin/issues/93)) ([5c2e6cb](https://github.com/deanjstone/sys-admin/commit/5c2e6cb91cfb286fc6c6f2e95199764dc2e64c9b)), closes [#92](https://github.com/deanjstone/sys-admin/issues/92) [#90](https://github.com/deanjstone/sys-admin/issues/90)

## [1.0.3](https://github.com/deanjstone/sys-admin/compare/v1.0.2...v1.0.3) (2026-08-12)


### Bug Fixes

* track executable bit on drift-poller.sh ([#72](https://github.com/deanjstone/sys-admin/issues/72)) ([8074319](https://github.com/deanjstone/sys-admin/commit/80743197d150cc4969385a9852dfc71209665309))

## [1.0.2](https://github.com/deanjstone/sys-admin/compare/v1.0.1...v1.0.2) (2026-08-08)


### Bug Fixes

* restic backup script was silently skipping all of ~/repos ([#70](https://github.com/deanjstone/sys-admin/issues/70)) ([b63369f](https://github.com/deanjstone/sys-admin/commit/b63369fb30813c1744e0054a18f0a7336838c321)), closes [sys-admin#69](https://github.com/sys-admin/issues/69)

## [1.0.1](https://github.com/deanjstone/sys-admin/compare/v1.0.0...v1.0.1) (2026-08-07)


### Bug Fixes

* update ~/projects references to ~/repos across scripts, docs, config ([#69](https://github.com/deanjstone/sys-admin/issues/69)) ([90d6a37](https://github.com/deanjstone/sys-admin/commit/90d6a370d63cf92f919d1e533aaa8cfc7e854dc6)), closes [deanjstone/argus-config#135](https://github.com/deanjstone/argus-config/issues/135) [cmdpal-argus#37](https://github.com/cmdpal-argus/issues/37) [ccbot#31](https://github.com/ccbot/issues/31)

# 1.0.0 (2026-08-03)


### Bug Fixes

* repoint install-homelab.sh at argus-config split, gate ccbot deploy ([#11](https://github.com/deanjstone/sys-admin/issues/11)) ([4158683](https://github.com/deanjstone/sys-admin/commit/4158683871b80f21819fcfd49397f107cca3f354)), closes [argus-config#68](https://github.com/argus-config/issues/68)
* resolve ShellCheck Lint workflow failures ([#9](https://github.com/deanjstone/sys-admin/issues/9)) ([996e9eb](https://github.com/deanjstone/sys-admin/commit/996e9ebfdc91dbcf39da233cc626063de6fd14d8))
* restore wezterm.lua, remove pre-split leftovers, fix stale script paths ([#51](https://github.com/deanjstone/sys-admin/issues/51)) ([862eab3](https://github.com/deanjstone/sys-admin/commit/862eab39186f0e61c3047a2a457d744f2fc21a70)), closes [#25](https://github.com/deanjstone/sys-admin/issues/25) [#26](https://github.com/deanjstone/sys-admin/issues/26)
* **skills:** correctness fixes, structural chaining, verbosity pass ([3865b5f](https://github.com/deanjstone/sys-admin/commit/3865b5f908de890fe75a0714ecc17e4778cfaf0a))
* update install-windows.ps1 for argus-config split ([b0700cb](https://github.com/deanjstone/sys-admin/commit/b0700cb23c70bb079633a389e92d0203f6093831))


### Features

* add semantic-release for automated versioning ([#61](https://github.com/deanjstone/sys-admin/issues/61)) ([a5d7686](https://github.com/deanjstone/sys-admin/commit/a5d7686c46600bd0d9cf886d8d7aab9d6c804888))
* make sys-admin the sole owner of the Windows PowerShell profile ([#13](https://github.com/deanjstone/sys-admin/issues/13)) ([6693638](https://github.com/deanjstone/sys-admin/commit/66936380a868e2ec50c559be1155d9d0d6ddb24d))
