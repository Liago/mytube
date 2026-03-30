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

		// 4. Handle POST (Update Queue)
		if (event.httpMethod === "POST") {
			const localQueue = JSON.parse(event.body);

			await s3.send(new PutObjectCommand({
				Bucket: R2_BUCKET_NAME,
				Key: QUEUE_FILE_KEY,
				Body: JSON.stringify(localQueue),
				ContentType: "application/json"
			}));

			return {
				statusCode: 200,
				body: JSON.stringify({ message: "Prefetch queue synced successfully", saved: localQueue })
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
