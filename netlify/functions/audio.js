const { S3Client, HeadObjectCommand } = require("@aws-sdk/client-s3");
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

exports.handler = async (event, context) => {
	const videoId = event.queryStringParameters.videoId;

	if (!videoId) {
		return {
			statusCode: 400,
			body: JSON.stringify({ error: "Missing videoId parameter" }),
		};
	}

	const fileKey = `${videoId}.m4a`;
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
		let activeCookiePath = undefined;
		let hasCookies = false;

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
			'-f', '140',           // Force AAC/m4a (itag 140)
			'-o', tmpFilePath,     // Output to file in /tmp
			'--force-overwrites',
			'--quiet',
			'--no-warnings',
			'--referer', 'https://www.youtube.com/'
		];

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

		// Upload to R2 from File Stream
		const parallelUploads3 = new Upload({
			client: s3,
			params: {
				Bucket: R2_BUCKET_NAME,
				Key: fileKey,
				Body: fileStream,
				ContentType: "audio/mp4",
				ContentLength: stats.size
			},
		});

		await parallelUploads3.done();

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
