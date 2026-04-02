# Implementazioni recenti

## 2 Aprile 2026

### Cached Playlist: layout compatto e auto-advance
- **CachedPlaylistView**: sostituito `VideoCardView` (card grandi con thumbnail 220px) con layout lista compatto — thumbnail 100x56, titolo `.footnote`, metadata `.caption2`, righe strette con divider
- **CachedPlaylistViewModel**: ordinamento cambiato da newest-first per data di download a **oldest-first per data di pubblicazione** (`publishedAt`)
- **Auto-advance**: tappando un video dalla playlist cached si imposta la coda completa tramite `setQueue()`, così al termine della traccia parte automaticamente la successiva
- **Debug video mancanti**: aggiunto log dei video cached su R2 che non vengono restituiti dall'API YouTube (`fetchVideoDetails`), per identificare video persi silenziosamente

### Playlist YouTube: ordinamento e coda di riproduzione
- **YouTubeService**: nuovo metodo `fetchAllPlaylistItems()` che pagina tutte le pagine dell'API (maxResults: 50) per ottenere l'intera playlist
- **PlaylistDetailView**: gli elementi vengono ora ordinati per `publishedAt` ascending (il meno recente per primo) e al tap si imposta la coda per l'auto-advance
- **AudioPlayerService — sistema di coda**:
  - Nuova struct `QueueItem` (videoId, title, author, thumbnailURL, publishedAt)
  - Stato coda: `queue`, `currentQueueIndex`, computed `hasQueue`/`hasNextTrack`/`hasPreviousTrack`
  - Metodi: `setQueue(items:startIndex:)`, `playNextTrack()`, `playPreviousTrack()`, `clearQueue()`
  - `setupEndObserver`: auto-advance al termine della traccia
  - Remote Command Center: handler per next/previous track abilitati dinamicamente quando la coda è attiva
  - `playVideo()` svuota la coda se chiamato da contesti non-coda (tap singolo da Home, Channel, ecc.)
  - `stop()` svuota la coda
  - Rimossa property inutilizzata `playNext: Bool`

---

## 31 Marzo 2026

### Backend: paginazione R2 ListObjects
- **check-cache.js**: la lista degli oggetti R2 ora pagina correttamente usando `ContinuationToken`, risolvendo il limite di 1000 oggetti per richiesta e restituendo tutti i file cached

### Cached Playlist: ordinamento per data di download
- **CachedPlaylistViewModel**: ordinamento per `LastModified` (data di download esatta da R2) al posto di `publishedAt`, con fallback a `publishedAt` se le date di download sono identiche

---

## 30 Marzo 2026

### Prefetch Queue: fix e stabilizzazione
- Risolto loop infinito nella coda di prefetch
- Ripristinato menu ellipsis per le azioni sui video
- Fixata race condition nel sovrascrittura della coda di prefetch

### Coda di prefetch individuale
- Nuova funzionalità: possibilità di aggiungere singoli episodi alla coda di download (prefetch)
- **PrefetchQueueService**: servizio per gestione coda, sincronizzazione con backend
- **PrefetchQueueView**: vista dedicata nella tab Playlist (tab "Coda")
- Integrazione nel menu ellipsis di `VideoCardView` e `ChannelDetailView`
