# Fix: Prefetch Bot Detection — 2026-03-07

**Branch**: `claude/fix-prefetch-bot-detection-LmOAM`
**File modificato**: `netlify/functions/scheduled-prefetch-background.js`

---

## Problema

La funzione di prefetch schedulata (`0 */3 * * *`) veniva rilevata da YouTube come bot dopo pochi download andati a buon fine. Una volta rilevata, tutti i download successivi fallivano con l'errore:

> `Sign in to confirm you are not a bot`

I cookie venivano "bruciati" durante ogni run e il loop continuava comunque, aggravando il ban invece di fermarsi.

---

## Cause identificate

| # | Causa | Dettaglio |
|---|-------|-----------|
| 1 | **Nessun delay tra download** | Fino a 15 video scaricati in sequenza istantanea (5 canali × 3 video) |
| 2 | **Nessun delay tra canali** | I canali venivano processati back-to-back senza pause |
| 3 | **Cookie bruciati in bulk** | Tutti i download dello stesso run usavano gli stessi cookie, rendendoli sospetti |
| 4 | **Nessun abort su bot detection** | Dopo il primo errore "Sign in to confirm", il loop continuava e peggiorava la situazione |
| 5 | **Volume eccessivo per run** | 3 video per canale = troppo traffico concentrato |
| 6 | **yt-dlp HTTP interno bursty** | Nessun rate limiting sulle richieste HTTP interne di yt-dlp |

---

## Fix implementate

### Fix A — Delay randomizzato tra video (10–45 secondi)

Tra il download di un video e il successivo (all'interno dello stesso canale) viene inserita una pausa casuale tra 10 e 45 secondi.

```js
if (!botDetected && vi < videosToCheck.length - 1) {
    const delaySec = Math.floor(Math.random() * 36) + 10;
    logger.info(`Waiting ${delaySec}s before next video...`);
    await sleep(delaySec * 1000, delaySec * 1000);
}
```

---

### Fix B — Delay randomizzato tra canali (30–90 secondi)

Tra la scansione di un canale e quella successiva viene inserita una pausa casuale tra 30 e 90 secondi.

```js
if (!botDetected && ci < channels.length - 1) {
    const delaySec = Math.floor(Math.random() * 61) + 30;
    logger.info(`Waiting ${delaySec}s before next channel...`);
    await sleep(delaySec * 1000, delaySec * 1000);
}
```

---

### Fix C — Abort immediato su bot detection

Al primo errore che contiene `"Sign in to confirm"` o `"confirm you"`, il flag `botDetected` viene impostato a `true` e **tutti i loop** (`for` canali e `for` video) si interrompono immediatamente. Viene inviata una notifica in-app.

Questo evita di continuare a fare richieste con cookie già compromessi, preservandoli per il run successivo.

```js
let botDetected = false;

// Nel loop video:
if (downloadErr.message.includes('Sign in to confirm') || downloadErr.message.includes('confirm you')) {
    logger.warn('Bot-check detected during download! Aborting run to preserve cookies.');
    botDetected = true;
    break;
}

// Nel loop canali:
if (botDetected) break;
```

---

### Fix D — Riduzione da 3 a 2 video per canale

Il numero di video controllati per ogni canale è stato ridotto da 3 a 2, diminuendo il volume totale di richieste per run del 33%.

```js
// Prima
const videosToCheck = feed.items.slice(0, 3);

// Dopo
const videosToCheck = feed.items.slice(0, 2);
```

---

### Fix E — Rate limiting interno di yt-dlp

Aggiunti tre flag alle args di yt-dlp per rallentare le sue richieste HTTP interne (resolve, manifest, segment fetch):

```js
args.push('--sleep-requests', '2');      // 2s tra richieste HTTP interne
args.push('--sleep-interval', '3');      // minimo 3s di pausa
args.push('--max-sleep-interval', '10'); // massimo 10s di pausa (random)
```

---

## Impatto sui tempi di esecuzione

Con le fix attive, il tempo per processare N canali con M video da scaricare è approssimativamente:

```
T ≈ (N - 1) × 30–90s [delay tra canali]
  + download_effettivi × (10–45s [delay tra video] + 3–10s [yt-dlp interno] + tempo_download)
```

Per 5 canali con 0–1 video nuovo per canale: ~5–8 minuti totali stimati.
Il timeout di Netlify Functions è 26 secondi per le funzioni standard, ma le scheduled functions hanno timeout estesi — verificare se necessario.

---

## Comportamento precedente vs attuale

| Scenario | Prima | Dopo |
|----------|-------|------|
| 5 canali, nessun nuovo video | ~5 secondi | ~2–5 minuti (delay tra canali) |
| 5 canali, 2 nuovi video ciascuno | ~30 secondi | ~10–15 minuti |
| Bot detection al 3° video | Continua fino alla fine bruciando tutti i cookie | Abort immediato, notifica inviata |
| Cookie scaduti | Loop completo con 10+ errori nei log | Stop al primo errore |
