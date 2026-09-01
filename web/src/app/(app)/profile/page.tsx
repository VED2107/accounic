import { redirect } from 'next/navigation';
import { getMe } from '@/lib/supabase/server';
import { Avatar, Badge, Card, PageHeader } from '@/components/ui/primitives';
import { Reveal } from '@/components/motion/reveal';
import { ThemeChooser } from '@/components/shell/theme-toggle';
import { ProfileForm } from './profile-form';
import { PasswordForm } from './password-form';
import { SignOutButton } from './sign-out-button';
import { ExportPanel } from './export-panel';
import { initials } from '@/lib/names';
import { fullDate } from '@/lib/dates';

export const metadata = { title: 'Profile' };

/**
 * Profile (context.md §4).
 *
 * An account screen, not a settings sprawl. Five groups, each of which is a
 * question someone actually asks: who am I here, what is my business called,
 * how should this look, how do I change my password, how do I get out.
 */
export default async function ProfilePage() {
  const me = await getMe();
  if (!me) redirect('/login');

  return (
    <div className="mx-auto w-full max-w-4xl px-4 py-6 sm:px-6 lg:px-8 lg:py-8">
      <Reveal>
        <PageHeader title="Profile" description="Your account and how Accounic behaves for you." />
      </Reveal>

      <Reveal delay={40}>
        <Card className="mb-4 flex flex-wrap items-center gap-4 px-5 py-4">
          <Avatar size="lg" identity={me.name || me.email}>
            {initials(me.name || me.email)}
          </Avatar>
          <div className="min-w-0 flex-1">
            <p className="flex flex-wrap items-center gap-2">
              <span className="truncate font-display text-[1.0625rem] font-semibold tracking-tight text-ink">
                {me.name}
              </span>
              {me.is_admin ? <Badge tone="accent">Administrator</Badge> : null}
            </p>
            <p className="mt-0.5 truncate text-[0.8125rem] text-ink-muted">
              {me.email} · joined {fullDate(me.created_at)}
            </p>
          </div>
        </Card>
      </Reveal>

      <div className="grid items-start gap-4 lg:grid-cols-[1.15fr_1fr]">
        <Reveal delay={80}>
          <Card className="overflow-hidden">
            <div className="border-b border-line px-5 py-3.5">
              <h2 className="font-display text-[0.9375rem] font-semibold tracking-tight text-ink">
                Your details
              </h2>
              <p className="mt-0.5 text-[0.8125rem] text-ink-muted">
                Your email address is managed by your administrator.
              </p>
            </div>
            <div className="px-5 py-4">
              <ProfileForm me={me} />
            </div>
          </Card>
        </Reveal>

        <div className="space-y-4">
          <Reveal delay={110}>
            <Card className="overflow-hidden">
              <div className="border-b border-line px-5 py-3.5">
                <h2 className="font-display text-[0.9375rem] font-semibold tracking-tight text-ink">
                  Appearance
                </h2>
                <p className="mt-0.5 text-[0.8125rem] text-ink-muted">
                  Accounic is dark by default. This is stored on this device only.
                </p>
              </div>
              <div className="px-5 py-4">
                <ThemeChooser />
              </div>
            </Card>
          </Reveal>

          <Reveal delay={130}>
            <Card className="overflow-hidden">
              <div className="border-b border-line px-5 py-3.5">
                <h2 className="font-display text-[0.9375rem] font-semibold tracking-tight text-ink">
                  Your data
                </h2>
                <p className="mt-0.5 text-[0.8125rem] text-ink-muted">
                  Take your books with you — a report, a spreadsheet, or a backup.
                </p>
              </div>
              <div className="px-5 py-4">
                <ExportPanel />
              </div>
            </Card>
          </Reveal>

          <Reveal delay={140}>
            <Card className="overflow-hidden">
              <div className="border-b border-line px-5 py-3.5">
                <h2 className="font-display text-[0.9375rem] font-semibold tracking-tight text-ink">
                  Security
                </h2>
                <p className="mt-0.5 text-[0.8125rem] text-ink-muted">
                  Choose something long. You will stay signed in on this device.
                </p>
              </div>
              <div className="px-5 py-4">
                <PasswordForm />
              </div>
            </Card>
          </Reveal>

          <Reveal delay={170}>
            <Card className="flex flex-wrap items-center justify-between gap-4 px-5 py-4">
              <div className="min-w-0">
                <h2 className="font-display text-[0.9375rem] font-semibold tracking-tight text-ink">
                  Session
                </h2>
                <p className="mt-0.5 text-[0.8125rem] text-ink-muted">
                  Signed in as {me.email}.
                </p>
              </div>
              <SignOutButton />
            </Card>
          </Reveal>
        </div>
      </div>
    </div>
  );
}
