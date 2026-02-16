#!/usr/bin/env node
/**
 * Setup OAuth token for yt-dlp and upload it to R2.
 *
 * This script:
 * 1. Runs yt-dlp --username oauth2 --password "" to trigger OAuth flow
 * 2. Opens your browser for Google authorization
 * 3. Reads the generated token from yt-dlp cache
 * 4. Uploads it to R2 as system/_oauth_token.json
 *
 * Usage: node setup-oauth.js
 *
 * Requires:
 *   - yt-dlp binary in project root
 *   - R2 credentials in .env
 */

const fs = require('fs');
const path = require('path');
const { execSync, spawnSync } = require('child_process');
const os = require('os');

// Load .env if present
const envPath = path.resolve(__dirname, '.env');
if (fs.existsSync(envPath)) {
	const envContent = fs.readFileSync(envPath, 'utf8');
	envContent.split('\n').forEach(line => {
		const match = line.match(/^\s*([\w]+)\s*=\s*(.*)$/);
		if (match && !process.env[match[1]]) {
			process.env[match[1]] = match[2].replace(/^["']|["']$/g, '');
		}
	});
}

const { S3Client, PutObjectCommand } = require("@aws-sdk/client-s3");

const R2_ACCOUNT_ID = process.env.R2_ACCOUNT_ID;
const R2_ACCESS_KEY_ID = process.env.R2_ACCESS_KEY_ID;
const R2_SECRET_ACCESS_KEY = process.env.R2_SECRET_ACCESS_KEY;
const R2_BUCKET_NAME = process.env.R2_BUCKET_NAME || "mytube-audio";

if (!R2_ACCOUNT_ID || !R2_ACCESS_KEY_ID || !R2_SECRET_ACCESS_KEY) {
	console.error('Missing R2 credentials. Set R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY in .env');
	process.exit(1);
}

const s3 = new S3Client({
	region: "auto",
	endpoint: `https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com`,
	credentials: {
		accessKeyId: R2_ACCESS_KEY_ID,
		secretAccessKey: R2_SECRET_ACCESS_KEY,
	},
});

// Find yt-dlp cache directory
function findCacheDir() {
	const platform = os.platform();
	if (platform === 'darwin') {
		return path.join(os.homedir(), 'Library', 'Caches', 'yt-dlp');
	} else if (platform === 'linux') {
		return path.join(os.homedir(), '.cache', 'yt-dlp');
	} else if (platform === 'win32') {
		return path.join(process.env.APPDATA || '', 'yt-dlp');
	}
	return path.join(os.homedir(), '.cache', 'yt-dlp');
}

async function main() {
	const binaryPath = path.resolve(__dirname, 'yt-dlp');

	if (!fs.existsSync(binaryPath)) {
		console.error(`yt-dlp binary not found at ${binaryPath}`);
		process.exit(1);
	}

	console.log('=== MyTube OAuth Setup ===');
	console.log('');
	console.log('This will open your browser for Google OAuth authorization.');
	console.log('Please sign in with a YouTube account and authorize access.');
	console.log('');

	// Step 1: Run yt-dlp with OAuth to trigger the flow
	// We use a known video to trigger the auth flow
	console.log('Starting yt-dlp OAuth flow...');
	console.log('(Follow the instructions in your browser/terminal)\n');

	const result = spawnSync(binaryPath, [
		'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
		'--username', 'oauth2',
		'--password', '',
		'--skip-download',
		'--print', 'title',
	], {
		stdio: 'inherit', // Show yt-dlp output directly to user
		timeout: 120000,  // 2 minute timeout for OAuth flow
	});

	if (result.status !== 0) {
		console.error('\nOAuth flow failed. Please try again.');
		if (result.error) console.error('Error:', result.error.message);
		process.exit(1);
	}

	console.log('\nOAuth flow completed successfully!');

	// Step 2: Find the token file in yt-dlp cache
	const cacheDir = findCacheDir();
	const tokenPath = path.join(cacheDir, 'youtube-oauth2-token.json');

	console.log(`Looking for token at: ${tokenPath}`);

	if (!fs.existsSync(tokenPath)) {
		// Try alternative locations
		const altPaths = [
			path.join(cacheDir, 'youtube-oauth2-token.json'),
			path.join(os.homedir(), '.yt-dlp', 'youtube-oauth2-token.json'),
		];

		let found = false;
		for (const alt of altPaths) {
			if (fs.existsSync(alt)) {
				console.log(`Found token at: ${alt}`);
				found = true;
				break;
			}
		}

		if (!found) {
			console.error('OAuth token file not found. Searched in:');
			console.error(`  - ${tokenPath}`);
			altPaths.forEach(p => console.error(`  - ${p}`));
			console.error('\nPlease check your yt-dlp cache directory manually.');

			// List cache dir contents for debugging
			if (fs.existsSync(cacheDir)) {
				console.error(`\nContents of ${cacheDir}:`);
				try {
					const files = fs.readdirSync(cacheDir, { recursive: true });
					files.forEach(f => console.error(`  ${f}`));
				} catch (e) {
					console.error('  (could not list directory)');
				}
			}
			process.exit(1);
		}
	}

	// Step 3: Read the token and upload to R2
	const tokenContent = fs.readFileSync(tokenPath, 'utf8');
	const tokenData = JSON.parse(tokenContent);

	console.log(`Token loaded (expires: ${tokenData.expires || 'unknown'})`);

	await s3.send(new PutObjectCommand({
		Bucket: R2_BUCKET_NAME,
		Key: 'system/_oauth_token.json',
		Body: tokenContent,
		ContentType: 'application/json',
	}));

	console.log(`\n✅ OAuth token uploaded to R2 bucket "${R2_BUCKET_NAME}" as system/_oauth_token.json`);
	console.log('The token will auto-refresh. No need to repeat this unless it gets revoked.');
}

main().catch(err => {
	console.error('Setup failed:', err.message);
	process.exit(1);
});
