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

const HISTORY_FILE_KEY = "system/history.json";

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
		const getRemoteHistory = async () => {
			try {
				const data = await s3.send(new GetObjectCommand({
					Bucket: R2_BUCKET_NAME,
					Key: HISTORY_FILE_KEY
				}));
				const chunks = [];
				for await (const chunk of data.Body) {
					chunks.push(chunk);
				}
				return JSON.parse(Buffer.concat(chunks).toString('utf8'));
			} catch (e) {
				if (e.name === 'NoSuchKey' || e.name === 'NotFound') {
					return {}; // Return empty object if no history exists yet
				}
				throw e;
			}
		};

		// 3. Handle GET (Read History)
		if (event.httpMethod === "GET") {
			const history = await getRemoteHistory();
			return {
				statusCode: 200,
				body: JSON.stringify(history)
			};
		}

		// 4. Handle POST (Merge & Update History)
		if (event.httpMethod === "POST") {
			const localHistory = JSON.parse(event.body); // Expecting { videoId: { ...VideoStatus... } }
			const remoteHistory = await getRemoteHistory();

			// Merge Strategy: "Latest Update Wins"
			// We iterate over the incoming local history and update remote if local is newer
			// OR if remote doesn't have it.
			// Note: We also need to keep what's in remote that isn't in local (which is implicit since we start with remote)

			const mergedHistory = { ...remoteHistory };

			for (const [videoId, localStatus] of Object.entries(localHistory)) {
				const remoteStatus = mergedHistory[videoId];

				if (!remoteStatus) {
					// New entry
					mergedHistory[videoId] = localStatus;
				} else {
					// Conflict: Compare timestamps
					// Ensure we handle date strings correctly
					const localTime = new Date(localStatus.lastUpdated).getTime();
					const remoteTime = new Date(remoteStatus.lastUpdated).getTime();

					if (localTime > remoteTime) {
						mergedHistory[videoId] = localStatus;
					}
				}
			}

			// Save back to R2
			await s3.send(new PutObjectCommand({
				Bucket: R2_BUCKET_NAME,
				Key: HISTORY_FILE_KEY,
				Body: JSON.stringify(mergedHistory),
				ContentType: "application/json"
			}));

			return {
				statusCode: 200,
				body: JSON.stringify({ message: "History synced successfully", merged: mergedHistory })
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
