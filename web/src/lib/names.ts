/**
 * Name helpers.
 *
 * Kept in a plain module rather than beside the search UI: both Server and
 * Client Components render avatars, and a function exported from a 'use client'
 * file cannot be called during a server render.
 */

/** "Rahul Traders" -> "RT". Falls back to "?" for an unusable name. */
export function initials(name: string): string {
  const parts = name.trim().split(/\s+/).slice(0, 2);
  return parts.map((part) => part[0]?.toUpperCase() ?? '').join('') || '?';
}
