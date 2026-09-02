import type { ReactNode } from 'react';
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
/**
 * One settings group: a hairline, a quiet heading, the control beneath it.
 *
 * The rule is the one `FormSection` follows in the design system — a heading is
 * a label, not a container. The rule belongs to the section rather than to the
 * gap, so the first group in a column drops its own line without the parent
 * needing to know which child is first.
 */
function SettingsSection({
  title,
  description,
  delay,
  children,
}: {
  title: string;
  description?: string;
  delay: number;
  children: ReactNode;
}) {
  return (
    <Reveal delay={delay} className="block border-t border-line pt-5 first:border-t-0 first:pt-0 [&:not(:first-child)]:mt-6">
      <h2 className="stat-label">{title}</h2>
      {description ? (
        <p className="mt-1.5 max-w-prose text-[0.8125rem] leading-relaxed text-ink-muted">
          {description}
        </p>
      ) : null}
      <div className="mt-4">{children}</div>
    </Reveal>
  );
}

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

      {/* Sections, not six cards.

          Every group here was a Card — border, background, radius, header rule
          — so a settings page of five short forms carried five heavy containers
          and read as five separate documents rather than one account screen.
          `primitives.tsx` already states the rule for grouped fields: the
          heading is a hairline label, not a card. Profile is the same shape and
          now follows it, which is why the page suddenly has a spine. */}
      <div className="grid items-start gap-x-10 lg:grid-cols-[1.15fr_1fr]">
        <div>
          <SettingsSection
            delay={80}
            title="Identity"
            description="Your email address is managed by your administrator."
          >
            <ProfileForm me={me} />
          </SettingsSection>
        </div>

        <div>
          <SettingsSection
            delay={110}
            title="Appearance"
            description="Accounic is dark by default. This is stored on this device only."
          >
            <ThemeChooser />
          </SettingsSection>

          <SettingsSection
            delay={130}
            title="Your data"
            description="Take your books with you — a report, a spreadsheet, or a backup."
          >
            <ExportPanel />
          </SettingsSection>

          <SettingsSection
            delay={140}
            title="Security"
            description="Choose something long. You will stay signed in on this device."
          >
            <PasswordForm />
          </SettingsSection>

          {/* Signing out is destructive enough to be deliberate and ordinary
              enough not to shout. It gets the last section and a quiet control,
              not a red panel. */}
          <SettingsSection delay={170} title="Session" description={`Signed in as ${me.email}.`}>
            <SignOutButton />
          </SettingsSection>
        </div>
      </div>
    </div>
  );
}
