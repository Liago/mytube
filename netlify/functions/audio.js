const { S3Client, HeadObjectCommand, GetObjectCommand } = require("@aws-sdk/client-s3");
const { Upload } = require("@aws-sdk/lib-storage");
const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');

// Configuration from Environment Variables
const R2_ACCOUNT_ID = process.env.R2_ACCOUNT_ID;
const R2_ACCESS_KEY_ID = process.env.R2_ACCESS_KEY_ID;
const R2_SECRET_ACCESS_KEY = process.env.R2_SECRET_ACCESS_KEY;
const R2_BUCKET_NAME = process.env.R2_BUCKET_NAME || "mytube-audio";
const R2_PUBLIC_DOMAIN = process.env.R2_PUBLIC_DOMAIN || "https://r2.mytube.app";

const s3 = new S3Client({
	region: "auto",
	endpoint: `https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com`,
	credentials: {
		accessKeyId: R2_ACCESS_KEY_ID,
		secretAccessKey: R2_SECRET_ACCESS_KEY,
	},
});

const API_SECRET = process.env.API_SECRET;

exports.handler = async (event, context) => {
	// Security Check
	if (API_SECRET) {
		const token = event.headers['x-api-key'] || event.headers['X-Api-Key'];
		if (token !== API_SECRET) {
			return { statusCode: 401, body: JSON.stringify({ error: "Unauthorized" }) };
		}
	}

	const videoId = event.queryStringParameters.videoId;

	if (!videoId) {
		return {
			statusCode: 400,
			body: JSON.stringify({ error: "Missing videoId parameter" }),
		};
	}

	// Cache busting: using _v2 to ignore previous corrupted (double duration) uploads
	const fileKey = `${videoId}_v2.m4a`;
	const publicUrl = `${R2_PUBLIC_DOMAIN}/${fileKey}`;

	// 1. Check Cache
	try {
		const head = await s3.send(
			new HeadObjectCommand({
				Bucket: R2_BUCKET_NAME,
				Key: fileKey,
			})
		);

		// Check for empty files (failed uploads) logic
		if (head.ContentLength && head.ContentLength > 0) {
			console.log(`Cache HIT for ${videoId}`);
			return {
				statusCode: 307,
				headers: { Location: publicUrl },
				body: "",
			};
		} else {
			console.log(`Cache HIT for ${videoId} but file is empty (0 bytes). Re-downloading...`);
		}
	} catch (error) {
		if (error.name !== "NotFound") {
			console.error("Error checking cache:", error);
		}
		console.log(`Cache MISS for ${videoId}. Downloading with local yt-dlp binary...`);
	}

	// 2. Download to /tmp and Upload using standalone yt-dlp binary
	try {
		const netscapeCookiePath = path.resolve('/tmp', 'cookies.txt');
		let activeCookiePath = undefined;
		let hasCookies = false;

		// Helper: convert JSON cookies array to Netscape format string
		const convertToNetscape = (cookies) => {
			let netscapeContent = "# Netscape HTTP Cookie File\n";
			cookies.forEach(c => {
				const domain = c.domain;
				const includeSubdomains = domain.startsWith('.') ? 'TRUE' : 'FALSE';
				const cookiePath = c.path;
				const secure = c.secure ? 'TRUE' : 'FALSE';
				const expiration = c.expirationDate ? Math.round(c.expirationDate) : 0;
				const name = c.name;
				const value = c.value;

				netscapeContent += `${domain}\t${includeSubdomains}\t${cookiePath}\t${secure}\t${expiration}\t${name}\t${value}\n`;
			});
			return netscapeContent;
		};

		// Try loading cookies from R2 bucket (_cookies.json)
		try {
			console.log('Loading cookies from R2 bucket...');
			const cookieObj = await s3.send(new GetObjectCommand({
				Bucket: R2_BUCKET_NAME,
				Key: '_cookies.json',
			}));
			const chunks = [];
			for await (const chunk of cookieObj.Body) {
				chunks.push(chunk);
			}
			const cookieBody = Buffer.concat(chunks).toString('utf8');
			const cookies = JSON.parse(cookieBody);
			const netscapeContent = convertToNetscape(cookies);
			fs.writeFileSync(netscapeCookiePath, netscapeContent);
			console.log(`Cookies loaded from R2 (${cookies.length} cookies), saved to ${netscapeCookiePath}`);
			activeCookiePath = netscapeCookiePath;
			hasCookies = true;
		} catch (err) {
			if (err.name === 'NoSuchKey' || err.name === 'NotFound') {
				console.log('No _cookies.json found in R2 bucket');
			} else {
				console.error('Error loading cookies from R2:', err.message);
			}
		}

		// Fallback: try local cookies.json file
		if (!hasCookies) {
			const jsonCookiePath = path.resolve(process.cwd(), 'cookies.json');
			if (fs.existsSync(jsonCookiePath)) {
				console.log('Found local cookies.json, converting to Netscape format...');
				try {
					const jsonContent = fs.readFileSync(jsonCookiePath, 'utf8');
					const cookies = JSON.parse(jsonContent);
					const netscapeContent = convertToNetscape(cookies);
					fs.writeFileSync(netscapeCookiePath, netscapeContent);
					console.log('Converted cookies saved to', netscapeCookiePath);
					activeCookiePath = netscapeCookiePath;
					hasCookies = true;
				} catch (err) {
					console.error("Error converting cookies:", err);
				}
			}
		}

		if (!hasCookies) {
			console.log('WARNING: No cookies available. Upload _cookies.json to R2 bucket or provide local cookies.json');
		}

		// Prepare command: use local binary based on OS
		const isLinux = process.platform === 'linux';
		const binaryName = isLinux ? 'yt-dlp-linux' : 'yt-dlp';
		const binaryPath = path.resolve(process.cwd(), binaryName);

		// Use /tmp for temporary storage
		const tmpFilePath = path.resolve('/tmp', `${videoId}.m4a`);
		// Clean up previous run if exists
		if (fs.existsSync(tmpFilePath)) fs.unlinkSync(tmpFilePath);

		console.log(`OS: ${process.platform}, using binary: ${binaryName}`);

		if (!fs.existsSync(binaryPath)) {
			// Detailed error for debugging deployment
			const files = fs.readdirSync(process.cwd());
			console.error(`Binary not found at ${binaryPath}. Root files: ${files.join(', ')}`);
			throw new Error(`yt-dlp binary not found at ${binaryPath}`);
		}

		const args = [
			`https://www.youtube.com/watch?v=${videoId}`,
			'-f', '140/bestaudio[ext=m4a]/bestaudio', // itag 140 preferred, fallback to best m4a/audio
			'-o', tmpFilePath,     // Output to file in /tmp
			'--force-overwrites',
			'--no-warnings',
			'--referer', 'https://www.youtube.com/',
			'--user-agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
			'--write-info-json' // Extract metadata
		];

		if (hasCookies && activeCookiePath) {
			args.push('--cookies', activeCookiePath);
		}

		console.log(`Spawning: ${binaryPath} ${args.join(' ')}`);

		const child = spawn(binaryPath, args, {
			stdio: ['ignore', 'pipe', 'pipe']
		});

		// Handle stderr
		let stderrOutput = '';
		child.stderr.on('data', (data) => {
			stderrOutput += data.toString();
			console.error(`yt-dlp stderr: ${data}`);
		});

		// Wait for download to finish
		await new Promise((resolve, reject) => {
			child.on('exit', (code) => {
				if (code === 0) resolve();
				else reject(new Error(`yt-dlp exited with code ${code}. Stderr: ${stderrOutput}`));
			});
			child.on('error', (err) => reject(err));
		});

		// Verify file exists
		if (!fs.existsSync(tmpFilePath)) {
			throw new Error("Download finished successfully but file was not created at " + tmpFilePath);
		}

		const fileStream = fs.createReadStream(tmpFilePath);
		const stats = fs.statSync(tmpFilePath);

		// Upload Audio and Metadata in parallel
		const uploads = [];

		// 1. Audio Upload
		const audioUpload = new Upload({
			client: s3,
			params: {
				Bucket: R2_BUCKET_NAME,
				Key: fileKey,
				Body: fileStream,
				ContentType: "audio/mp4",
				ContentLength: stats.size
			},
		});
		uploads.push(audioUpload.done());

		// 2. Metadata Upload (if exists)
		// yt-dlp typically keys infojson as filename.info.json
		// Since we explicitly set output to tmpFilePath (.m4a), it likely appends or replaces.
		// Usually: id.m4a -> id.info.json
		const possibleMetaPath = tmpFilePath.replace(/\.m4a$/, '.info.json');

		if (fs.existsSync(possibleMetaPath)) {
			console.log(`Found metadata at ${possibleMetaPath}, uploading...`);
			const metaStream = fs.createReadStream(possibleMetaPath);
			const metaUpload = new Upload({
				client: s3,
				params: {
					Bucket: R2_BUCKET_NAME,
					Key: `${videoId}.json`, // Clean key
					Body: metaStream,
					ContentType: "application/json",
				},
			});
			uploads.push(metaUpload.done().then(() => {
				// Cleanup metadata immediately
				try { fs.unlinkSync(possibleMetaPath); } catch (e) { }
			}));
		} else {
			console.log(`Metadata file not found at ${possibleMetaPath}`);
		}

		await Promise.all(uploads);

		// Cleanup /tmp
		try {
			fs.unlinkSync(tmpFilePath);
		} catch (e) {
			console.warn("Failed to cleanup tmp file:", e);
		}

		console.log(`Upload complete for ${videoId}`);

		return {
			statusCode: 307,
			headers: { Location: publicUrl },
			body: "",
		};
	} catch (error) {
		console.error(`Error processing ${videoId}:`, error);
		return {
			statusCode: 500,
			body: JSON.stringify({ error: error.message }),
		};
	}
};
