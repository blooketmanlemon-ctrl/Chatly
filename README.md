# Chatly — deployable multiplayer chat starter

This is a static HTML app backed by Supabase. It is not an offline-only mockup: once configured and deployed, separate people can register, join public servers, use private invite codes, and exchange messages/images.

## 1. Create the Supabase backend
1. Create a project at https://supabase.com/.
2. In the project, open **SQL Editor**, create a query, paste all of `schema.sql`, and run it.
3. Open **Storage** and create a bucket named `chat-images`. Set it to **Public**. (The SQL file adds upload/read policies.)
4. Open **Project Settings → API**. Copy the Project URL and the `anon` / publishable public key. Never use the `service_role` secret in browser code.

## 2. Configure the website
Open `index.html` in a text editor. At the top of its script, replace:
- `PASTE_YOUR_SUPABASE_PROJECT_URL`
- `PASTE_YOUR_SUPABASE_ANON_KEY`

The anon/public key is intended for browser use; database safety comes from the Row Level Security policies in `schema.sql`. Do not disable RLS or expose a service-role key.

## 3. Publish it so friends can join
A local file or `file://` bookmark is not a shareable online service. Upload `index.html`, `manifest.webmanifest`, `sw.js`, and the other included files to a static host that serves HTTPS, such as GitHub Pages, Netlify, or Cloudflare Pages. Then share the resulting HTTPS URL. Friends open that same URL and register their own accounts. For GitHub Pages, create a repository, upload the files, then enable Pages in repository Settings → Pages.

The app is configured for open registration. Anyone who can reach the site can create an account. Public servers can be discovered and joined; private servers require an invite code.

## 4. Install on phones
Open the published HTTPS address in the browser. On Android/Chrome use **⋮ → Install app** or **Add to Home screen**. On iPhone/Safari use **Share → Add to Home Screen**.

## Current starter scope
- Email/password accounts, username profile
- Public server discovery and joining
- Private servers with invite codes
- Server channels and live channel messages
- Image attachments
- Persistent messages in Supabase
- Responsive layout and PWA manifest/service worker

This starter does not yet include direct-message threads, push notifications, typing indicators, read receipts, moderation tools, or end-to-end encryption. Do not use it for sensitive conversations. Public image URLs mean uploaded images can be viewed by anyone who has the URL. Add moderation, rate limits, stronger storage rules, and privacy controls before inviting a large public audience.
