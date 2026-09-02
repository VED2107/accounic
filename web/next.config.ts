import type { NextConfig } from 'next';

const nextConfig: NextConfig = {
  reactStrictMode: true,
  poweredByHeader: false,
  experimental: {
    // Keeps server action payloads small; this app never posts large bodies.
    serverActions: { bodySizeLimit: '1mb' },
  },
  // The PDF statement embeds Poppins so that a rupee sign is a rupee sign and
  // not a missing glyph. The route reads the two .ttf files off disk, and
  // nothing in the module graph *imports* them, so Next's file tracer cannot
  // see that they are needed and would leave them out of a deployment bundle.
  // Naming them here is what makes the export work anywhere but a dev server.
  outputFileTracingIncludes: {
    '/people/[id]/statement': ['./src/lib/pdf/fonts/*.ttf'],
  },
  async headers() {
    // The Supabase project this app talks to. Naming it in the CSP means a
    // script that somehow ran could not exfiltrate to anywhere else — the
    // connect-src is the control that turns XSS from "read the ledger and post
    // it elsewhere" into "read the ledger".
    const supabase = process.env.NEXT_PUBLIC_SUPABASE_URL ?? '';
    const supabaseOrigin = (() => {
      try {
        return new URL(supabase).origin;
      } catch {
        return '';
      }
    })();
    const supabaseWs = supabaseOrigin.replace(/^https:/, 'wss:');

    const csp = [
      "default-src 'self'",
      // Next's App Router inlines hydration data and a small bootstrap, and
      // styled-jsx writes inline <style>. 'unsafe-inline' for styles is
      // unavoidable without a nonce pipeline; scripts get 'unsafe-inline' only
      // because Next's inline bootstrap has no stable hash across builds.
      // Tightening this to a nonce is the next step worth taking here.
      //
      // 'unsafe-eval' in development ONLY. Next's dev server ships React Fast
      // Refresh, which evaluates modules as strings; with it blocked the whole
      // client bundle failed to initialise and NOTHING on localhost hydrated —
      // every dialog, menu, filter and form was dead, while the server-rendered
      // HTML looked perfectly fine. That is a nasty way to lose an afternoon,
      // and it hid every interaction bug behind a page that merely looked
      // correct. The production bundle evaluates no strings, so the deployed
      // policy is unchanged and stays as strict as it was.
      process.env.NODE_ENV === 'development'
        ? "script-src 'self' 'unsafe-inline' 'unsafe-eval'"
        : "script-src 'self' 'unsafe-inline'",
      "style-src 'self' 'unsafe-inline'",
      "img-src 'self' data: blob:",
      "font-src 'self' data:",
      // Supabase REST, auth and realtime, and nothing else.
      `connect-src 'self' ${supabaseOrigin} ${supabaseWs}`.trim(),
      "frame-ancestors 'none'",
      "form-action 'self'",
      "base-uri 'self'",
      "object-src 'none'",
      'upgrade-insecure-requests',
    ].join('; ');

    return [
      {
        source: '/:path*',
        headers: [
          { key: 'Content-Security-Policy', value: csp },
          // Two years, subdomains included. Only meaningful over HTTPS, which
          // is the only way this is deployed.
          {
            key: 'Strict-Transport-Security',
            value: 'max-age=63072000; includeSubDomains; preload',
          },
          { key: 'X-Content-Type-Options', value: 'nosniff' },
          // X-Frame-Options for old browsers; frame-ancestors above is the real
          // control and wins wherever both are understood.
          { key: 'X-Frame-Options', value: 'DENY' },
          { key: 'Referrer-Policy', value: 'strict-origin-when-cross-origin' },
          {
            key: 'Permissions-Policy',
            value: 'camera=(), microphone=(), geolocation=(), payment=(), usb=()',
          },
          // This app is same-origin only; both of these cost nothing and close
          // cross-origin leak channels.
          { key: 'Cross-Origin-Opener-Policy', value: 'same-origin' },
          { key: 'Cross-Origin-Resource-Policy', value: 'same-origin' },
          { key: 'X-DNS-Prefetch-Control', value: 'off' },
        ],
      },
    ];
  },
};

export default nextConfig;
