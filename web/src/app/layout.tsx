import type { Metadata, Viewport } from 'next';
import { Inter, Poppins } from 'next/font/google';
import { THEME_BOOT_SCRIPT } from '@/lib/theme';
import './globals.css';

/**
 * Two faces, each with a job (docs/decisions.md).
 *
 * Poppins carries the brand and the headings — it is the wordmark's face, so
 * using it for titles makes the product feel of a piece. Inter carries every
 * label, row and number, because at 13px it stays legible in a way a geometric
 * face does not. Both are self-hosted by next/font, so there is no render-
 * blocking request to Google and no layout shift when they land.
 */
const display = Poppins({
  subsets: ['latin'],
  weight: ['500', '600', '700'],
  variable: '--font-display-face',
  display: 'swap',
});

const ui = Inter({
  subsets: ['latin'],
  variable: '--font-ui',
  display: 'swap',
});

export const metadata: Metadata = {
  title: {
    default: 'Accounic',
    template: '%s · Accounic',
  },
  applicationName: 'Accounic',
  description: 'Know who owes you, who you owe, and what is settled.',
  // Private software for a handful of trusted people (context.md §1).
  robots: { index: false, follow: false },
};

export const viewport: Viewport = {
  themeColor: [
    { media: '(prefers-color-scheme: light)', color: '#f6f7f9' },
    { media: '(prefers-color-scheme: dark)', color: '#08090c' },
  ],
  width: 'device-width',
  initialScale: 1,
  viewportFit: 'cover',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={`${ui.variable} ${display.variable}`} suppressHydrationWarning>
      <head>
        {/* Applies a pinned light/dark choice before first paint. Without it the
            page paints dark and swaps, which flashes on every navigation. */}
        <script dangerouslySetInnerHTML={{ __html: THEME_BOOT_SCRIPT }} />
      </head>
      <body className="min-h-dvh antialiased">{children}</body>
    </html>
  );
}
