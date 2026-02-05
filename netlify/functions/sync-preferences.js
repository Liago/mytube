const { S3Client, GetObjectCommand, PutObjectCommand } = require("@aws-sdk/client-s3");

// Configuration
const R2_ACCOUNT_ID = process.env.R2_ACCOUNT_ID;
const R2_ACCESS_KEY_ID = process.env.R2_ACCESS_KEY_ID;
const R2_SECRET_ACCESS_KEY = process.env.R2_SECRET_ACCESS_KEY;
const R2_BUCKET_NAME = process.env.R2_BUCKET_NAME || "mytube-audio";
const API_SECRET = process.env.API_SECRET;

const s3 = new S3Client({
	region: "auto",
	endpoint: `https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com`,
	credentials: {
		accessKeyId: R2_ACCESS_KEY_ID,
		secretAccessKey: R2_SECRET_ACCESS_KEY,
	},
});

const PREFS_FILE_KEY = "home_channels.json";

exports.handler = async (event, context) => {
	// 1. Security Check
	if (API_SECRET) {
		const token = event.headers['x-api-key'] || event.headers['X-Api-Key'];
		if (token !== API_SECRET) {
			return { statusCode: 401, body: JSON.stringify({ error: "Unauthorized" }) };
		}
	}

	try {
		// 2. Fetch Helper
		const getRemotePrefs = async () => {
			try {
				const data = await s3.send(new GetObjectCommand({
					Bucket: R2_BUCKET_NAME,
					Key: PREFS_FILE_KEY
				}));
				const chunks = [];
				for await (const chunk of data.Body) {
					chunks.push(chunk);
				}
				return JSON.parse(Buffer.concat(chunks).toString('utf8'));
			} catch (e) {
				if (e.name === 'NoSuchKey' || e.name === 'NotFound') {
					return { channels: [] }; // Default empty
				}
				throw e;
			}
		};

		// 3. Handle GET (Read Prefs)
		if (event.httpMethod === "GET") {
			const prefs = await getRemotePrefs();
			return {
				statusCode: 200,
				body: JSON.stringify(prefs)
			};
		}

		// 4. Handle POST (Update Prefs)
		if (event.httpMethod === "POST") {
			// Expecting { channels: ["ID1", "ID2"] }
			const localPrefs = JSON.parse(event.body);

			// For preferences, we can assume the latest client push is authoritative "for now"
			// OR we can try to merge. But for a toggle list, usually the last action wins.
			// Let's just save what the client sends, assuming client already did a merge if needed (or just blindly saving).
			// To support multi-device better, client should GET first, modify, then POST.
			// But for simplicity of this step: Save what we get.

			await s3.send(new PutObjectCommand({
				Bucket: R2_BUCKET_NAME,
				Key: PREFS_FILE_KEY,
				Body: JSON.stringify(localPrefs),
				ContentType: "application/json"
			}));

			return {
				statusCode: 200,
				body: JSON.stringify({ message: "Preferences synced successfully", saved: localPrefs })
			};
		}

		return { statusCode: 405, body: "Method Not Allowed" };

	} catch (error) {
		console.error("Sync error:", error);
		return {
			statusCode: 500,
			body: JSON.stringify({ error: error.message })
		};
	}
};
