const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');

async function debug() {
	const jsonCookiePath = path.resolve(process.cwd(), 'cookies.json');
	const netscapeCookiePath = path.resolve(process.cwd(), 'cookies_debug.txt');
	let activeCookiePath = undefined;

	if (fs.existsSync(jsonCookiePath)) {
		console.log('Found cookies.json, converting...');
		try {
			const jsonContent = fs.readFileSync(jsonCookiePath, 'utf8');
			const cookies = JSON.parse(jsonContent);

			let netscapeContent = "# Netscape HTTP Cookie File\n";
			cookies.forEach(c => {
				const domain = c.domain;
				const includeSubdomains = domain.startsWith('.') ? 'TRUE' : 'FALSE';
				const path = c.path;
				const secure = c.secure ? 'TRUE' : 'FALSE';
				const expiration = c.expirationDate ? Math.round(c.expirationDate) : 0;
				const name = c.name;
				const value = c.value;

				netscapeContent += `${domain}\t${includeSubdomains}\t${path}\t${secure}\t${expiration}\t${name}\t${value}\n`;
			});

			fs.writeFileSync(netscapeCookiePath, netscapeContent);
			console.log('Saved Netscape cookies to', netscapeCookiePath);
			activeCookiePath = netscapeCookiePath;
		} catch (err) {
			console.error("Error converting:", err);
		}
	}

	const binaryPath = path.resolve(process.cwd(), 'yt-dlp');
	// Removed User-Agent to let yt-dlp pick the best one
	const args = [
		'-F',
		'https://www.youtube.com/watch?v=s4xmUqBRg6g',
		'--referer', 'https://www.youtube.com/'
	];

	/*
if (activeCookiePath) {
	args.push('--cookies', activeCookiePath);
}
*/

	console.log(`Running: ${binaryPath} ${args.join(' ')}`);
	const child = spawn(binaryPath, args, { stdio: 'inherit' });

	child.on('exit', (code) => {
		console.log(`Exited with ${code}`);
		// Clean up
		if (fs.existsSync(netscapeCookiePath)) fs.unlinkSync(netscapeCookiePath);
	});
}

debug();
