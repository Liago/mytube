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

// Helper: Run yt-dlp (Copied/Adapted from audio.js)
const runYtDlp = async (url, outputPath, cookiesPath) => {
	return new Promise((resolve, reject) => {
		// Locate yt-dlp binary (assuming it's in the same bin folder as audio.js expects or relative)
		// In Netlify, we extracted it to /tmp/yt-dlp usually, but here we might need to re-download or use what's available.
		// For simplicity, we assume we need to download it again if it's a fresh container.
		// CAUTION: Background functions might run on different instances.
		// We will try to use the one from the repo if committed, or download.
		// As a fallback, let's assume valid yt-dlp is present or downloadable.

		// For this implementation, we will try to use a relative path or standard linux path.
		// If we really need robustness, we should copy the "ensure binary" logic from audio.js 
		// But to keep this file clean, let's assume /var/task/bin/yt-dlp-linux exists or similar.
		// Actually, best to replicate the "download if missing" logic briefly.

		const binaryName = 'yt-dlp-linux';
		const binPath = path.join('/tmp', binaryName);

		// Check if binary exists, if not download (simplified version of audio.js logic)
		if (!fs.existsSync(binPath)) {
			// We can't easily download here without curl/fetch logic again. 
			// Ideally we should share code. For now, let's assume we can spawn 'curl'
			try {
				require('child_process').execSync(`curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o ${binPath} && chmod +x ${binPath}`);
			} catch (e) {
				return reject(new Error(`Failed to download yt-dlp: ${e.message}`));
			}
		}

		const args = [
			'--extract-audio',
			'--audio-format', 'm4a',
			'--output', outputPath,
			'--no-playlist',
			'--no-warnings',
			'--js-runtimes', `node:${process.execPath}`,
			url
		];

		if (cookiesPath && fs.existsSync(cookiesPath)) {
			args.push('--cookies', cookiesPath);
		}

		const processProc = spawn(binPath, args);

		processProc.on('close', (code) => {
			if (code === 0) resolve();
			else reject(new Error(`yt-dlp exited with code ${code}`));
		});
	});
};

const prefetchHandler = async (event) => {
	console.log("Starting Scheduled Prefetch...");

	try {
		// 1. Get Home Channels
		let channels = [];
		try {
			const data = await s3.send(new GetObjectCommand({ Bucket: R2_BUCKET_NAME, Key: PREFS_FILE_KEY }));
			const body = await data.Body.transformToString();
			channels = JSON.parse(body).channels || [];
		} catch (e) {
			console.log("No preferences found or error reading prefs:", e.message);
			return;
		}

		if (channels.length === 0) {
			console.log("No home channels to scan.");
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
