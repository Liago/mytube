## 1.0.0 (2026-04-02)

### Features

* adaptive bot-check mitigation for peak hours ([df4d8f5](https://github.com/Liago/mytube/commit/df4d8f5c5ce723c406b22ccd710dd3581502847c))
* Add cloud sync mechanism to VideoStatusManager ([79c767f](https://github.com/Liago/mytube/commit/79c767f60aa6cdb4a846895f61b17213b2758f26))
* add individual episode prefetch queue ([7083dab](https://github.com/Liago/mytube/commit/7083dabf77258b7e5c85c2a06b14e14be714643b))
* add log cleanup to scheduled cleanup function (7-day retention) ([9c61230](https://github.com/Liago/mytube/commit/9c612301047925e75e1b3988bf76c2ba368d24dc))
* adds background audio playback and background refresh ([b3d8b8c](https://github.com/Liago/mytube/commit/b3d8b8cac85c51e56ec543060ffc8e9cd36a9801))
* adds background video prefetching and preferences syncing ([d1800a8](https://github.com/Liago/mytube/commit/d1800a8b5c52474c7c6bc2b521dcb76a1605ee82))
* adds Google session status card ([ad7f49b](https://github.com/Liago/mytube/commit/ad7f49ba95cfe416c1028b246c928264270c92f2))
* align player strategies and improve cookie formatting ([5601bc1](https://github.com/Liago/mytube/commit/5601bc1f30628c256574aa9e0e4675c885fa7952))
* **backend:** Add Netlify function for cookie status API ([f1fea0e](https://github.com/Liago/mytube/commit/f1fea0ee00b61c8b87e4b58335e541c538cebf33))
* **backend:** Add Netlify function to check R2 cache status ([1eb651c](https://github.com/Liago/mytube/commit/1eb651c0769a5d8f2dc817a965b55bd2c301d554))
* **backend:** Implement weekly R2 cache cleanup ([c9ab437](https://github.com/Liago/mytube/commit/c9ab4373417999673b7a0c19cf7bafc991c63f5e))
* **backend:** Refactor audio upload with v2 file keys and cookie support ([c5ab754](https://github.com/Liago/mytube/commit/c5ab7547b3c58ffff6fe9c0d48a45740325f3292))
* configures semantic release ([0324822](https://github.com/Liago/mytube/commit/032482286b96a5eb4e7d77030ac303978ec35622))
* displays user profile information ([73946d3](https://github.com/Liago/mytube/commit/73946d34efebc65caa5d47f365c66379cdee7611))
* enhances audio extraction strategy ([6aeef4d](https://github.com/Liago/mytube/commit/6aeef4dc80518f01bafb0c5a373609d252720e25))
* enhances video download and playback resilience ([28b1117](https://github.com/Liago/mytube/commit/28b1117bbc328ea71daaebfb6dd483c8558acf9e))
* implement cached episodes playlist UI and backend logic ([7f2e062](https://github.com/Liago/mytube/commit/7f2e062d66950977af5e4e3feec1a7511b5e6678))
* implement centralized R2 logger, fix proxy url parsing, replace iOS Playlists tab with Logs ([0e2c83d](https://github.com/Liago/mytube/commit/0e2c83d9534c62d026e2aa88cb485252211e87f5))
* implement channel navigation from home feed cards ([40be14d](https://github.com/Liago/mytube/commit/40be14d7078817e8e1a1605d8e0d400db260d01f))
* Implement Netlify function for video history cloud sync ([a162d34](https://github.com/Liago/mytube/commit/a162d34ecaef61abaa6928233c94d925eaa955e2))
* improves audio download reliability ([20e0110](https://github.com/Liago/mytube/commit/20e0110678ca4cde6d2f78c6ba6f71e67dc80e18))
* improves proxy handling and retry logic. ([729ce1d](https://github.com/Liago/mytube/commit/729ce1d884050b3ba253731a74187feb62462434))
* improves YouTube extraction and adds proxy support ([e18b6f3](https://github.com/Liago/mytube/commit/e18b6f373d9bbaf8d1a8d51a79b07cf7d469f6b6))
* in-app notification system for prefetched videos ([28137d6](https://github.com/Liago/mytube/commit/28137d62dd5de82f3af1022bc6461169612324c4))
* inject R2 unified logger into cleanup scheduled function ([d381617](https://github.com/Liago/mytube/commit/d3816170bbcb0c7a0136d3b87d6419f5b9f3f9a0))
* Introduce CacheStatusService for tracking R2 cache ([045c308](https://github.com/Liago/mytube/commit/045c3088273a3c109eb2b6869dc1aa2fd34aedca))
* introduces splash screen during authentication ([57ec5ee](https://github.com/Liago/mytube/commit/57ec5ee0cfc1197bfbd22538c6714d5ea896ea1c))
* **ios:** Add ProfileView with cookie status and tab integration ([4f34026](https://github.com/Liago/mytube/commit/4f340263cfd420200107c1490beabb325007ff03))
* **ios:** Implement CookieStatusService and expiration notifications ([470d47c](https://github.com/Liago/mytube/commit/470d47cae880f3319dab669068e8a954d2e25784))
* **logs:** add tap-to-expand detail sheet for truncated log entries ([8d84699](https://github.com/Liago/mytube/commit/8d84699d48e6bc30cfbc3dcc4067401e655f2011))
* opens player modal on some video tap ([2a054a2](https://github.com/Liago/mytube/commit/2a054a2f4ab030eb11dabe2229424e8741578ac2))
* optimizes prefetch schedule and bot-check handling ([8aaf54f](https://github.com/Liago/mytube/commit/8aaf54ff403ca0214180d111c50ab19ca1816df2))
* **playlist:** compact layout, oldest-first sort, auto-advance for cached playlist ([567ca5c](https://github.com/Liago/mytube/commit/567ca5c55f772b7eb656eb6e72c022aaa39bc1a3))
* **playlist:** sort cached playlist by exact download date (LastModified) instead of publishedAt ([dafbe60](https://github.com/Liago/mytube/commit/dafbe60748c446b3142600c98956981959106e4c))
* **playlist:** sort items oldest-first and auto-advance to next track ([940225e](https://github.com/Liago/mytube/commit/940225ec260c01d9c95cb90325c6e7d8f8b08b6b))
* **prefetch:** schedule 3h, bot-check notification, android_creator strategy ([0ce2d77](https://github.com/Liago/mytube/commit/0ce2d77c0989e74ceb3cf8ce252fd3a01c82d826))
* reduces cleanup threshold to two days ([ffe829f](https://github.com/Liago/mytube/commit/ffe829f5111f90b8f338051309f21a75531db5cb))
* Trigger initial video history sync on manager initialization ([a7dc343](https://github.com/Liago/mytube/commit/a7dc343e618204be625f4549bf14accd532f1dc8))
* trigger local system push notifications for new prefetched videos ([d00d888](https://github.com/Liago/mytube/commit/d00d8886dee9d65b00a5f2f6fbd4607c5dc8b594))
* **ui:** Display R2 cache status in video cards and channel views ([2e747d8](https://github.com/Liago/mytube/commit/2e747d8ed71958d640b8a504d04df167caa32ab2))
* updated prefetch logic and iOS prefetch toggle ([57f26f6](https://github.com/Liago/mytube/commit/57f26f689671400dd77a0d45c1cb46f971192729))

### Bug Fixes

* add YOUTUBE_COOKIES env var support and improve YouTube bot evasion ([49e6860](https://github.com/Liago/mytube/commit/49e6860c2ceebaec190d0fcee6e22e6f4951d0df))
* aggressively strip whitespaces from proxy_url to prevent InvalidURL yt-dlp aborts ([e57affc](https://github.com/Liago/mytube/commit/e57affc11e24224171dabe9449516195a0a98087))
* always pass cookies in yt-dlp strategies when available ([1966d04](https://github.com/Liago/mytube/commit/1966d04a6925d18335ee34c3ec166b93586f084e))
* audio player ([30d710d](https://github.com/Liago/mytube/commit/30d710d10ed3315c8f92f062e6becc9e5fe0314d))
* **audio:** Change yt-dlp format fallback to include 18 to fix missing format errors ([598e9c2](https://github.com/Liago/mytube/commit/598e9c20d3d55bfd77b524b9e58bcec2496e84c7))
* **audio:** patch cookie expiration format and add unauthenticated fallback cascade for yt-dlp ([8ae5868](https://github.com/Liago/mytube/commit/8ae586870af53c2bdd6de7ecfc5d5a01450b5212))
* avoid publishing to npm ([380ac33](https://github.com/Liago/mytube/commit/380ac3346053c22a20c85cfb853cc5d1b9682aee))
* **backend:** paginate R2 ListObjects to return all cached items ([8e3c065](https://github.com/Liago/mytube/commit/8e3c06593e63562a9401949ee7538ac93b731c64))
* changes cleanup schedule to daily ([df7711a](https://github.com/Liago/mytube/commit/df7711a7efd5cce87e822e6262531239b368b68c))
* correct optional binding for duration.seconds ([5cd92be](https://github.com/Liago/mytube/commit/5cd92be85564afeeafa92249c1ab491bb001f472))
* **debug:** standardise netscape cookie format and update yt-dlp test parameters ([9460a30](https://github.com/Liago/mytube/commit/9460a30156c5a269989f0f83247dc20ab47fe521))
* enhances audio extraction robustness ([d50e701](https://github.com/Liago/mytube/commit/d50e7010ac77179f67ef9f4dac7b860f8ead9c59))
* expand stream extraction with more Piped instances + Invidious fallback ([9d384b0](https://github.com/Liago/mytube/commit/9d384b0753d2b1705306527767c0dd2ce04e7ea3))
* fixes audio playback using Netlify backend ([a5d0a00](https://github.com/Liago/mytube/commit/a5d0a00e04dec5518a93cbace83cb814c1e02da1))
* fixes yt-dlp binary path resolution ([a1cfa1d](https://github.com/Liago/mytube/commit/a1cfa1da35e0fd32cac1462a97a77f5b432d2872))
* implement AVAssetResourceLoaderDelegate for YouTube streams ([c45d846](https://github.com/Liago/mytube/commit/c45d846e698f48fc63ac5ed2ea80f88b6a5bd330))
* implement streaming download with URLSessionDataDelegate ([5c83c32](https://github.com/Liago/mytube/commit/5c83c3226ad994fd6aebb0f033cf3c727e10254c))
* improves audio extraction by handling proxy failures ([c753cea](https://github.com/Liago/mytube/commit/c753ceaa92f0bbe2215967ef721263f5d9f3b403))
* **ios:** resolve HomeView compilation errors and add channelId to Snippet ([3fb6a15](https://github.com/Liago/mytube/commit/3fb6a153a045a519c4bc6910991c8ef7c6d219d5))
* load YouTube cookies from R2 bucket instead of env var ([fe85b12](https://github.com/Liago/mytube/commit/fe85b12a58312a787d38fcd209b5350dbb5e702f))
* **logs:** add visible loading spinner with label during log fetch ([4c73b49](https://github.com/Liago/mytube/commit/4c73b49750d09fd3f12a787fd3bdb781c202fa03))
* **logs:** reverse log order to show newest first and increase font size ([2a890b8](https://github.com/Liago/mytube/commit/2a890b816533073bb6f19ea6a0361c769a9406ae))
* make YouTube video description optional and handle backend errors gracefully ([90501ac](https://github.com/Liago/mytube/commit/90501ac097e8bdda46c23dd9b9b6d6728ed46f3b))
* optimizes yt-dlp arguments for audio extraction ([883cca7](https://github.com/Liago/mytube/commit/883cca7c282b1fffe50e459e64a3ee6c42d2b565))
* **prefetch:** reduce YouTube bot detection with delays and early abort ([19002f8](https://github.com/Liago/mytube/commit/19002f81c7a51d9ed62b8f3565c6f6e99ad23221))
* **prefetch:** resolve queue looping, restore ellipsis menu, fix queue overwrite race ([17fba7f](https://github.com/Liago/mytube/commit/17fba7f5b1260cf7fd909b0f322681692864c4be))
* prioritizes cookie expiration status ([a169ef1](https://github.com/Liago/mytube/commit/a169ef1b1ef82652a3e820d356a49d69f9085a44))
* prioritizes no-cookie audio download strategies ([ef1af97](https://github.com/Liago/mytube/commit/ef1af9767434709478794f09cbfdb4ac8cf2f9e8))
* protects batch check from cancellation during execution ([1b2a893](https://github.com/Liago/mytube/commit/1b2a893f30a09b9dd8df3cd8169e2f3c0392b1a8))
* removes redundant youtube-dl options ([98ea33a](https://github.com/Liago/mytube/commit/98ea33a60b25d8dcc9d58b6d71d741a948ba3fb7))
* replace remaining AppConfig reference with Secrets in LogsView ([a25ea2c](https://github.com/Liago/mytube/commit/a25ea2c534fb576b1d9610b8048df055fd560910))
* resolve 404 NSURLError in LogsView by adding netlify functions path prefix ([399e6fd](https://github.com/Liago/mytube/commit/399e6fde5fb04e4a04c14c8b252fa3e33cd494d4))
* resolve background audio playback and lock screen controls ([6d4f5a7](https://github.com/Liago/mytube/commit/6d4f5a708d072edd4bb52bedb2c77b626fb14899))
* resolve background playback and lock screen control issues ([1587d7e](https://github.com/Liago/mytube/commit/1587d7e4730aaee00672972ad59bcc4b39af6866))
* resolve infinite recursion in UTType extension ([dd78a1f](https://github.com/Liago/mytube/commit/dd78a1f48ec8017649d4d8f90003028b7c4ff1f9))
* resolve iOS compilation errors in LogsView ([6bbfea1](https://github.com/Liago/mytube/commit/6bbfea1d8e9895450124736202566a0e521f1c79))
* restore LocalStreamProxy for reliable YouTube streaming ([abd1920](https://github.com/Liago/mytube/commit/abd19204b51299a635b993624b3ac1adbbd24b3e))
* skip live events, premieres, and unavailable videos immediately ([0f8f24b](https://github.com/Liago/mytube/commit/0f8f24bf54c1970f89100823e82843e7efe1cd4c))
* switch to iOS client impersonation to bypass bot detection ([2000814](https://github.com/Liago/mytube/commit/2000814fe506111ead6d5a9e68d6b712ec2d5a6b))
* switch to TV ([a2b021c](https://github.com/Liago/mytube/commit/a2b021c2eebaf90b26059279e88e70e813f9f86c))
* updates cleanup schedule to cron syntax ([9736ec0](https://github.com/Liago/mytube/commit/9736ec0fa120a6492426de94c4317c353b5979eb))
* updates youtube-dl user agent ([886665a](https://github.com/Liago/mytube/commit/886665a60a251a46262b22f5b5a55ce314c20174))
* use correct UTType for AAC audio ([b8a5140](https://github.com/Liago/mytube/commit/b8a51407e91ce552a9bbd03702802fe636248b1c))
* use format fallback chain and remove player_client=web ([5674519](https://github.com/Liago/mytube/commit/56745198e2abec3745d704587579983e607d211a))
* use stream chunks to read R2 cookie response body ([9a754ac](https://github.com/Liago/mytube/commit/9a754acec2b9c53ad9ee3c1d4d15622c207cdbf2))
* various on player ([ebc29b3](https://github.com/Liago/mytube/commit/ebc29b319e6cd3b9d6417d92baf21d974d3b3bd6))
* **yt:** catch shadowban explicitly as 'Requested format is not available' and fast-fail ([24daa70](https://github.com/Liago/mytube/commit/24daa70280acaf657e010ae2d6c8c32537a29a51))

## [1.28.0](https://github.com/Liago/mytube/compare/v1.27.1...v1.28.0) (2026-04-02)

### Features

* **playlist:** sort items oldest-first and auto-advance to next track ([db105db](https://github.com/Liago/mytube/commit/db105db36369d91d6f8c10c70a2bcfffbf31f503))

## [1.27.1](https://github.com/Liago/mytube/compare/v1.27.0...v1.27.1) (2026-03-30)

### Bug Fixes

* **backend:** paginate R2 ListObjects to return all cached items ([1f856a0](https://github.com/Liago/mytube/commit/1f856a01d24069298edf95ae2d7196d4d6ad4236))

## [1.27.0](https://github.com/Liago/mytube/compare/v1.26.1...v1.27.0) (2026-03-30)

### Features

* **playlist:** sort cached playlist by exact download date (LastModified) instead of publishedAt ([759858a](https://github.com/Liago/mytube/commit/759858a4b11c4e74e9a126a8fb2752d91b550322))

## [1.26.1](https://github.com/Liago/mytube/compare/v1.26.0...v1.26.1) (2026-03-30)

### Bug Fixes

* **prefetch:** resolve queue looping, restore ellipsis menu, fix queue overwrite race ([ed0617a](https://github.com/Liago/mytube/commit/ed0617a0627cdff92a9b7fb119b4aab0bc4c8f61))

## [1.26.0](https://github.com/Liago/mytube/compare/v1.25.1...v1.26.0) (2026-03-30)

### Features

* add individual episode prefetch queue ([64ab278](https://github.com/Liago/mytube/commit/64ab278550a9da01a97a4190c5b6d7b882bd93eb))

## [1.25.1](https://github.com/Liago/mytube/compare/v1.25.0...v1.25.1) (2026-03-27)

### Bug Fixes

* make YouTube video description optional and handle backend errors gracefully ([fd8c22b](https://github.com/Liago/mytube/commit/fd8c22b3d26594588242485ccf75aa9611b9a3ec))

## [1.25.0](https://github.com/Liago/mytube/compare/v1.24.1...v1.25.0) (2026-03-27)

### Features

* implement cached episodes playlist UI and backend logic ([9622fab](https://github.com/Liago/mytube/commit/9622fab98d92254c191221bfbc6eec427e87355d))

## [1.24.1](https://github.com/Liago/mytube/compare/v1.24.0...v1.24.1) (2026-03-26)

### Bug Fixes

* **logs:** add visible loading spinner with label during log fetch ([ca2989d](https://github.com/Liago/mytube/commit/ca2989d73b8a41f4716cbf58c187a28160712000))

## [1.24.0](https://github.com/Liago/mytube/compare/v1.23.2...v1.24.0) (2026-03-26)

### Features

* **logs:** add tap-to-expand detail sheet for truncated log entries ([7082869](https://github.com/Liago/mytube/commit/7082869d577e083baaa0092904aff4178bc661f2))

## [1.23.2](https://github.com/Liago/mytube/compare/v1.23.1...v1.23.2) (2026-03-26)

### Bug Fixes

* **logs:** reverse log order to show newest first and increase font size ([1662f6d](https://github.com/Liago/mytube/commit/1662f6d8cb8e35f588175e2eff079b878b8d64e0))

## [1.23.1](https://github.com/Liago/mytube/compare/v1.23.0...v1.23.1) (2026-03-26)

### Bug Fixes

* skip live events, premieres, and unavailable videos immediately ([740e634](https://github.com/Liago/mytube/commit/740e6340cccf1a1ae6ee85b35866997d49997b12))

## [1.23.0](https://github.com/Liago/mytube/compare/v1.22.6...v1.23.0) (2026-03-11)

### Features

* adaptive bot-check mitigation for peak hours ([f520794](https://github.com/Liago/mytube/commit/f520794207c531a0c92edec52746a70c0ffb0642))

## [1.22.6](https://github.com/Liago/mytube/compare/v1.22.5...v1.22.6) (2026-03-09)

### Bug Fixes

* **debug:** standardise netscape cookie format and update yt-dlp test parameters ([d47ae80](https://github.com/Liago/mytube/commit/d47ae80cae5cb1d7f5ce6a401002c08877fb7d50))

## [1.22.5](https://github.com/Liago/mytube/compare/v1.22.4...v1.22.5) (2026-03-09)

### Bug Fixes

* **yt:** catch shadowban explicitly as 'Requested format is not available' and fast-fail ([b062b2c](https://github.com/Liago/mytube/commit/b062b2c35b8b7277d32e4968ed3e66c9be0129a7))

## [1.22.4](https://github.com/Liago/mytube/compare/v1.22.3...v1.22.4) (2026-03-09)

### Bug Fixes

* **audio:** patch cookie expiration format and add unauthenticated fallback cascade for yt-dlp ([ab4f520](https://github.com/Liago/mytube/commit/ab4f5202000c461089bf94f4deb8fd16ada72e01))

## [1.22.3](https://github.com/Liago/mytube/compare/v1.22.2...v1.22.3) (2026-03-07)

### Bug Fixes

* **prefetch:** reduce YouTube bot detection with delays and early abort ([7d6d71f](https://github.com/Liago/mytube/commit/7d6d71f274a2b835f3ad2d642608f7e7a0251fbb))

## [1.22.2](https://github.com/Liago/mytube/compare/v1.22.1...v1.22.2) (2026-03-05)

### Bug Fixes

* always pass cookies in yt-dlp strategies when available ([5317d14](https://github.com/Liago/mytube/commit/5317d145e5c321f0458658fd5a6176d553f090de))

## [1.22.1](https://github.com/Liago/mytube/compare/v1.22.0...v1.22.1) (2026-03-05)

### Bug Fixes

* **audio:** Change yt-dlp format fallback to include 18 to fix missing format errors ([1feb8a6](https://github.com/Liago/mytube/commit/1feb8a60be0ed448e356ce8033dbe80d7e36906b))

## [1.22.0](https://github.com/Liago/mytube/compare/v1.21.0...v1.22.0) (2026-03-04)

### Features

* align player strategies and improve cookie formatting ([0dbb6d4](https://github.com/Liago/mytube/commit/0dbb6d4afd0e7232529894c2b798341de5530538))

## [1.21.0](https://github.com/Liago/mytube/compare/v1.20.0...v1.21.0) (2026-03-03)

### Features

* add log cleanup to scheduled cleanup function (7-day retention) ([af870b6](https://github.com/Liago/mytube/commit/af870b64b1f8cf90d2dafcdf037ad760427a96ad))

## [1.20.0](https://github.com/Liago/mytube/compare/v1.19.0...v1.20.0) (2026-03-03)

### Features

* **prefetch:** schedule 3h, bot-check notification, android_creator strategy ([9ab930c](https://github.com/Liago/mytube/commit/9ab930c9c84e708e2e941bbe802cce0300edfb27))

## [1.19.0](https://github.com/Liago/mytube/compare/v1.18.0...v1.19.0) (2026-03-03)

### Features

* optimizes prefetch schedule and bot-check handling ([45ae82c](https://github.com/Liago/mytube/commit/45ae82cbf4a42b308e3487df7c25eeaa8c468a67))

## [1.18.0](https://github.com/Liago/mytube/compare/v1.17.0...v1.18.0) (2026-02-25)

### Features

* trigger local system push notifications for new prefetched videos ([069e6b2](https://github.com/Liago/mytube/commit/069e6b2859951fbd9c09c19117287f60055e6227))

## [1.17.0](https://github.com/Liago/mytube/compare/v1.16.0...v1.17.0) (2026-02-25)

### Features

* in-app notification system for prefetched videos ([8f3c52c](https://github.com/Liago/mytube/commit/8f3c52c2f8554a201450f158fd8f1fd3e373d231))

## [1.16.0](https://github.com/Liago/mytube/compare/v1.15.4...v1.16.0) (2026-02-25)

### Features

* inject R2 unified logger into cleanup scheduled function ([a0ec8cc](https://github.com/Liago/mytube/commit/a0ec8cc604b47225a3210543e66b267b1c2c10b0))

## [1.15.4](https://github.com/Liago/mytube/compare/v1.15.3...v1.15.4) (2026-02-25)

### Bug Fixes

* aggressively strip whitespaces from proxy_url to prevent InvalidURL yt-dlp aborts ([8d321b8](https://github.com/Liago/mytube/commit/8d321b86245397164937393679163d1b88410950))

## [1.15.3](https://github.com/Liago/mytube/compare/v1.15.2...v1.15.3) (2026-02-25)

### Bug Fixes

* resolve 404 NSURLError in LogsView by adding netlify functions path prefix ([eaee09c](https://github.com/Liago/mytube/commit/eaee09c2d477f11e2b178f646625b6accdfda15b))

## [1.15.2](https://github.com/Liago/mytube/compare/v1.15.1...v1.15.2) (2026-02-25)

### Bug Fixes

* replace remaining AppConfig reference with Secrets in LogsView ([11c13ba](https://github.com/Liago/mytube/commit/11c13ba561fbce5b951dedc9e137237cd3faea2f))

## [1.15.1](https://github.com/Liago/mytube/compare/v1.15.0...v1.15.1) (2026-02-25)

### Bug Fixes

* resolve iOS compilation errors in LogsView ([a893fe4](https://github.com/Liago/mytube/commit/a893fe400b8e94e28c90f2a6e64c66789e02d8c9))

## [1.15.0](https://github.com/Liago/mytube/compare/v1.14.1...v1.15.0) (2026-02-25)

### Features

* implement centralized R2 logger, fix proxy url parsing, replace iOS Playlists tab with Logs ([863b82f](https://github.com/Liago/mytube/commit/863b82f72cd55968892240b9d63ee445069064b9))

## [1.14.1](https://github.com/Liago/mytube/compare/v1.14.0...v1.14.1) (2026-02-25)

### Bug Fixes

* improves audio extraction by handling proxy failures ([25a2029](https://github.com/Liago/mytube/commit/25a2029ad4e077e51f2aa218bb8db29b163f5ea4))

## [1.14.0](https://github.com/Liago/mytube/compare/v1.13.0...v1.14.0) (2026-02-24)

### Features

* reduces cleanup threshold to two days ([d46e0a7](https://github.com/Liago/mytube/commit/d46e0a70514c5f02a1ac419182d3f24e30f44ef7))

## [1.13.0](https://github.com/Liago/mytube/compare/v1.12.3...v1.13.0) (2026-02-24)

### Features

* improves proxy handling and retry logic. ([f70b292](https://github.com/Liago/mytube/commit/f70b292754fc35ae9cee63677f172aa998d1f4b6))

## [1.12.3](https://github.com/Liago/mytube/compare/v1.12.2...v1.12.3) (2026-02-24)

### Bug Fixes

* optimizes yt-dlp arguments for audio extraction ([26e8f0d](https://github.com/Liago/mytube/commit/26e8f0da592144cb5b17cd01e1c69bef9f6ce237))

## [1.12.2](https://github.com/Liago/mytube/compare/v1.12.1...v1.12.2) (2026-02-24)

### Bug Fixes

* fixes yt-dlp binary path resolution ([a54a118](https://github.com/Liago/mytube/commit/a54a1189558f7508a47170b38968d131dd36f78d))

## [1.12.1](https://github.com/Liago/mytube/compare/v1.12.0...v1.12.1) (2026-02-24)

### Bug Fixes

* updates cleanup schedule to cron syntax ([1eaccee](https://github.com/Liago/mytube/commit/1eaccee61342d6be0111461b10ac400506835f8f))

## [1.12.0](https://github.com/Liago/mytube/compare/v1.11.2...v1.12.0) (2026-02-23)

### Features

* updated prefetch logic and iOS prefetch toggle ([a9c2e20](https://github.com/Liago/mytube/commit/a9c2e202d72701d791af7abdb7e2676a8e2ca91a))

## [1.11.2](https://github.com/Liago/mytube/compare/v1.11.1...v1.11.2) (2026-02-23)

### Bug Fixes

* changes cleanup schedule to daily ([f6eda3b](https://github.com/Liago/mytube/commit/f6eda3b986007b7c01268f8c5fc0c2651a4f05c6))

## [1.11.1](https://github.com/Liago/mytube/compare/v1.11.0...v1.11.1) (2026-02-17)

### Bug Fixes

* **ios:** resolve HomeView compilation errors and add channelId to Snippet ([ee79491](https://github.com/Liago/mytube/commit/ee794911fdf33c878cc72f398519b3d290bb4220))

## [1.11.0](https://github.com/Liago/mytube/compare/v1.10.0...v1.11.0) (2026-02-17)

### Features

* enhances audio extraction strategy ([8820d32](https://github.com/Liago/mytube/commit/8820d32292dac1ebee36b809fb65124ce27c0be5))

## [1.10.0](https://github.com/Liago/mytube/compare/v1.9.1...v1.10.0) (2026-02-17)

### Features

* implement channel navigation from home feed cards ([8e58dcc](https://github.com/Liago/mytube/commit/8e58dcc6db4dded3144a31b614fa2a20baeac09d))

## [1.9.1](https://github.com/Liago/mytube/compare/v1.9.0...v1.9.1) (2026-02-17)

### Bug Fixes

* prioritizes no-cookie audio download strategies ([85197cf](https://github.com/Liago/mytube/commit/85197cff8219e8d9b6facad0613b5e613440d02a))

## [1.9.0](https://github.com/Liago/mytube/compare/v1.8.0...v1.9.0) (2026-02-16)

### Features

* enhances video download and playback resilience ([84a5a5b](https://github.com/Liago/mytube/commit/84a5a5b9cdafd5a66ca91f07e75bd1ce7a51c681))

## [1.8.0](https://github.com/Liago/mytube/compare/v1.7.5...v1.8.0) (2026-02-06)

### Features

* improves YouTube extraction and adds proxy support ([d46e58e](https://github.com/Liago/mytube/commit/d46e58e88f4b701ed28b16c7ebebda52572c2bc5))

## [1.7.5](https://github.com/Liago/mytube/compare/v1.7.4...v1.7.5) (2026-02-06)

### Bug Fixes

* switch to TV ([839ce8b](https://github.com/Liago/mytube/commit/839ce8b504d7387afbb0414dff9ac79de708c140))

## [1.7.4](https://github.com/Liago/mytube/compare/v1.7.3...v1.7.4) (2026-02-06)

### Bug Fixes

* switch to iOS client impersonation to bypass bot detection ([55d1623](https://github.com/Liago/mytube/commit/55d16233636cb22834f6d87c8891c5504124400a))

## [1.7.3](https://github.com/Liago/mytube/compare/v1.7.2...v1.7.3) (2026-02-06)

### Bug Fixes

* removes redundant youtube-dl options ([731603f](https://github.com/Liago/mytube/commit/731603ff2195c706573855b2cfc5abdaa344b099))

## [1.7.2](https://github.com/Liago/mytube/compare/v1.7.1...v1.7.2) (2026-02-06)

### Bug Fixes

* enhances audio extraction robustness ([fbc5861](https://github.com/Liago/mytube/commit/fbc5861d7585d1a31b6faa1c2821d04ffead56fa))

## [1.7.1](https://github.com/Liago/mytube/compare/v1.7.0...v1.7.1) (2026-02-06)

### Bug Fixes

* updates youtube-dl user agent ([383564a](https://github.com/Liago/mytube/commit/383564a249f6a4159389b0c749d05df507094375))

## [1.7.0](https://github.com/Liago/mytube/compare/v1.6.0...v1.7.0) (2026-02-05)

### Features

* adds Google session status card ([4a6bee9](https://github.com/Liago/mytube/commit/4a6bee94d9c2fd558ad23f339736cfb6da480d66))

## [1.6.0](https://github.com/Liago/mytube/compare/v1.5.0...v1.6.0) (2026-02-05)

### Features

* introduces splash screen during authentication ([0c97778](https://github.com/Liago/mytube/commit/0c97778dbcf19d8c2a5dc5b9f4ed09455301fcca))

## [1.5.0](https://github.com/Liago/mytube/compare/v1.4.0...v1.5.0) (2026-02-05)

### Features

* adds background video prefetching and preferences syncing ([7085182](https://github.com/Liago/mytube/commit/7085182e69063a91faad4df04c79f14c4f92b6be))

## [1.4.0](https://github.com/Liago/mytube/compare/v1.3.0...v1.4.0) (2026-02-05)

### Features

* Add cloud sync mechanism to VideoStatusManager ([8b51f98](https://github.com/Liago/mytube/commit/8b51f9874259eb85efdee509834c1159e3f22c21))
* Implement Netlify function for video history cloud sync ([aef290e](https://github.com/Liago/mytube/commit/aef290ed8f3bdd48005ec5358bd9f86fc36f6577))
* Trigger initial video history sync on manager initialization ([443d6ea](https://github.com/Liago/mytube/commit/443d6eac4c9b89459e988bfe79bd02b747d2eea7))

## [1.3.0](https://github.com/Liago/mytube/compare/v1.2.1...v1.3.0) (2026-02-05)

### Features

* displays user profile information ([ce13c2c](https://github.com/Liago/mytube/commit/ce13c2c927aed08dd4a7b8b2751ecb8c5ca5c222))

## [1.2.1](https://github.com/Liago/mytube/compare/v1.2.0...v1.2.1) (2026-02-05)

### Bug Fixes

* prioritizes cookie expiration status ([056fe64](https://github.com/Liago/mytube/commit/056fe64c4c4df4c31e577070e6eabcca6abb25a9))

## [1.2.0](https://github.com/Liago/mytube/compare/v1.1.0...v1.2.0) (2026-02-05)

### Features

* **backend:** Add Netlify function for cookie status API ([0d03317](https://github.com/Liago/mytube/commit/0d03317a3015a53fe79453d826b164a63d655564))
* **ios:** Add ProfileView with cookie status and tab integration ([a5bb83d](https://github.com/Liago/mytube/commit/a5bb83dfc8dfeca4ccd4e0fd564f7e1241b92096))
* **ios:** Implement CookieStatusService and expiration notifications ([befc1c5](https://github.com/Liago/mytube/commit/befc1c5cd85fbe654dd8837a1e25770308a4dd26))

## [1.1.0](https://github.com/Liago/mytube/compare/v1.0.4...v1.1.0) (2026-02-05)

### Features

* improves audio download reliability ([e3139a5](https://github.com/Liago/mytube/commit/e3139a5aa6c239eca782ea3f25abb5c16bec6851))

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
