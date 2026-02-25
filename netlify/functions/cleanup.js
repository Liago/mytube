const { S3Client, ListObjectsV2Command, DeleteObjectsCommand } = require("@aws-sdk/client-s3");
const { schedule } = require("@netlify/functions");

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

const handler = async (event, context) => {
	const Logger = require('./lib/logger');
	const logger = new Logger('cleanup');

	logger.info("Starting daily cleanup...");

	try {
		// List all objects
		let isTruncated = true;
		let continuationToken = undefined;
		let deletedCount = 0;
		const thresholdDate = new Date();
		thresholdDate.setDate(thresholdDate.getDate() - 2);

		while (isTruncated) {
			const command = new ListObjectsV2Command({
				Bucket: R2_BUCKET_NAME,
				ContinuationToken: continuationToken
			});

			const response = await s3.send(command);
			const contents = response.Contents || [];

			// Filter old files, preserving "system/" and "logs/" directory
			const oldFiles = contents.filter(obj => {
				const isSystemFile = obj.Key.startsWith("system/");
				const isLogFile = obj.Key.startsWith("logs/");
				const isOld = obj.LastModified < thresholdDate;
				return !isSystemFile && !isLogFile && isOld;
			});

			if (oldFiles.length > 0) {
				const deleteParams = {
					Bucket: R2_BUCKET_NAME,
					Delete: {
						Objects: oldFiles.map(obj => ({ Key: obj.Key })),
						Quiet: true
					}
				};

				await s3.send(new DeleteObjectsCommand(deleteParams));
				deletedCount += oldFiles.length;
				logger.info(`Deleted ${oldFiles.length} files.`);
			}

			isTruncated = response.IsTruncated;
			continuationToken = response.NextContinuationToken;
		}

		logger.info(`Cleanup complete. Total deleted: ${deletedCount}`);

		return {
			statusCode: 200,
			body: JSON.stringify({ message: "Cleanup complete", deleted: deletedCount }),
		};

	} catch (error) {
		logger.error(`Cleanup failed: ${error.message}`);
		return {
			statusCode: 500,
			body: JSON.stringify({ error: error.message }),
		};
	} finally {
		await logger.save();
	}
};

// Schedule: Daily at midnight
exports.handler = schedule("0 0 * * *", handler);
