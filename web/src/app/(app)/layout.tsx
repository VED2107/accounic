import { redirect } from 'next/navigation';
import { getMe } from '@/lib/supabase/server';
import { AppShell } from '@/components/shell/app-shell';
import { TelemetryListener } from '@/components/telemetry-listener';

/**
 * Authenticated shell (context.md §29).
 *
 * The session is resolved once here and handed down, so no child screen pays
 * for another auth round trip.
 */
export default async function AppLayout({ children }: { children: React.ReactNode }) {
  const me = await getMe();
  if (!me) redirect('/login');

  return (
    <AppShell me={me}>
      {/* Reports the two failures React's boundary never sees: an error in a
          handler or timer, and a promise nobody awaited (Phase 2). */}
      <TelemetryListener />
      {children}
    </AppShell>
  );
}
