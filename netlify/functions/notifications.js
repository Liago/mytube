const { S3Client, GetObjectCommand } = require("@aws-sdk/client-s3");

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

exports.handler = async (event, context) => {
	// Security Check
	if (API_SECRET) {
		const token = event.headers['x-api-key'] || event.headers['X-Api-Key'];
		if (token !== API_SECRET) {
			return { statusCode: 401, body: JSON.stringify({ error: "Unauthorized" }) };
		}
	}

	try {
		const command = new GetObjectCommand({
			Bucket: R2_BUCKET_NAME,
			Key: "system/notifications.json"
		});

		const data = await s3.send(command);
		const bodyArray = await data.Body.transformToByteArray();
		const jsonString = new TextDecoder().decode(bodyArray);

		return {
			statusCode: 200,
			headers: { 'Content-Type': 'application/json' },
			body: jsonString
		};
	} catch (error) {
		if (error.name === 'NoSuchKey') {
			return {
				statusCode: 200,
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify([])
			};
		}

		console.error("Error fetching notifications:", error);
		return {
			statusCode: 500,
			body: JSON.stringify({ error: error.message })
		};
	}
};
