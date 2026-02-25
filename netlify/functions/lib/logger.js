const { S3Client, PutObjectCommand } = require("@aws-sdk/client-s3");
const crypto = require("crypto");

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

class Logger {
	constructor(functionName) {
		this.functionName = functionName;
		this.logs = [];
		this.startTime = new Date();
	}

	info(message) {
		this._addLog("INFO", message);
	}

	warn(message) {
		this._addLog("WARN", message);
	}

	error(message) {
		this._addLog("ERROR", message);
	}

	_addLog(level, message) {
		const entry = {
			timestamp: new Date().toISOString(),
			level,
			message
		};
		console.log(`${level} - ${message}`);
		this.logs.push(entry);
	}

	async save() {
		try {
			this.info(`Finished execution in ${Date.now() - this.startTime.getTime()}ms`);
			const uuid = crypto.randomUUID();

			// Format: logs/YYYY-MM-DD/function_timestamp_abcd.json
			const dateStr = this.startTime.toISOString().split('T')[0];
			const key = `logs/${dateStr}/${this.functionName}_${this.startTime.getTime()}_${uuid.substring(0, 8)}.json`;

			const content = JSON.stringify({
				functionName: this.functionName,
				startTime: this.startTime.toISOString(),
				durationMs: Date.now() - this.startTime.getTime(),
				logs: this.logs
			}, null, 2);

			await s3.send(new PutObjectCommand({
				Bucket: R2_BUCKET_NAME,
				Key: key,
				Body: content,
				ContentType: "application/json"
			}));
		} catch (err) {
			console.error("Failed to save logs to R2:", err);
		}
	}
}

module.exports = Logger;
