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

const LOG_RETENTION_DAYS = 7;
const AUDIO_RETENTION_DAYS = 2;

const handler = async (event, context) => {
	const Logger = require('./lib/logger');
	const logger = new Logger('cleanup');

	logger.info("Starting daily cleanup...");

	try {
		let isTruncated = true;
		let continuationToken = undefined;
		let deletedAudioCount = 0;
		let deletedLogCount = 0;

		const audioThreshold = new Date();
		audioThreshold.setDate(audioThreshold.getDate() - AUDIO_RETENTION_DAYS);

		const logThreshold = new Date();
		logThreshold.setDate(logThreshold.getDate() - LOG_RETENTION_DAYS);

		while (isTruncated) {
			const command = new ListObjectsV2Command({
				Bucket: R2_BUCKET_NAME,
				ContinuationToken: continuationToken
			});

			const response = await s3.send(command);
			const contents = response.Contents || [];

			// Old audio/media files (older than 2 days, skip system/ and logs/)
			const oldAudioFiles = contents.filter(obj => {
				const isSystemFile = obj.Key.startsWith("system/");
				const isLogFile = obj.Key.startsWith("logs/");
				return !isSystemFile && !isLogFile && obj.LastModified < audioThreshold;
			});

			// Old log files (older than 7 days)
			const oldLogFiles = contents.filter(obj => {
				return obj.Key.startsWith("logs/") && obj.LastModified < logThreshold;
			});

			const filesToDelete = [...oldAudioFiles, ...oldLogFiles];

			if (filesToDelete.length > 0) {
				const deleteParams = {
					Bucket: R2_BUCKET_NAME,
					Delete: {
						Objects: filesToDelete.map(obj => ({ Key: obj.Key })),
						Quiet: true
					}
				};

				await s3.send(new DeleteObjectsCommand(deleteParams));
				deletedAudioCount += oldAudioFiles.length;
				deletedLogCount += oldLogFiles.length;

				if (oldAudioFiles.length > 0) {
					logger.info(`Deleted ${oldAudioFiles.length} audio files.`);
				}
				if (oldLogFiles.length > 0) {
					logger.info(`Deleted ${oldLogFiles.length} log files.`);
				}
			}

			isTruncated = response.IsTruncated;
			continuationToken = response.NextContinuationToken;
		}

		logger.info(`Cleanup complete. Audio deleted: ${deletedAudioCount}, Logs deleted: ${deletedLogCount}`);

		return {
			statusCode: 200,
			body: JSON.stringify({
				message: "Cleanup complete",
				deletedAudio: deletedAudioCount,
				deletedLogs: deletedLogCount
			}),
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
