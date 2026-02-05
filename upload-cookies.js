#!/usr/bin/env node
/**
 * Upload cookies.json to R2 bucket for YouTube authentication.
 *
 * Usage: node upload-cookies.js [path-to-cookies.json]
 *
 * Requires these env vars (from .env or exported):
 *   R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_BUCKET_NAME
 */

const fs = require('fs');
const path = require('path');

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
	console.error('Missing R2 credentials. Set R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY env vars or add them to .env');
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

async function main() {
	const cookiePath = process.argv[2] || path.resolve(__dirname, 'cookies.json');

	if (!fs.existsSync(cookiePath)) {
		console.error(`File not found: ${cookiePath}`);
		console.error('Usage: node upload-cookies.js [path-to-cookies.json]');
		process.exit(1);
	}

	const content = fs.readFileSync(cookiePath, 'utf8');
	const cookies = JSON.parse(content);
	console.log(`Read ${cookies.length} cookies from ${cookiePath}`);

	await s3.send(new PutObjectCommand({
		Bucket: R2_BUCKET_NAME,
		Key: 'system/_cookies.json',
		Body: content,
		ContentType: 'application/json',
	}));

	console.log(`Uploaded to R2 bucket "${R2_BUCKET_NAME}" as system/_cookies.json`);
}

main().catch(err => {
	console.error('Upload failed:', err.message);
	process.exit(1);
});
