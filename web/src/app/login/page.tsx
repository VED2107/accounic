import type { Metadata } from 'next';
import { redirect } from 'next/navigation';
import { getMe } from '@/lib/supabase/server';
import { LoginForm } from './login-form';
import { AccounicMark } from '@/components/brand';

export const metadata: Metadata = { title: 'Sign in' };

/**
 * Sign-in (context.md §2).
 *
 * Email and password only. There is no signup link, no social button and no
 * password-reset flow by design: an administrator creates accounts and resets
 * passwords.
 *
 * The one screen a user sees before they are inside the product, so it carries
 * the mark at full size and nothing else — no marketing, no feature list, no
 * illustration. It is a door.
 */
export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ next?: string }>;
}) {
  if (await getMe()) redirect('/');
  const { next } = await searchParams;

  return (
    <main className="relative grid min-h-dvh place-items-center overflow-hidden px-5 py-12">
      {/* A single wash of brand colour behind the card. The only decoration in
          the product, and it is behind the one screen with nothing to read. */}
      <div
        aria-hidden
        className="pointer-events-none absolute left-1/2 top-0 size-[36rem] -translate-x-1/2 -translate-y-1/2 rounded-full bg-accent-soft blur-3xl"
      />

      <div className="reveal relative w-full max-w-sm">
        <div className="mb-8 flex flex-col items-center text-center">
          <AccounicMark id="login" className="size-14" />
          <h1 className="page-title mt-5">
            Accoun<span className="brand-text">ic</span>
          </h1>
          <p className="mt-2 text-[0.8125rem] text-ink-muted">
            Know who owes you, who you owe, and what is settled.
          </p>
        </div>

        <LoginForm next={typeof next === 'string' ? next : undefined} />

        <p className="mt-8 text-center text-[0.75rem] leading-relaxed text-ink-faint">
          Accounts are created by your administrator.
          <br />
          Contact them if you cannot sign in.
        </p>
      </div>
    </main>
  );
}
