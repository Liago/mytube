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

	const { date, functionName, logFile } = event.queryStringParameters || {};

	try {
		// Legacy: fetch a specific log file by name (kept for backward compat)
		if (logFile) {
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
		}

		// Aggregated daily logs for a specific function
		if (date && functionName) {
			return await fetchAggregatedLogs(date, functionName);
		}

		// List dates or list function summaries for a date
		const prefix = date ? `logs/${date}/` : "logs/";
		const commandOptions = {
			Bucket: R2_BUCKET_NAME,
			Prefix: prefix,
		};

		if (!date) {
			// List folders (dates)
			commandOptions.Delimiter = "/";
			const command = new ListObjectsV2Command(commandOptions);
			const response = await s3.send(command);

			const dates = (response.CommonPrefixes || [])
				.map(p => p.Prefix.replace('logs/', '').replace('/', ''))
				.sort((a, b) => b.localeCompare(a)); // Newest first

			return {
				statusCode: 200,
				body: JSON.stringify({ dates })
			};
		} else {
			// List all files for the date, then group by function
			const allFiles = await listAllFiles(date);

			// Group by functionName
			const groups = {};
			for (const file of allFiles) {
				if (!groups[file.functionName]) {
					groups[file.functionName] = {
						functionName: file.functionName,
						totalRuns: 0,
						files: []
					};
				}
				groups[file.functionName].totalRuns++;
				groups[file.functionName].files.push(file.filename);
			}

			const functions = Object.values(groups)
				.sort((a, b) => a.functionName.localeCompare(b.functionName));

			return {
				statusCode: 200,
				body: JSON.stringify({ functions })
			};
		}

	} catch (error) {
		console.error("Error fetching logs:", error);
		return {
			statusCode: 500,
			body: JSON.stringify({ error: error.message })
		};
	}
};

/**
 * List all log files for a given date, handling pagination.
 */
async function listAllFiles(date) {
	const prefix = `logs/${date}/`;
	let allFiles = [];
	let continuationToken = undefined;

	do {
		const commandOptions = {
			Bucket: R2_BUCKET_NAME,
			Prefix: prefix,
		};
		if (continuationToken) {
			commandOptions.ContinuationToken = continuationToken;
		}
		const response = await s3.send(new ListObjectsV2Command(commandOptions));

		const files = (response.Contents || [])
			.filter(obj => obj.Key !== prefix)
			.map(obj => {
				const parts = obj.Key.split('/');
				const filename = parts[parts.length - 1];
				const nameParts = filename.replace('.json', '').split('_');
				// format: functionName_timestamp_uuid.json
				const functionName = nameParts.slice(0, nameParts.length - 2).join('_');
				const timestamp = parseInt(nameParts[nameParts.length - 2], 10);
				return { filename, key: obj.Key, functionName, timestamp, size: obj.Size };
			});

		allFiles = allFiles.concat(files);
		continuationToken = response.IsTruncated ? response.NextContinuationToken : undefined;
	} while (continuationToken);

	return allFiles.sort((a, b) => b.timestamp - a.timestamp);
}

/**
 * Fetch all log files for a function on a given date, merge them into
 * a single aggregated response with runs sorted chronologically.
 */
async function fetchAggregatedLogs(date, functionName) {
	const allFiles = await listAllFiles(date);
	const functionFiles = allFiles
		.filter(f => f.functionName === functionName)
		.sort((a, b) => a.timestamp - b.timestamp); // Oldest first for chronological order

	if (functionFiles.length === 0) {
		return {
			statusCode: 200,
			body: JSON.stringify({
				functionName,
				date,
				runs: [],
				totalEntries: 0,
				totalErrors: 0,
				totalWarnings: 0
			})
		};
	}

	// Fetch all files in parallel
	const fetchPromises = functionFiles.map(async (file) => {
		const data = await s3.send(new GetObjectCommand({
			Bucket: R2_BUCKET_NAME,
			Key: file.key
		}));
		const bodyArray = await data.Body.transformToByteArray();
		const jsonString = new TextDecoder().decode(bodyArray);
		return JSON.parse(jsonString);
	});

	const logDetails = await Promise.all(fetchPromises);

	let totalEntries = 0;
	let totalErrors = 0;
	let totalWarnings = 0;

	const runs = logDetails.map(detail => {
		const entries = detail.logs || [];
		const errors = entries.filter(e => e.level === "ERROR").length;
		const warnings = entries.filter(e => e.level === "WARN").length;
		totalEntries += entries.length;
		totalErrors += errors;
		totalWarnings += warnings;

		return {
			startTime: detail.startTime,
			durationMs: detail.durationMs || 0,
			entryCount: entries.length,
			errorCount: errors,
			warningCount: warnings,
			entries
		};
	});

	return {
		statusCode: 200,
		headers: { 'Content-Type': 'application/json' },
		body: JSON.stringify({
			functionName,
			date,
			runs,
			totalEntries,
			totalErrors,
			totalWarnings
		})
	};
}
