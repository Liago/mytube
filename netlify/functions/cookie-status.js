const { S3Client, GetObjectCommand, HeadObjectCommand } = require("@aws-sdk/client-s3");

// Configuration from Environment Variables
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
		// 1. Get File Metadata (Last Modified)
		const headParams = {
			Bucket: R2_BUCKET_NAME,
			Key: 'system/_cookies.json'
		};
		let lastModified = null;
		try {
			const head = await s3.send(new HeadObjectCommand(headParams));
			lastModified = head.LastModified;
		} catch (e) {
			console.log("Could not get head object for cookies:", e.message);
		}

		// 2. Get File Content
		const cookieObj = await s3.send(new GetObjectCommand({
			Bucket: R2_BUCKET_NAME,
			Key: 'system/_cookies.json',
		}));
		const chunks = [];
		for await (const chunk of cookieObj.Body) {
			chunks.push(chunk);
		}
		const cookieBody = Buffer.concat(chunks).toString('utf8');
		const cookies = JSON.parse(cookieBody);

		// 3. Analyze Cookies
		const totalCookies = cookies.length;
		let earliestExpiration = null;
		let validCookies = 0;
		const now = Date.now() / 1000; // Unix timestamp in seconds

		// Priority cookies for expiration check
		const PRIORITY_COOKIES = ['__Secure-1PSID', 'LOGIN_INFO'];
		let priorityExpiration = null;

		cookies.forEach(c => {
			if (c.expirationDate) {
				// If expiration is in the past, it's expired
				if (c.expirationDate > now) {
					validCookies++;

					// Track priority cookie expiration
					if (PRIORITY_COOKIES.includes(c.name)) {
						if (priorityExpiration === null || c.expirationDate < priorityExpiration) {
							priorityExpiration = c.expirationDate;
						}
					}

					// Track general earliest valid expiration
					if (earliestExpiration === null || c.expirationDate < earliestExpiration) {
						earliestExpiration = c.expirationDate;
					}
				}
			} else {
				// Session cookie or no expiration
				validCookies++;
			}
		});

		// Use priority expiration if available, otherwise general earliest
		const finalExpiration = priorityExpiration || earliestExpiration;

		// Determine Status
		let status = "Valid";
		const oneDay = 86400;
		const threeDays = oneDay * 3;

		if (validCookies === 0) {
			status = "Expired";
		} else if (finalExpiration && (finalExpiration - now) < threeDays) {
			status = "Expiring Soon";
		}

		return {
			statusCode: 200,
			body: JSON.stringify({
				totalCookies: totalCookies,
				validCookies: validCookies,
				validCookies: validCookies,
				earliestExpiration: finalExpiration, // Unix timestamp
				lastUploaded: lastModified, // ISO string
				status: status
			}),
		};

	} catch (error) {
		if (error.name === 'NoSuchKey' || error.name === 'NotFound') {
			return {
				statusCode: 404,
				body: JSON.stringify({ error: "Cookies not found", status: "Missing" })
			};
		}
		console.error("Error reading cookies:", error);
		return {
			statusCode: 500,
			body: JSON.stringify({ error: error.message }),
		};
	}
};
