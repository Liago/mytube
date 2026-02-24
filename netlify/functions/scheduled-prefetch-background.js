const { S3Client, GetObjectCommand, PutObjectCommand, HeadObjectCommand } = require("@aws-sdk/client-s3");
const { schedule } = require('@netlify/functions');
const Parser = require('rss-parser');
const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');
const parser = new Parser();

// Configuration
const R2_ACCOUNT_ID = process.env.R2_ACCOUNT_ID;
const R2_ACCESS_KEY_ID = process.env.R2_ACCESS_KEY_ID;
const R2_SECRET_ACCESS_KEY = process.env.R2_SECRET_ACCESS_KEY;
const R2_BUCKET_NAME = process.env.R2_BUCKET_NAME || "mytube-audio";
const PREFS_FILE_KEY = "system/home_channels.json";

const s3 = new S3Client({
	region: "auto",
	endpoint: `https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com`,
	credentials: {
		accessKeyId: R2_ACCESS_KEY_ID,
		secretAccessKey: R2_SECRET_ACCESS_KEY,
	},
});

const runYtDlp = async (url, outputPath, cookiesPath) => {
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
				'-f', '140/bestaudio[ext=m4a]/bestaudio',
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

			if (process.env.PROXY_URL && !process.env.PROXY_URL.includes('user:pass@host:port')) {
				args.push('--proxy', process.env.PROXY_URL);
			}

			const processProc = spawn(binPath, args, { stdio: ['ignore', 'pipe', 'pipe'] });

			let stderrOutput = '';
			processProc.stderr.on('data', (data) => {
				stderrOutput += data.toString();
			});

			processProc.on('close', (code) => {
				if (code === 0) resolve();
				else reject(new Error(`yt-dlp exited with code ${code}. Stderr: ${stderrOutput}`));
			});
		});
	};

	let downloadSuccess = false;
	let downloadError = null;
	const hasCookies = cookiesPath && fs.existsSync(cookiesPath);

	const strategies = [];
	if (hasCookies) {
		strategies.push({ useCookies: true, playerClient: 'ios' });
		strategies.push({ useCookies: true, playerClient: 'android_creator' });
		strategies.push({ useCookies: true, playerClient: 'web' });
		strategies.push({ useCookies: false, playerClient: 'tv_embedded' });
		strategies.push({ useCookies: true, playerClient: 'tv_embedded' });
		strategies.push({ useCookies: false, playerClient: 'android' });
		strategies.push({ useCookies: true, playerClient: 'mweb' });
	} else {
		for (const client of PLAYER_CLIENTS) {
			strategies.push({ useCookies: false, playerClient: client });
		}
	}

	const MAX_ATTEMPTS = 6;
	const cappedStrategies = strategies.slice(0, MAX_ATTEMPTS);

	for (const strategy of cappedStrategies) {
		if (downloadSuccess) break;
		try {
			console.log(`Trying strategy client=${strategy.playerClient}, cookies=${strategy.useCookies}`);
			await executeStrategy(strategy.useCookies, strategy.playerClient);
			downloadSuccess = true;
			console.log(`Success with strategy client=${strategy.playerClient}`);
		} catch (err) {
			console.warn(`Strategy failed: ${err.message}`);
			downloadError = err;
		}
	}

	if (!downloadSuccess) {
		throw downloadError || new Error("All download strategies exhausted");
	}
};

const prefetchHandler = async (event) => {
	console.log("Starting Scheduled Prefetch...");

	try {
		let channels = [];
		try {
			const data = await s3.send(new GetObjectCommand({ Bucket: R2_BUCKET_NAME, Key: PREFS_FILE_KEY }));
			const body = await data.Body.transformToString();
			const prefs = JSON.parse(body);
			// Use prefetchChannels if present, fallback to channels for retrocompatibility
			channels = prefs.prefetchChannels || prefs.channels || [];
		} catch (e) {
			console.log("No preferences found or error reading prefs:", e.message);
			return;
		}

		if (channels.length === 0) {
			console.log("No prefetch channels to scan.");
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
				return `${domain}\tTRUE\t${c.path}\t${c.secure ? 'TRUE' : 'FALSE'}\t${c.expirationDate || 0}\t${c.name}\t${c.value}`;
			}).join('\n');
			fs.writeFileSync(cookiesPath, '# Netscape HTTP Cookie File\n' + netscapeCookies);

		} catch (e) {
			console.log("Could not load/convert cookies:", e.message);
			// Continue without cookies? Might fail for some videos.
		}

		// 3. Scan & Download
		for (const channelId of channels) {
			console.log(`Scanning channel: ${channelId}`);
			try {
				const feed = await parser.parseURL(`https://www.youtube.com/feeds/videos.xml?channel_id=${channelId}`);

				// Check last 3 videos
				const videosToCheck = feed.items.slice(0, 3);

				for (const video of videosToCheck) {
					const videoId = video.id.replace('yt:video:', '');
					const r2Key = `${videoId}_v2.m4a`;

					// Check availability
					try {
						await s3.send(new HeadObjectCommand({ Bucket: R2_BUCKET_NAME, Key: r2Key }));
						console.log(`Video ${videoId} already exists. Skipping.`);
					} catch (e) {
						if (e.name === 'NotFound' || e.name === '404') {
							console.log(`Video ${videoId} missing. Downloading...`);

							// Download
							const tempPath = `/tmp/${videoId}.m4a`;
							await runYtDlp(video.link, tempPath, fs.existsSync(cookiesPath) ? cookiesPath : null);

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
								console.log(`Uploaded ${videoId} to R2.`);
								fs.unlinkSync(tempPath); // Cleanup
							}
						}
					}
				}

			} catch (err) {
				console.error(`Error processing channel ${channelId}:`, err.message);
			}
		}

	} catch (error) {
		console.error("Prefetch critical error:", error);
	}
};

// Schedule: Run every 6 hours
exports.handler = schedule("0 */6 * * *", prefetchHandler);
