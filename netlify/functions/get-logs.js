const { S3Client, ListObjectsV2Command, GetObjectCommand } = require("@aws-sdk/client-s3");

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

	const { date, logFile } = event.queryStringParameters || {};

	try {
		if (logFile) {
			// Fetch specific log content
			const data = await s3.send(new GetObjectCommand({
				Bucket: R2_BUCKET_NAME,
				Key: `logs/${date}/${logFile}`
			}));
			const bodyArray = await data.Body.transformToByteArray();
			const jsonString = new TextDecoder().decode(bodyArray);
			return {
				statusCode: 200,
				headers: { 'Content-Type': 'application/json' },
				body: jsonString
			};
		} else {
			// List dates or list files for a date
			const prefix = date ? `logs/${date}/` : "logs/";
			const commandOptions = {
				Bucket: R2_BUCKET_NAME,
				Prefix: prefix,
			};

			if (!date) {
				// We want to list folders (dates)
				commandOptions.Delimiter = "/";
			}

			const command = new ListObjectsV2Command(commandOptions);
			const response = await s3.send(command);

			if (!date) {
				// Return available dates
				const dates = (response.CommonPrefixes || [])
					.map(p => p.Prefix.replace('logs/', '').replace('/', ''))
					.sort((a, b) => b.localeCompare(a)); // Newest first

				return {
					statusCode: 200,
					body: JSON.stringify({ dates })
				};
			} else {
				// Return files for the specific date
				const files = (response.Contents || [])
					.filter(obj => obj.Key !== prefix) // Exclude the folder itself if returned
					.map(obj => {
						const parts = obj.Key.split('/');
						const filename = parts[parts.length - 1];
						const nameParts = filename.replace('.json', '').split('_');
						// format: functionName_timestamp_uuid.json
						const functionName = nameParts.slice(0, nameParts.length - 2).join('_');
						const timestamp = parseInt(nameParts[nameParts.length - 2], 10);

						return {
							filename,
							key: obj.Key,
							functionName,
							timestamp,
							size: obj.Size
						};
					})
					.sort((a, b) => b.timestamp - a.timestamp); // Newest first

				return {
					statusCode: 200,
					body: JSON.stringify({ files })
				};
			}
		}

	} catch (error) {
		console.error("Error fetching logs:", error);
		return {
			statusCode: 500,
			body: JSON.stringify({ error: error.message })
		};
	}
};
