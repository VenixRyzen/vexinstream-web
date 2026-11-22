# CLAUDE.md — VexinStream (`v7.0`)

## Project Overview
- **App Name:** VexinStream (Created & Developed by **VenixRyzen**)
- **Current Version:** `v7.0`
- **Stack:** Zero-build Vanilla HTML5, CSS3, Vanilla JS, PWA (`manifest.json`, `sw.js`), `hls.js`, AniList GraphQL API, Anivexa-API fallback (`https://onrender.com`), and **Supabase JS v2** (CDN) for cloud auth, XP leveling, cosmetics, and the global leaderboard.

---

## Non-Negotiable Architectural Rules
1. **Zero-Build Setup:** Do NOT introduce bundlers (Webpack, Vite, Parcel), Node dependencies, or TypeScript compilation. Everything must run directly in the browser from `index.html` (or clean modular `css/` and `js/` files linked via standard `<link>` / `<script>` tags). `supabase/schema.sql` is dashboard setup SQL only — not a build step.
2. **Creator Branding:** Always preserve **VexinStream** and **by VenixRyzen** credits in the header, spotlight section, and footer.
3. **Service Worker Cache Versioning:** Whenever modifying core shell files (`index.html`, `manifest.json`, or new CSS/JS files), bump `CACHE_NAME` in `sw.js` (currently `"vexinstream-shell-v7.0"`) so returning PWA users receive updates cleanly.
4. **Mobile RAM & Player Cleanup:**
   - Keep `hls.js` strictly capped: `{ maxBufferLength: 30, maxMaxBufferLength: 60, backBufferLength: 30, enableWorker: true }`.
   - Always call `stopMedia()` (`hls.stopLoad()`, `hls.detachMedia()`, `hls.destroy()`, `video.removeAttribute("src")`, `video.load()`) before switching episodes, changing servers, or closing `#player-section`.
5. **Ad-Shield & Brave Compatibility:**
   - Respect `vexin_sandbox_prefs` per-server rules (`megaplay-mal-sub` and `megaplay-mal-dub` default to `false`; others default to `true`).
   - Respect `navigator.brave.isBrave()` auto-detection (defaults internal iframe `sandbox` to `OFF` on Brave while showing `#brave-badge`).
6. **Content Maturity Safety:** Default to `SFW` (hiding `isAdult: true` and `"Ecchi"` / `"Hentai"` genres at both GraphQL and client levels).
7. **Supabase Zero-Build Config:** `SUPABASE_URL` / `SUPABASE_ANON_KEY` live as clearly marked placeholders at the top of the inline `<script>`. `SUPABASE_ENABLED` must gracefully fall back to `false` when keys are blank/invalid, the CDN fails, or `window.supabase` is missing — the site must never crash in local-only mode.
8. **Supabase Auth Flow:** Use **PKCE** (`flowType: "pkce"`) so Supabase callbacks use `?code=` and never collide with the legacy AniList `#access_token` hash handled by `handleOAuthRedirect()`. Never call Supabase auth methods synchronously inside `onAuthStateChange` — defer with `setTimeout(..., 0)`.
9. **XP & Cosmetics Integrity:** XP may only be written by the `award_watch_xp` RPC and cosmetics only by `equip_cosmetic` (both `SECURITY DEFINER`). Never grant clients direct UPDATE on `xp`, `level`, `episodes_watched`, or `equipped_*` columns.
10. **AniList Coexistence:** Supabase accounts and the legacy `userProfile` (AniList/local) are independent. Linking AniList stores its token in `vexin_user` and keeps `syncAniListEpisodeProgress()` working alongside a Supabase session. Do not remove the legacy sign-in path.

---

## File Map & Key Functions
- `index.html` — Core UI, CSS theme variables (`data-theme="dark|light"`, `data-accent`), AniList GraphQL client (`fetchAniList`), embed switcher (`EMBED_SERVERS`), HLS fallback (`API_SERVERS`), player controls, and all v7.0 Supabase account / XP / cosmetics / leaderboard logic.
- `manifest.json` — PWA standalone manifest (`#08090e` background, maskable SVG icon).
- `sw.js` — Network-first shell caching; bypasses external video streams, `graphql.anilist.co`, and Supabase requests (all cross-origin).
- `supabase/schema.sql` — **New in v7.0.** Run once in the Supabase SQL Editor: tables, RLS, column-level grants, `handle_new_user` trigger, `award_watch_xp` / `equip_cosmetic` RPCs, and the seeded `cosmetics` catalog.

### Key Functions to Know Before Editing
- **Titles:** `getAnimeTitle(anime)` & `findEnglishSynonym(anime)` (falls back to Latin synonyms before Romaji).
- **Streaming & Sandbox:** `isSandboxEnabledForServer(serverKey)`, `applyIframeSandbox(iframeEl, enableSandbox)`, `stopMedia()`, `changeEpisode(delta, autoSynced)`.
- **AniList Sync:** `syncAniListEpisodeProgress(anime, completedEp)` (fires at `>= 82%` HLS progress or `Next →` / `N` hotkey, deduplicated via `syncedAniListKeys`).
- **Supabase Auth (v7.0):** `initSupabaseAuth()`, `handleSupabaseSession(session)`, `loadSupabaseProfile()`, `renderAuthModal()`, `submitEmailAuth(e)`, `signInWithGoogle()`, `supabaseSignOut()`.
- **XP Progression (v7.0):** `awardWatchXp(anime, ep)` (deduped per `(anime.id, ep)` via `claimedXpKeys`), `applyXpResult(data)`, `showLevelUpBanner(data)`, `levelFromXp(xp)`, `xpProgress(xp)`.
- **Cosmetics (v7.0):** `COSMETIC_CATALOG`, `COSMETIC_FIELD`, `COSMETIC_DB_CATEGORY`, `openProfileModal()`, `renderProfileModal()`, `renderCosmeticGrid()`, `equipCosmetic(categoryKey, value)`, `saveDisplayName()`, `saveProfilePrivacy(isPublic)`.
- **Leaderboard (v7.0):** `loadLeaderboard()`, `leaderboardRowHtml(profile, rank, isMe)`, `switchTab("LEADERBOARD")`.
- **Hotkeys:** `Space` (Play/Pause), `F` (Fullscreen), `M` (Mute), `N` (Next Episode) — must remain disabled when typing in `<input>`, `<textarea>`, or `<select>`.

### XP Rules (v7.0)
- Award **50 XP** once per unique `(anime_id, episode_num)` per Supabase user.
- Triggered at **`>= 82%`** of an HLS episode, on `Next →` with completion, on the `N` hotkey, and on `video.onended`.
- Level formula (client + SQL must stay in sync):
  - `level = Math.floor(Math.sqrt(xp / 100)) + 1`
  - `currentLevelMinXp = Math.pow(level - 1, 2) * 100`
  - `nextLevelMinXp = Math.pow(level, 2) * 100`
- Server-side anti-cheat: `watch_xp_log` has PK `(user_id, anime_id, episode_num)`; conflicting inserts award nothing.

---

## Supabase Schema (v7.0)

### Tables
- **`public.profiles`** — `id uuid` (PK → `auth.users`), `display_name`, `avatar_url`, `xp`, `level`, `episodes_watched`, `is_public`, `equipped_title`, `equipped_name_color`, `equipped_name_effect`, `equipped_avatar_frame`, `equipped_banner`, `created_at`, `updated_at`. No email column (privacy).
- **`public.watch_xp_log`** — `(user_id, anime_id, episode_num)` PK, `xp_awarded`, `awarded_at`. No client RLS policies.
- **`public.cosmetics`** — `(category, id)` PK, `label`, `required_level`. Mirrors `COSMETIC_CATALOG`; `equip_cosmetic` validates against it server-side.

### RPCs
- **`award_watch_xp(p_anime_id integer, p_episode_num integer)`** → `jsonb`:
  `{ awarded, xp, total_xp, level, old_level, leveled_up, episodes_watched }`
- **`equip_cosmetic(p_category text, p_value text)`** → `jsonb`:
  `{ ok, category, value }`; raises on locked/unknown cosmetics or unauthenticated calls.

### Security
- RLS on all tables.
- `profiles` SELECT = public rows **or** own row.
- Clients may only INSERT `(id, display_name, avatar_url)` and UPDATE `(display_name, is_public)`.
- Progression columns are writable only through the SECURITY DEFINER RPCs.
- `handle_new_user` trigger auto-creates a profile on email/Google sign-up.

### Required Supabase Dashboard Setup
1. Run `supabase/schema.sql` in the SQL Editor.
2. Paste Project URL + anon key into `SUPABASE_URL` / `SUPABASE_ANON_KEY` in `index.html`.
3. Authentication → URL Configuration → add your exact page URL to **Redirect URLs** (and localhost for testing).
4. Enable the **Google** provider for “Continue with Google”.
5. For AniList linking, create a client at `anilist.co/settings/developer` with the same redirect URL.

---

## Cosmetic Catalog & CSS Classes (v7.0)

All cosmetics are level-gated by `requiredLevel`; the client renders `🔒 Lvl X` on locked items and the RPC re-checks the level.

| Category | Equipped field | CSS class pattern |
|---|---|---|
| Titles | `equipped_title` | `.pc-title-pill`, `.lb-title-pill` (catalog labels/icons) |
| Name colors | `equipped_name_color` | `.nc-*` |
| Name effects | `equipped_name_effect` | `.ne-*` (`@keyframes` glow/pulse/shimmer/chromatic) |
| Avatar frames | `equipped_avatar_frame` | `.af-*` (`@keyframes` cyber/legendary) |
| Profile banners | `equipped_banner` | `.pbn-*` |

### Catalog IDs / Required Levels
- **Titles:** `newcomer` (1), `sub-enjoyer` (2), `binge-watcher` (4), `night-owl` (6), `sakuga-hunter` (9), `vexin-vanguard` (12), `anime-archivist` (16), `venix-elite` (20).
- **Name colors:** `default` (1), `cyber-cyan` (2), `sakura-pink` (3), `emerald-mint` (5), `royal-gold` (7), `sunset-gradient` (10), `nebula-gradient` (13), `prismatic-rgb` (18).
- **Name effects:** `none` (1), `soft-glow` (6), `neon-pulse` (11), `shimmer-sweep` (15), `chromatic-wave` (20).
- **Avatar frames:** `none` (1), `accent-ring` (3), `gold-crest` (8), `cyber-pulse` (14), `legendary-aura` (20).
- **Banners:** `sunset-drift` (1), `sakura-night` (4), `neon-city` (8), `aurora-sky` (12), `starlight-void` (17).

When adding/renaming a cosmetic, update **both** `COSMETIC_CATALOG` in `index.html` and the seed rows in `supabase/schema.sql`, then bump `CACHE_NAME`.

---

## `localStorage` Keys (Do Not Rename Without Migration)
- `vexin_settings` — `{ titleLang, theme, accent, maturity, autoNext }`
- `vexin_sandbox_prefs` — Per-server boolean map (e.g., `{ "megaplay-mal-sub": false }`)
- `vexin_maturity_confirmed` — `"true"`
- `vexin_anilist_client_id` — User's AniList OAuth Client ID
- `vexin_user` — `{ id, name, avatar, token, type: "anilist" | "local" }`
- `vexin_watchlist` — Array of saved AniList `media` objects
- `vexin_history` — Max 12 items: `[{ anime, ep, timestamp, duration, updatedAt }]`

**Supabase-managed (do not touch):** `sb-<project-ref>-auth-token` (session, maintained by `supabase-js`). There is no hand-written Supabase key in this list.

---

## Coding Conventions
- Keep UI mobile-friendly (`@media (max-width: 768px)` 2-column grid, 100-episode chunking with `+ Show All Eps`, `env(safe-area-inset-*)` support).
- Use existing CSS variables (`--bg`, `--surface`, `--glass`, `--accent`) so all 6 accent themes and Dark/Light modes apply automatically to new UI elements.
- Escape every user-controlled string inserted into `innerHTML` (`escapeHtml` / `escapeAttr`) — display names and avatar URLs are untrusted.
- Keep `CLAUDE.md` updated whenever new files, `localStorage` keys, Supabase tables/RPCs, cosmetics, or major features are added.