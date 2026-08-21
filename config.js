/* Optional auto-connect for the KC Project Leads portal.
 *
 * Leave these blank to use the in-app "Connect to Supabase" screen (which stores
 * the values in your browser's localStorage instead).
 *
 * To auto-connect for everyone who opens this page, fill both in and commit this
 * file. NOTE: the anon key is a PUBLIC key, and this is an "open portal" (anyone
 * with the page can already read and edit the data), so committing it here does
 * not expose anything the portal doesn't already expose. Do NOT put the
 * service_role/secret key here.
 */
window.KC_SUPABASE = {
  url: "",      // e.g. https://abcdefgh.supabase.co
  anonKey: ""   // your project's anon public key
};
