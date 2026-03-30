const { S3Client, GetObjectCommand, PutObjectCommand, HeadObjectCommand } = require("@aws-sdk/client-s3");
const { schedule } = require('@netlify/functions');
const Parser = require('rss-parser');
const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');
const parser = new Parser({
	customFields: {
		item: ['media:group', 'media:title']
	},
	headers: {
		'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36'
	}
});

// Helper: sleep for a random duration between min and max milliseconds
const sleep = (minMs, maxMs) => {
	const ms = Math.floor(Math.random() * (maxMs - minMs + 1)) + minMs;
	return new Promise(resolve => setTimeout(resolve, ms));
};

// Peak hour detection (14:00-22:00 CET/CEST)
const isPeakHour = () => {
	const now = new Date();
	const cetHour = new Date(now.toLocaleString('en-US', { timeZone: 'Europe/Rome' })).getHours();
	return cetHour >= 14 && cetHour < 22;
};

// Fisher-Yates shuffle
const shuffleArray = (arr) => {
	const copy = [...arr];
	for (let i = copy.length - 1; i > 0; i--) {
		const j = Math.floor(Math.random() * (i + 1));
		[copy[i], copy[j]] = [copy[j], copy[i]];
	}
	return copy;
};

// Configuration
const R2_ACCOUNT_ID = process.env.R2_ACCOUNT_ID;
const R2_ACCESS_KEY_ID = process.env.R2_ACCESS_KEY_ID;
const R2_SECRET_ACCESS_KEY = process.env.R2_SECRET_ACCESS_KEY;
const R2_BUCKET_NAME = process.env.R2_BUCKET_NAME || "mytube-audio";
const PREFS_FILE_KEY = "system/home_channels.json";
const QUEUE_FILE_KEY = "system/prefetch_queue.json";

const s3 = new S3Client({
	region: "auto",
	endpoint: `https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com`,
	credentials: {
		accessKeyId: R2_ACCESS_KEY_ID,
		secretAccessKey: R2_SECRET_ACCESS_KEY,
	},
});

const runYtDlp = async (url, outputPath, cookiesPath, ctx = { skipProxy: false }) => {
	const isLinux = process.platform === 'linux';
	const binaryName = isLinux ? 'yt-dlp-linux' : 'yt-dlp';
	const binPath = path.resolve(process.cwd(), binaryName);

	if (!fs.existsSync(binPath)) {
		throw new Error(`yt-dlp binary not found at ${binPath}`);
	}

	const CHROME_UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';
	const PLAYER_CLIENTS = ['tv_embedded', 'web_creator', 'mweb', 'android', 'ios', 'web', 'android_creator'];

	const executeStrategy = async (useCookies, playerClient) => {
		return new Promise((resolve, reject) => {
			const args = [
				'-f', '140/bestaudio[ext=m4a]/bestaudio/18/best',
				'-o', outputPath,
				'--force-overwrites',
				'--no-playlist',
				'--no-warnings',
				'--js-runtimes', `node:${process.execPath}`,
				url
			];

			if (useCookies && cookiesPath && fs.existsSync(cookiesPath)) {
				args.push('--cookies', cookiesPath);
			}

			args.push('--extractor-args', `youtube:player_client=${playerClient}`);
			args.push('--user-agent', CHROME_UA);
			args.push('--compat-options', '2025');
			// Adaptive intra-request delays: more conservative during peak hours
			const sleepRequests = ctx.sleepRequests || '2';
			const sleepInterval = ctx.sleepInterval || '3';
			const maxSleepInterval = ctx.maxSleepInterval || '10';
			args.push('--sleep-requests', sleepRequests);
			args.push('--sleep-interval', sleepInterval);
			args.push('--max-sleep-interval', maxSleepInterval);

			const proxyUrl = (process.env.PROXY_URL || '').replace(/\s+/g, '');
			if (proxyUrl && !ctx.skipProxy && proxyUrl.startsWith('http')) {
				if (ctx.logger) ctx.logger.info(`Using Proxy: ${proxyUrl}`);
				args.push('--proxy', proxyUrl);
			} else if (proxyUrl && ctx.skipProxy) {
				if (ctx.logger) ctx.logger.info('Proxy disabled for this request due to previous error.');
			}

			const processProc = spawn(binPath, args, { stdio: ['ignore', 'pipe', 'pipe'] });

			let stderrOutput = '';
			processProc.stderr.on('data', (data) => {
				stderrOutput += data.toString();
			});

			processProc.on('close', (code) => {
				if (code === 0) resolve();
				else {
					if (stderrOutput.includes('429 Too Many Requests') || stderrOutput.includes('Unable to connect to proxy') || stderrOutput.includes('ProxyError')) {
						ctx.skipProxy = true;
						reject(new Error(`Proxy rate limit detected. Disabling proxy. Stderr: ${stderrOutput}`));
					} else {
						reject(new Error(`yt-dlp exited with code ${code}. Stderr: ${stderrOutput}`));
					}
				}
			});
		});
	};

	let downloadSuccess = false;
	let downloadError = null;
	const hasCookies = cookiesPath && fs.existsSync(cookiesPath);

	const strategies = [];
	if (hasCookies) {
		strategies.push({ useCookies: true, playerClient: 'android_creator' });
		strategies.push({ useCookies: true, playerClient: 'web' });
		strategies.push({ useCookies: true, playerClient: 'tv_embedded' });
		strategies.push({ useCookies: true, playerClient: 'ios' });
		strategies.push({ useCookies: true, playerClient: 'android' });
		strategies.push({ useCookies: true, playerClient: 'mweb' });
	}
	
	// Fallback to cookie-less strategies if all authenticated ones fail or no cookies are present
	for (const client of PLAYER_CLIENTS) {
		strategies.push({ useCookies: false, playerClient: client });
	}

	const MAX_ATTEMPTS = 8;
	const cappedStrategies = strategies.slice(0, MAX_ATTEMPTS);

	for (let i = 0; i < cappedStrategies.length; i++) {
		const strategy = cappedStrategies[i];
		if (downloadSuccess) break;
		try {
			if (ctx.logger) ctx.logger.info(`Trying strategy client=${strategy.playerClient}, cookies=${strategy.useCookies}`);
			await executeStrategy(strategy.useCookies, strategy.playerClient);
			downloadSuccess = true;
			if (ctx.logger) ctx.logger.info(`Success with strategy client=${strategy.playerClient}`);
		} catch (err) {
			if (ctx.logger) ctx.logger.warn(`Strategy failed: ${err.message}`);
			downloadError = err;
			if (err.message.includes('Proxy rate limit detected') || err.message.includes('Proxy error detected')) {
				if (ctx.logger) ctx.logger.info(`Proxy disabled globally. Retrying same strategy without proxy...`);
				i--; // Retry the same strategy without proxy
			} else if (err.message.includes('Sign in to confirm') || err.message.includes('confirm you') || err.message.includes('Requested format is not available')) {
				if (ctx.logger) ctx.logger.warn(`Bot-check/shadowban detected. Aborting further strategies.`);
				break; // Fail fast
			} else if (err.message.includes('live event will begin') || err.message.includes('Premieres in') || err.message.includes('This video is not available') || err.message.includes('Video unavailable') || err.message.includes('is not a valid URL') || err.message.includes('Private video')) {
				if (ctx.logger) ctx.logger.warn(`Video not downloadable (live/premiere/unavailable). Skipping.`);
				downloadError = new Error(`SKIP: ${err.message}`);
				break; // No point retrying with different clients
			}
		}
	}

	if (!downloadSuccess) {
		throw downloadError || new Error("All download strategies exhausted");
	}
};

const prefetchHandler = async (event) => {
	const Logger = require('./lib/logger');
	const logger = new Logger('scheduled-prefetch');
	logger.info("Starting Scheduled Prefetch...");

	try {
		let channels = [];
		try {
			const data = await s3.send(new GetObjectCommand({ Bucket: R2_BUCKET_NAME, Key: PREFS_FILE_KEY }));
			const body = await data.Body.transformToString();
			const prefs = JSON.parse(body);
			// Use prefetchChannels if present, fallback to channels for retrocompatibility
			channels = prefs.prefetchChannels || prefs.channels || [];
		} catch (e) {
			logger.warn(`No preferences found or error reading prefs: ${e.message}`);
			return;
		}

		if (channels.length === 0) {
			logger.info("No prefetch channels to scan.");
			await logger.save();
			return;
		}

		// 2. Download Cookies (for yt-dlp)
		const cookiesPath = '/tmp/cookies.txt'; // Netscape format needed
		try {
			// Need to convert JSON cookies to Netscape or assume we have a netscape file on R2?
			// The audio.js uses _cookies.json (JSON). runYtDlp logic in audio.js handled conversion.
			// We should ideally fetch _cookies.json and convert.
			// For brevity, let's assume we fetch `_cookies.json` and convert it here.
			const cookieData = await s3.send(new GetObjectCommand({ Bucket: R2_BUCKET_NAME, Key: 'system/_cookies.json' }));
			const cookieJson = JSON.parse(await cookieData.Body.transformToString());

			// Convert to Netscape
			const netscapeCookies = cookieJson.map(c => {
				const domain = c.domain.startsWith('.') ? c.domain : `.${c.domain}`;
				const includeSubdomains = 'TRUE';
				const cookiePath = c.path;
				const secure = c.secure ? 'TRUE' : 'FALSE';
				const expiration = c.expirationDate ? Math.round(c.expirationDate) : 0;
				return `${domain}\t${includeSubdomains}\t${cookiePath}\t${secure}\t${expiration}\t${c.name}\t${c.value}`;
			}).join('\n');
			fs.writeFileSync(cookiesPath, '# Netscape HTTP Cookie File\n' + netscapeCookies);

		} catch (e) {
			logger.warn(`Could not load/convert cookies: ${e.message}`);
			// Continue without cookies? Might fail for some videos.
		}

		// 3. Scan & Download
		const newNotifications = [];
		const peak = isPeakHour();
		logger.info(`Time profile: ${peak ? 'PEAK hours (14-22 CET) — conservative mode' : 'Off-peak hours — normal mode'}`);

		const runCtx = {
			skipProxy: false,
			logger,
			sleepRequests: peak ? '4' : '2',
			sleepInterval: peak ? '5' : '3',
			maxSleepInterval: peak ? '15' : '10',
		};

		const VIDEO_DELAY = peak ? [30, 90] : [10, 45];
		const CHANNEL_DELAY = peak ? [60, 180] : [30, 90];
		const VIDEOS_PER_CHANNEL = peak ? 1 : 2;

		// Track bot detection across the entire run — abort everything if triggered
		let botDetected = false;
		let consecutiveBotChecks = 0;
		const MAX_BOT_RETRIES = 1; // Allow 1 retry with backoff before aborting

		// 3a. Process Prefetch Queue (user-requested episodes, higher priority than channel scan)
		let queueItems = [];
		try {
			const queueData = await s3.send(new GetObjectCommand({ Bucket: R2_BUCKET_NAME, Key: QUEUE_FILE_KEY }));
			const queueBody = await queueData.Body.transformToString();
			const queue = JSON.parse(queueBody);
			queueItems = queue.items || [];
		} catch (e) {
			if (e.name === 'NoSuchKey' || e.name === 'NotFound') {
				logger.info("No prefetch queue found. Skipping queue phase.");
			} else {
				logger.warn(`Error reading prefetch queue: ${e.message}`);
			}
		}

		if (queueItems.length > 0) {
			logger.info(`Processing prefetch queue: ${queueItems.length} items`);
			const processedIds = new Set();

			for (let qi = 0; qi < queueItems.length; qi++) {
				if (botDetected) break;

				const queueItem = queueItems[qi];
				const videoId = queueItem.videoId;
				const r2Key = `${videoId}_v2.m4a`;

				// Check if already cached
				try {
					await s3.send(new HeadObjectCommand({ Bucket: R2_BUCKET_NAME, Key: r2Key }));
					logger.info(`Queue item ${videoId} already cached. Removing from queue.`);
					processedIds.add(videoId);
				} catch (e) {
					if (e.name === 'NotFound' || e.name === '404') {
						logger.info(`Queue item ${videoId} not cached. Downloading...`);

						try {
							const tempPath = `/tmp/${videoId}.m4a`;
							const videoUrl = `https://www.youtube.com/watch?v=${videoId}`;
							await runYtDlp(videoUrl, tempPath, fs.existsSync(cookiesPath) ? cookiesPath : null, runCtx);

							if (fs.existsSync(tempPath)) {
								const fileStream = fs.createReadStream(tempPath);
								const stats = fs.statSync(tempPath);
								await s3.send(new PutObjectCommand({
									Bucket: R2_BUCKET_NAME,
									Key: r2Key,
									Body: fileStream,
									ContentType: 'audio/mp4',
									ContentLength: stats.size
								}));
								logger.info(`Uploaded queue item ${videoId} to R2.`);

								newNotifications.push({
									id: videoId,
									title: queueItem.title || 'Unknown Title',
									channelInfo: queueItem.channelName || 'Prefetch Queue',
									timestamp: new Date().toISOString()
								});

								fs.unlinkSync(tempPath);
							}
							processedIds.add(videoId);
						} catch (downloadErr) {
							if (downloadErr.message.startsWith("SKIP:")) {
								logger.warn(`Skipping queue item ${videoId}: ${downloadErr.message}`);
								processedIds.add(videoId); // Remove non-downloadable items from queue
							} else {
								logger.error(`Download failed for queue item ${videoId}: ${downloadErr.message}`);

								if (downloadErr.message.includes('Sign in to confirm') || downloadErr.message.includes('confirm you') || downloadErr.message.includes('Requested format is not available')) {
									consecutiveBotChecks++;

									if (consecutiveBotChecks <= MAX_BOT_RETRIES) {
										const backoffSec = Math.floor(Math.random() * 61) + 60;
										logger.warn(`Bot-check detected during queue processing (attempt ${consecutiveBotChecks}/${MAX_BOT_RETRIES + 1}). Backing off ${backoffSec}s...`);
										await sleep(backoffSec * 1000, backoffSec * 1000);

										try {
											logger.info(`Retrying queue item ${videoId} after backoff...`);
											const tempPath = `/tmp/${videoId}.m4a`;
											const videoUrl = `https://www.youtube.com/watch?v=${videoId}`;
											await runYtDlp(videoUrl, tempPath, fs.existsSync(cookiesPath) ? cookiesPath : null, runCtx);

											if (fs.existsSync(tempPath)) {
												const fileStream = fs.createReadStream(tempPath);
												const stats = fs.statSync(tempPath);
												await s3.send(new PutObjectCommand({
													Bucket: R2_BUCKET_NAME,
													Key: r2Key,
													Body: fileStream,
													ContentType: 'audio/mp4',
													ContentLength: stats.size
												}));
												logger.info(`Uploaded queue item ${videoId} to R2 (after retry).`);
												newNotifications.push({
													id: videoId,
													title: queueItem.title || 'Unknown Title',
													channelInfo: queueItem.channelName || 'Prefetch Queue',
													timestamp: new Date().toISOString()
												});
												fs.unlinkSync(tempPath);
											}
											processedIds.add(videoId);
											consecutiveBotChecks = 0;
										} catch (retryErr) {
											logger.warn(`Queue retry also failed: ${retryErr.message}`);
											consecutiveBotChecks++;
										}
									}

									if (consecutiveBotChecks > MAX_BOT_RETRIES) {
										logger.warn('Bot-check persistent during queue processing. Aborting run.');
										botDetected = true;
										newNotifications.push({
											id: `bot-check-${Date.now()}`,
											title: '⚠️ Bot-check persistente — Cookies da verificare',
											channelInfo: 'Sistema',
											timestamp: new Date().toISOString(),
											type: 'error',
											message: 'YouTube bot-check persistente durante processing coda prefetch. Verificare cookies.'
										});
										break;
									}
								}
							}
						}

						// Delay between queue downloads
						if (!botDetected && qi < queueItems.length - 1) {
							const delaySec = Math.floor(Math.random() * (VIDEO_DELAY[1] - VIDEO_DELAY[0] + 1)) + VIDEO_DELAY[0];
							logger.info(`Waiting ${delaySec}s before next queue item...`);
							await sleep(delaySec * 1000, delaySec * 1000);
						}
					}
				}
			}

			// Update queue on R2: remove processed items
			const remainingItems = queueItems.filter(item => !processedIds.has(item.videoId));
			try {
				await s3.send(new PutObjectCommand({
					Bucket: R2_BUCKET_NAME,
					Key: QUEUE_FILE_KEY,
					Body: JSON.stringify({ items: remainingItems, lastUpdated: new Date().toISOString() }),
					ContentType: 'application/json'
				}));
				logger.info(`Queue processed: ${processedIds.size} downloaded/removed, ${remainingItems.length} remaining.`);
			} catch (e) {
				logger.error(`Failed to update prefetch queue on R2: ${e.message}`);
			}
		}

		// 3b. Channel RSS Scan
		// Shuffle channels to avoid predictable patterns
		const shuffledChannels = shuffleArray(channels);

		for (let ci = 0; ci < shuffledChannels.length; ci++) {
			if (botDetected) break;

			const channelId = shuffledChannels[ci];
			logger.info(`Scanning channel: ${channelId}`);
			try {
				const feed = await parser.parseURL(`https://www.youtube.com/feeds/videos.xml?channel_id=${channelId}`);

				// Adaptive: fewer videos per channel during peak hours
				const videosToCheck = feed.items.slice(0, VIDEOS_PER_CHANNEL);

				for (let vi = 0; vi < videosToCheck.length; vi++) {
					if (botDetected) break;

					const video = videosToCheck[vi];
					const videoId = video.id.replace('yt:video:', '');
					const r2Key = `${videoId}_v2.m4a`;

					// Check availability
					try {
						await s3.send(new HeadObjectCommand({ Bucket: R2_BUCKET_NAME, Key: r2Key }));
						logger.info(`Video ${videoId} already exists. Skipping.`);
					} catch (e) {
						if (e.name === 'NotFound' || e.name === '404') {
							logger.info(`Video ${videoId} missing. Downloading...`);

							try {
								// Download
								const tempPath = `/tmp/${videoId}.m4a`;
								await runYtDlp(video.link, tempPath, fs.existsSync(cookiesPath) ? cookiesPath : null, runCtx);

								// Upload
								if (fs.existsSync(tempPath)) {
									const fileStream = fs.createReadStream(tempPath);
									const stats = fs.statSync(tempPath);
									await s3.send(new PutObjectCommand({
										Bucket: R2_BUCKET_NAME,
										Key: r2Key,
										Body: fileStream,
										ContentType: 'audio/mp4',
										ContentLength: stats.size
									}));
									logger.info(`Uploaded ${videoId} to R2.`);

									newNotifications.push({
										id: videoId,
										title: video.title || 'Unknown Title',
										channelInfo: feed.title || channelId,
										timestamp: new Date().toISOString()
									});

									fs.unlinkSync(tempPath); // Cleanup
								}
							} catch (downloadErr) {
								// Non-downloadable videos (live, premiere, unavailable) — skip to next video
								if (downloadErr.message.startsWith("SKIP:")) {
									logger.warn(`Skipping video ${videoId}: ${downloadErr.message}`);
								} else {
								logger.error(`Download failed for ${videoId}: ${downloadErr.message}`);

								// Detect bot-check: retry with backoff, then abort if persistent
								if (downloadErr.message.includes('Sign in to confirm') || downloadErr.message.includes('confirm you') || downloadErr.message.includes('Requested format is not available')) {
									consecutiveBotChecks++;

									if (consecutiveBotChecks <= MAX_BOT_RETRIES) {
										// First bot-check: wait and retry this video
										const backoffSec = Math.floor(Math.random() * 61) + 60; // 60-120s
										logger.warn(`Bot-check detected (attempt ${consecutiveBotChecks}/${MAX_BOT_RETRIES + 1}). Backing off ${backoffSec}s before retry...`);
										await sleep(backoffSec * 1000, backoffSec * 1000);

										try {
											logger.info(`Retrying ${videoId} after backoff...`);
											await runYtDlp(video.link, tempPath, fs.existsSync(cookiesPath) ? cookiesPath : null, runCtx);

											// Retry succeeded!
											if (fs.existsSync(tempPath)) {
												const fileStream = fs.createReadStream(tempPath);
												const stats = fs.statSync(tempPath);
												await s3.send(new PutObjectCommand({
													Bucket: R2_BUCKET_NAME,
													Key: r2Key,
													Body: fileStream,
													ContentType: 'audio/mp4',
													ContentLength: stats.size
												}));
												logger.info(`Uploaded ${videoId} to R2 (after retry).`);
												newNotifications.push({
													id: videoId,
													title: video.title || 'Unknown Title',
													channelInfo: feed.title || channelId,
													timestamp: new Date().toISOString()
												});
												fs.unlinkSync(tempPath);
											}
											consecutiveBotChecks = 0; // Reset on success
										} catch (retryErr) {
											logger.warn(`Retry also failed: ${retryErr.message}`);
											consecutiveBotChecks++;
										}
									}

									if (consecutiveBotChecks > MAX_BOT_RETRIES) {
										logger.warn('Bot-check persistent after retry. Aborting run to preserve cookies.');
										botDetected = true;
										newNotifications.push({
											id: `bot-check-${Date.now()}`,
											title: '⚠️ Bot-check persistente — Cookies da verificare',
											channelInfo: 'Sistema',
											timestamp: new Date().toISOString(),
											type: 'error',
											message: 'YouTube bot-check persistente dopo retry con backoff. Verificare cookies o attendere ore notturne.'
										});
										break;
									}
								}
								} // end else (non-SKIP errors)
							}

							// Adaptive delay between video downloads
							if (!botDetected && vi < videosToCheck.length - 1) {
								const delaySec = Math.floor(Math.random() * (VIDEO_DELAY[1] - VIDEO_DELAY[0] + 1)) + VIDEO_DELAY[0];
								logger.info(`Waiting ${delaySec}s before next video...`);
								await sleep(delaySec * 1000, delaySec * 1000);
							}
						}
					}
				}

			} catch (err) {
				logger.error(`Error processing channel ${channelId}: ${err.message}`);
				// Detect bot-check at the channel/RSS level too
				if (err.message.includes('Sign in to confirm') || err.message.includes('confirm you') || err.message.includes('Requested format is not available')) {
					logger.warn('Bot-check / Shadowban detected at channel level! Aborting run to preserve cookies.');
					botDetected = true;
					newNotifications.push({
						id: `bot-check-${Date.now()}`,
						title: '⚠️ Cookie scaduti — Aggiorna i cookies',
						channelInfo: 'Sistema',
						timestamp: new Date().toISOString(),
						type: 'error',
						message: 'YouTube richiede il login o blocca i formati (Shadowban). Ricaricare cookies freschi su R2.'
					});
				}
			}

			// Adaptive delay between channels
			if (!botDetected && ci < shuffledChannels.length - 1) {
				const delaySec = Math.floor(Math.random() * (CHANNEL_DELAY[1] - CHANNEL_DELAY[0] + 1)) + CHANNEL_DELAY[0];
				logger.info(`Waiting ${delaySec}s before next channel...`);
				await sleep(delaySec * 1000, delaySec * 1000);
			}
		}

		if (botDetected) {
			logger.warn('Run aborted due to bot detection. Cookies may need renewal.');
		}

		// 4. Flush Notifications to R2
		if (newNotifications.length > 0) {
			try {
				let currentNotifications = [];
				try {
					const notifsData = await s3.send(new GetObjectCommand({ Bucket: R2_BUCKET_NAME, Key: 'system/notifications.json' }));
					const str = await notifsData.Body.transformToString();
					currentNotifications = JSON.parse(str);
				} catch (err) {
					// Either file doesn't exist or is invalid JSON
					logger.info("No existing notifications found or failed to parse, starting fresh.");
				}

				// Prepend new notifications
				currentNotifications.unshift(...newNotifications);

				// Cap at 100 items to avoid infinite growth
				if (currentNotifications.length > 100) {
					currentNotifications = currentNotifications.slice(0, 100);
				}

				await s3.send(new PutObjectCommand({
					Bucket: R2_BUCKET_NAME,
					Key: 'system/notifications.json',
					Body: JSON.stringify(currentNotifications),
					ContentType: 'application/json'
				}));
				logger.info(`Saved ${newNotifications.length} new notifications to system/notifications.json`);
			} catch (err) {
				logger.error(`Failed to flush notifications: ${err.message}`);
			}
		}

	} catch (error) {
		logger.error(`Prefetch critical error: ${error.message}`);
	} finally {
		await logger.save();
	}
};

// Schedule: Run every 3 hours
exports.handler = schedule("0 */3 * * *", prefetchHandler);
