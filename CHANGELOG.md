## [1.0.4](https://github.com/Liago/mytube/compare/v1.0.3...v1.0.4) (2026-02-05)

### Bug Fixes

* use stream chunks to read R2 cookie response body ([77db169](https://github.com/Liago/mytube/commit/77db169bef1e6cd2392d7767934c6190f99420ba))

## [1.0.3](https://github.com/Liago/mytube/compare/v1.0.2...v1.0.3) (2026-02-05)

### Bug Fixes

* use format fallback chain and remove player_client=web ([6460d50](https://github.com/Liago/mytube/commit/6460d502e613720e13ad531791f681f135173ceb))

## [1.0.2](https://github.com/Liago/mytube/compare/v1.0.1...v1.0.2) (2026-02-04)

### Bug Fixes

* load YouTube cookies from R2 bucket instead of env var ([6cee942](https://github.com/Liago/mytube/commit/6cee942119cfa57cd80b90d78bb39804e376fa69))

## [1.0.1](https://github.com/Liago/mytube/compare/v1.0.0...v1.0.1) (2026-02-04)

### Bug Fixes

* add YOUTUBE_COOKIES env var support and improve YouTube bot evasion ([2c0d622](https://github.com/Liago/mytube/commit/2c0d622c885dfcdd30c8efabb01becc42da0974e))

## 1.0.0 (2026-02-04)

### Features

* adds background audio playback and background refresh ([cc75d83](https://github.com/Liago/mytube/commit/cc75d8380d1274283bcba6f415c1872f99fa6c4c))
* **backend:** Add Netlify function to check R2 cache status ([876d639](https://github.com/Liago/mytube/commit/876d63915217b1f89754469c261ad375cc9b3a9b))
* **backend:** Implement weekly R2 cache cleanup ([dc82031](https://github.com/Liago/mytube/commit/dc82031cf2c51c31f419b7647c440cfd86c589a9))
* **backend:** Refactor audio upload with v2 file keys and cookie support ([c09bca0](https://github.com/Liago/mytube/commit/c09bca0463ecf50729219a412be8b8a8e42eb31e))
* configures semantic release ([04b014d](https://github.com/Liago/mytube/commit/04b014d80f8fa75e9cd906473103abe21610f22e))
* Introduce CacheStatusService for tracking R2 cache ([b96eaf9](https://github.com/Liago/mytube/commit/b96eaf906f6f52b1ecd80e59fa7a04b5ce89dd66))
* opens player modal on some video tap ([2a054a2](https://github.com/Liago/mytube/commit/2a054a2f4ab030eb11dabe2229424e8741578ac2))
* **ui:** Display R2 cache status in video cards and channel views ([c157e9c](https://github.com/Liago/mytube/commit/c157e9c2435e383767f6f6c298b629bb28fa1b3b))

### Bug Fixes

* audio player ([bb521b0](https://github.com/Liago/mytube/commit/bb521b04685458fb6893d61048a0c0cf94583086))
* avoid publishing to npm ([efd1af5](https://github.com/Liago/mytube/commit/efd1af56a57cad309ce38a2a575af628112cdad7))
* correct optional binding for duration.seconds ([b512ebc](https://github.com/Liago/mytube/commit/b512ebc2adc7ac2d5ea7a678adf514e43772bc6f))
* expand stream extraction with more Piped instances + Invidious fallback ([bca2686](https://github.com/Liago/mytube/commit/bca268656ba82f2eab6c9136f26a57a969cd0300))
* fixes audio playback using Netlify backend ([19bccf1](https://github.com/Liago/mytube/commit/19bccf173f1475d93f740e7619c3fed93593c2a3))
* implement AVAssetResourceLoaderDelegate for YouTube streams ([592b21c](https://github.com/Liago/mytube/commit/592b21cfd7845ef53093eb5bb86f407197ae869a))
* implement streaming download with URLSessionDataDelegate ([6139372](https://github.com/Liago/mytube/commit/6139372e5006b4abc5ffe34e39f16c0e30e3d646))
* protects batch check from cancellation during execution ([79e7904](https://github.com/Liago/mytube/commit/79e79040ff806f87a81ce64a5a5e547e68742a45))
* resolve background audio playback and lock screen controls ([31942de](https://github.com/Liago/mytube/commit/31942de3805312b1d00060e6e5b2c3a7414d22b0))
* resolve background playback and lock screen control issues ([89ec026](https://github.com/Liago/mytube/commit/89ec02677aadceaa5434fb5bd5805bdccfc55038))
* resolve infinite recursion in UTType extension ([ac4b911](https://github.com/Liago/mytube/commit/ac4b9114a454109af770027761b4c8a9f4d19860))
* restore LocalStreamProxy for reliable YouTube streaming ([f1fdf86](https://github.com/Liago/mytube/commit/f1fdf868d9716c11d6c4ed88d5938b064860d8e6))
* use correct UTType for AAC audio ([a0b5d93](https://github.com/Liago/mytube/commit/a0b5d934660e8655460420283f4aa364d5417729))
* various on player ([9c9903c](https://github.com/Liago/mytube/commit/9c9903ce5c195398bcec061d293f996e039166cf))
