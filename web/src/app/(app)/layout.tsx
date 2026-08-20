import { redirect } from 'next/navigation';
import { getMe } from '@/lib/supabase/server';
import { AppShell } from '@/components/shell/app-shell';

/**
 * Authenticated shell (context.md §29).
 *
 * The session is resolved once here and handed down, so no child screen pays
 * for another auth round trip.
 */
export default async function AppLayout({ children }: { children: React.ReactNode }) {
  const me = await getMe();
  if (!me) redirect('/login');

  return <AppShell me={me}>{children}</AppShell>;
}
