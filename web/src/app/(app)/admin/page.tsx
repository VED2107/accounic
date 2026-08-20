import { redirect } from 'next/navigation';
import { getMe } from '@/lib/supabase/server';
import { getAdminSystemInfo, getAdminUsers } from '@/lib/queries';
import { Card, PageHeader } from '@/components/ui/primitives';
import { Reveal } from '@/components/motion/reveal';
import { AdminIcon } from '@/components/icons';
import { UserTable } from './user-table';

export const metadata = { title: 'Admin' };

/**
 * Admin area (context.md §25).
 *
 * Intentionally small and intentionally plain: create a user, reset a password,
 * disable an account, and a handful of system counters. No CRM, no invoicing, no
 * reports. It uses the same design system as the rest of the product, but it
 * spends none of the product's warmth on itself.
 *
 * Note what is missing — there is no way to open another user's books. Admins
 * manage accounts; they are not given the ledgers, and RLS would refuse anyway.
 */
export default async function AdminPage({
  searchParams,
}: {
  searchParams: Promise<{ q?: string }>;
}) {
  const me = await getMe();
  if (!me) redirect('/login');
  if (!me.is_admin) redirect('/');

  const { q } = await searchParams;
  const query = typeof q === 'string' ? q : '';

  const [users, info] = await Promise.all([getAdminUsers(query), getAdminSystemInfo()]);

  const stats = [
    { label: 'Users', value: `${info.users_active}/${info.users_total}`, note: 'active' },
    { label: 'Administrators', value: String(info.admins) },
    { label: 'People', value: info.people_total.toLocaleString('en-IN') },
    { label: 'Transactions', value: info.transactions_total.toLocaleString('en-IN') },
    { label: 'Settlements', value: info.settlements_total.toLocaleString('en-IN') },
    { label: 'Database', value: info.database_size },
  ];

  return (
    <div className="mx-auto w-full max-w-5xl px-4 py-6 sm:px-6 lg:px-8 lg:py-8">
      <Reveal>
        <PageHeader
          eyebrow={
            <span className="flex items-center gap-1.5">
              <AdminIcon className="size-3.5" />
              Administration
            </span>
          }
          title="Accounts &amp; access"
          description="Accounting data stays private to each user. Administrators manage accounts, not ledgers."
        />
      </Reveal>

      <Reveal delay={40}>
        <Card className="mb-4 grid grid-cols-2 divide-line sm:grid-cols-3 sm:divide-x lg:grid-cols-6">
          {stats.map((stat) => (
            <div
              key={stat.label}
              className="border-b border-line px-4 py-3 last:border-b-0 sm:border-b-0 lg:border-b-0"
            >
              <p className="truncate text-[0.6875rem] uppercase tracking-wider text-ink-faint">
                {stat.label}
              </p>
              <p className="tnum mt-1 truncate text-[0.9375rem] font-semibold text-ink">
                {stat.value}
                {stat.note ? (
                  <span className="ml-1 text-[0.6875rem] font-normal text-ink-faint">
                    {stat.note}
                  </span>
                ) : null}
              </p>
            </div>
          ))}
        </Card>
      </Reveal>

      <Reveal delay={80}>
        <UserTable users={users.users} total={users.total} currentUserId={me.id} query={query} />
      </Reveal>
    </div>
  );
}
