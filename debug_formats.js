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
				const domain = c.domain.startsWith('.') ? c.domain : `.${c.domain}`;
				const includeSubdomains = 'TRUE';
				const pathStr = c.path;
				const secure = c.secure ? 'TRUE' : 'FALSE';
				const expiration = c.expirationDate ? Math.round(c.expirationDate) : 0;
				const name = c.name;
				const value = c.value;

				netscapeContent += `${domain}\t${includeSubdomains}\t${pathStr}\t${secure}\t${expiration}\t${name}\t${value}\n`;
			});

			fs.writeFileSync(netscapeCookiePath, netscapeContent);
			console.log('Saved Netscape cookies to', netscapeCookiePath);
			activeCookiePath = netscapeCookiePath;
		} catch (err) {
			console.error("Error converting:", err);
		}
	}

	const binaryPath = path.resolve(process.cwd(), 'yt-dlp');
	const args = [
		'-F',
		'https://www.youtube.com/watch?v=htXlkd-L4ZM',
		'--extractor-args', 'youtube:player_client=web',
		'--user-agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36'
	];

	if (activeCookiePath) {
		args.push('--cookies', activeCookiePath);
	}

	console.log(`Running: ${binaryPath} ${args.join(' ')}`);
	const child = spawn(binaryPath, args, { stdio: 'inherit' });

	child.on('exit', (code) => {
		console.log(`Exited with ${code}`);
		// Clean up
		if (fs.existsSync(netscapeCookiePath)) fs.unlinkSync(netscapeCookiePath);
	});
}

debug();
