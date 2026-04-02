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

const QUEUE_FILE_KEY = "system/prefetch_queue.json";

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
		const getRemoteQueue = async () => {
			try {
				const data = await s3.send(new GetObjectCommand({
					Bucket: R2_BUCKET_NAME,
					Key: QUEUE_FILE_KEY
				}));
				const chunks = [];
				for await (const chunk of data.Body) {
					chunks.push(chunk);
				}
				return JSON.parse(Buffer.concat(chunks).toString('utf8'));
			} catch (e) {
				if (e.name === 'NoSuchKey' || e.name === 'NotFound') {
					return { items: [] };
				}
				throw e;
			}
		};

		// 3. Handle GET (Read Queue)
		if (event.httpMethod === "GET") {
			const queue = await getRemoteQueue();
			return {
				statusCode: 200,
				body: JSON.stringify(queue)
			};
		}

		// 4. Handle POST (Merge & Update Queue)
		if (event.httpMethod === "POST") {
			const localPayload = JSON.parse(event.body);
			const localItems = localPayload.items || [];
			const clientLastSync = new Date(localPayload.lastUpdated || 0).getTime();

			const remoteQueue = await getRemoteQueue();
			const remoteItems = remoteQueue.items || [];

			// Build local map by videoId
			const localMap = {};
			localItems.forEach(item => { localMap[item.videoId] = item; });

			const mergedMap = {};

			// Add all local items (client's current state)
			for (const item of localItems) {
				mergedMap[item.videoId] = item;
			}

			// Add remote items not in local — only if added after this client's last sync
			for (const item of remoteItems) {
				if (!localMap[item.videoId]) {
					const itemAddedAt = new Date(item.addedAt).getTime();
					if (itemAddedAt > clientLastSync) {
						mergedMap[item.videoId] = item;
					}
				}
			}

			const mergedItems = Object.values(mergedMap);
			const now = new Date().toISOString();
			const mergedQueue = { items: mergedItems, lastUpdated: now };

			await s3.send(new PutObjectCommand({
				Bucket: R2_BUCKET_NAME,
				Key: QUEUE_FILE_KEY,
				Body: JSON.stringify(mergedQueue),
				ContentType: "application/json"
			}));

			return {
				statusCode: 200,
				body: JSON.stringify(mergedQueue)
			};
		}

		return { statusCode: 405, body: "Method Not Allowed" };

	} catch (error) {
		console.error("Sync prefetch queue error:", error);
		return {
			statusCode: 500,
			body: JSON.stringify({ error: error.message })
		};
	}
};
