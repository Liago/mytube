const { S3Client, HeadObjectCommand } = require("@aws-sdk/client-s3");

const R2_ACCOUNT_ID = process.env.R2_ACCOUNT_ID;
const R2_ACCESS_KEY_ID = process.env.R2_ACCESS_KEY_ID;
const R2_SECRET_ACCESS_KEY = process.env.R2_SECRET_ACCESS_KEY;
const R2_BUCKET_NAME = process.env.R2_BUCKET_NAME || "mytube-audio";

const s3 = new S3Client({
	region: "auto",
	endpoint: `https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com`,
	credentials: {
		accessKeyId: R2_ACCESS_KEY_ID,
		secretAccessKey: R2_SECRET_ACCESS_KEY,
	},
});

exports.handler = async (event, context) => {
	// Only allow POST or GET with ids param
	let videoIds = [];

	if (event.httpMethod === "POST") {
		try {
			const body = JSON.parse(event.body);
			videoIds = body.ids || [];
		} catch (e) {
			return { statusCode: 400, body: JSON.stringify({ error: "Invalid JSON" }) };
		}
	} else if (event.queryStringParameters.ids) {
		videoIds = event.queryStringParameters.ids.split(',');
	}

	if (!videoIds.length) {
		return { statusCode: 400, body: JSON.stringify({ error: "No video IDs provided" }) };
	}

	// Limit batch size
	if (videoIds.length > 50) videoIds = videoIds.slice(0, 50);

	const found = [];
	const missing = [];

	// Check R2 for each ID in parallel
	await Promise.all(videoIds.map(async (id) => {
		const fileKey = `${id}_v2.m4a`;
		try {
			await s3.send(new HeadObjectCommand({
				Bucket: R2_BUCKET_NAME,
				Key: fileKey,
			}));
			found.push(id);
		} catch (error) {
			missing.push(id);
		}
	}));

	return {
		statusCode: 200,
		headers: {
			"Content-Type": "application/json",
			"Access-Control-Allow-Origin": "*", // Enable CORS for iOS app
			"Access-Control-Allow-Headers": "Content-Type",
			"Access-Control-Allow-Methods": "GET, POST, OPTIONS"
		},
		body: JSON.stringify({ found, missing }),
	};
};
