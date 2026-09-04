'use client';

import { useActionState, useEffect, useRef, useState, useTransition } from 'react';
import { useRouter } from 'next/navigation';
import { Modal, ConfirmDialog } from '@/components/ui/modal';
import {
  Avatar,
  Badge,
  Button,
  Card,
  EmptyState,
  ErrorNote,
  Field,
  Input,
  Select,
  Spinner,
  SuccessNote,
  cn,
} from '@/components/ui/primitives';
import { Menu } from '@/components/ui/menu';
import { useToast } from '@/components/ui/toast';
import { staggerStyle } from '@/components/motion/reveal';
import { SubmitRow } from '@/components/ledger/transaction-sheet';
import { CloseIcon, PlusIcon, ProfileIcon, SearchIcon } from '@/components/icons';
import { initials } from '@/lib/names';
import {
  adminCreateUser,
  adminDeleteUser,
  adminResetPassword,
  adminSetUserActive,
  adminSetUserAdmin,
} from '@/lib/admin-actions';
import { relativeTime } from '@/lib/dates';
import type { ActionResult, AdminUser } from '@/lib/types';

const CURRENCIES = ['INR', 'USD', 'EUR', 'GBP', 'AED', 'AUD', 'CAD', 'SGD'];

export function UserTable({
  users,
  total,
  currentUserId,
  query,
}: {
  users: AdminUser[];
  total: number;
  currentUserId: string;
  query: string;
}) {
  const router = useRouter();
  const [search, setSearch] = useState(query);
  const [createOpen, setCreateOpen] = useState(false);
  const [resetting, setResetting] = useState<AdminUser | null>(null);
  const [confirming, setConfirming] = useState<{
    user: AdminUser;
    kind: 'toggle' | 'delete' | 'admin';
  } | null>(
    null,
  );
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();
  const toast = useToast();

  useEffect(() => {
    const timer = window.setTimeout(() => {
      const params = new URLSearchParams();
      if (search.trim()) params.set('q', search.trim());
      router.replace(params.size ? `/admin?${params}` : '/admin', { scroll: false });
    }, 220);
    return () => window.clearTimeout(timer);
  }, [search, router]);

  function run(operation: () => Promise<ActionResult<unknown>>, done?: string) {
    setError(null);
    startTransition(async () => {
      const result = await operation();
      if (!result.ok) {
        setError(result.error);
        return;
      }
      setConfirming(null);
      router.refresh();
      if (done) toast.show({ tone: 'success', title: done });
    });
  }

  return (
    <>
      <div className="mb-3 flex flex-wrap items-center gap-2">
        <div
          className={cn(
            'flex min-w-52 flex-1 items-center gap-2 rounded-field border border-line bg-sunken px-3',
            'transition-[border-color,background-color] duration-[var(--dur)] ease-[var(--ease)]',
            'focus-within:border-accent focus-within:bg-surface focus-within:ring-2 focus-within:ring-accent/25',
          )}
        >
          <SearchIcon className="size-4 shrink-0 text-ink-faint" />
          <input
            value={search}
            onChange={(event) => setSearch(event.target.value)}
            placeholder="Search users by name or email"
            aria-label="Search users"
            className="h-10 w-full bg-transparent text-sm text-ink outline-none placeholder:text-ink-faint"
          />
          {search ? (
            <button
              type="button"
              onClick={() => setSearch('')}
              aria-label="Clear search"
              className="press grid size-5 shrink-0 place-items-center rounded text-ink-faint transition-[background-color,border-color,color,box-shadow] duration-[var(--dur-fast)] ease-[var(--ease)] hover:text-ink"
            >
              <CloseIcon className="size-3.5" />
            </button>
          ) : null}
        </div>
        <Button onClick={() => setCreateOpen(true)}>
          <PlusIcon className="size-4" />
          Add user
        </Button>
      </div>

      {error ? (
        <div className="mb-3">
          <ErrorNote>{error}</ErrorNote>
        </div>
      ) : null}

      <Card className="overflow-hidden">
        {users.length === 0 ? (
          <EmptyState
            icon={<ProfileIcon />}
            title={query ? `Nothing matches “${query}”` : 'No users yet'}
            description={query ? undefined : 'Create the first account to get started.'}
          />
        ) : (
          <ul>
            {users.map((user, index) => (
              <li
                key={user.id}
                style={staggerStyle(index)}
                className={cn(
                  'reveal-row flex flex-wrap items-center gap-3 border-b border-line px-4 py-3 last:border-0 sm:px-5',
                  !user.is_active && 'bg-payable-soft/40',
                )}
              >
                <Avatar
                  size="md"
                  tone={user.is_active ? 'neutral' : 'payable'}
                  identity={user.is_active ? user.name || user.email : undefined}
                >
                  {initials(user.name || user.email)}
                </Avatar>

                <div className="min-w-40 flex-1">
                  <p className="flex flex-wrap items-center gap-2 text-[0.875rem] font-medium text-ink">
                    <span className="truncate">{user.name || '—'}</span>
                    {user.is_admin ? <Badge tone="accent">Admin</Badge> : null}
                    {!user.is_active ? <Badge tone="payable">Disabled</Badge> : null}
                    {user.id === currentUserId ? <Badge tone="muted">You</Badge> : null}
                  </p>
                  <p className="truncate text-[0.75rem] text-ink-faint">
                    {user.email} · {user.people_count} people · {user.transaction_count} transactions
                    {user.last_sign_in_at
                      ? ` · seen ${relativeTime(user.last_sign_in_at)}`
                      : ' · never signed in'}
                  </p>
                </div>

                {/* Four buttons per row, repeated down the list, made the
                    directory read as a control panel: the controls outweighed
                    the accounts they belonged to, and the destructive one sat
                    permanently a single click away. They move into a menu,
                    which changes where the actions live and nothing about who
                    may run them — every guard below is the same guard, and the
                    server actions behind them are untouched. */}
                <div className="flex shrink-0 items-center gap-1.5">
                  <Menu
                    label={user.name || user.email}
                    items={[
                      {
                        label: 'Reset password',
                        description: 'Set a new password and hand it over.',
                        onSelect: () => setResetting(user),
                      },
                      {
                        label: user.is_admin ? 'Revoke admin' : 'Make admin',
                        description:
                          user.id === currentUserId
                            ? 'You cannot change your own admin role.'
                            : undefined,
                        disabled: user.id === currentUserId,
                        onSelect: () => setConfirming({ user, kind: 'admin' }),
                      },
                      {
                        label: user.is_active ? 'Disable account' : 'Enable account',
                        description:
                          user.id === currentUserId
                            ? 'You cannot disable your own account.'
                            : user.is_active
                              ? 'They keep their data and cannot sign in.'
                              : undefined,
                        disabled: user.id === currentUserId,
                        onSelect: () => setConfirming({ user, kind: 'toggle' }),
                      },
                      {
                        // Still the only irreversible action here, so it is
                        // still the only one that carries the payable red — and
                        // it still goes through the same confirmation.
                        label: 'Delete account',
                        description:
                          user.id === currentUserId
                            ? 'You cannot delete your own account.'
                            : 'Permanent, along with every record in it.',
                        destructive: true,
                        disabled: user.id === currentUserId,
                        onSelect: () => setConfirming({ user, kind: 'delete' }),
                      },
                    ]}
                  />
                </div>
              </li>
            ))}
          </ul>
        )}
      </Card>

      {total > users.length ? (
        <p className="mt-3 text-[0.8125rem] text-ink-faint">
          Showing {users.length} of {total}. Narrow the search to find someone specific.
        </p>
      ) : null}

      <CreateUserModal open={createOpen} onClose={() => setCreateOpen(false)} />
      <ResetPasswordModal user={resetting} onClose={() => setResetting(null)} />

      <ConfirmDialog
        open={confirming?.kind === 'toggle'}
        onClose={() => setConfirming(null)}
        onConfirm={() =>
          confirming &&
          run(
            () => adminSetUserActive(confirming.user.id, !confirming.user.is_active),
            confirming.user.is_active ? 'Account disabled' : 'Account enabled',
          )
        }
        pending={pending}
        tone={confirming?.user.is_active ? 'danger' : 'primary'}
        confirmLabel={confirming?.user.is_active ? 'Disable' : 'Enable'}
        title={
          confirming?.user.is_active
            ? `Disable ${confirming.user.name || confirming.user.email}?`
            : `Enable ${confirming?.user.name || confirming?.user.email}?`
        }
        body={
          confirming?.user.is_active
            ? 'They will be signed out of their data immediately — the database refuses their requests, not just the interface. Their records are kept and come back if you enable them again.'
            : 'They will be able to sign in and reach their workspace again.'
        }
      />

      <ConfirmDialog
        open={confirming?.kind === 'admin'}
        onClose={() => setConfirming(null)}
        onConfirm={() =>
          confirming &&
          run(
            () => adminSetUserAdmin(confirming.user.email, !confirming.user.is_admin),
            confirming.user.is_admin ? 'Administrator access removed' : 'Administrator access granted',
          )
        }
        tone={confirming?.user.is_admin ? 'danger' : 'primary'}
        confirmLabel={confirming?.user.is_admin ? 'Revoke admin' : 'Make admin'}
        title={
          confirming?.user.is_admin
            ? `Remove administrator access from ${confirming.user.name || confirming.user.email}?`
            : `Make ${confirming?.user.name || confirming?.user.email} an administrator?`
        }
        body={
          confirming?.user.is_admin
            ? 'They keep their own ledger and their own data. They lose this page, and with it the ability to see or change anyone else’s account.'
            : 'They gain this page: every account on the system, the ability to enable, disable and delete them, and to reset anyone’s password. Their own ledger is unaffected.'
        }
      />

      <ConfirmDialog
        open={confirming?.kind === 'delete'}
        onClose={() => setConfirming(null)}
        onConfirm={() =>
          confirming && run(() => adminDeleteUser(confirming.user.id), 'Account deleted')
        }
        pending={pending}
        confirmLabel="Delete permanently"
        title={`Delete ${confirming?.user.name || confirming?.user.email}?`}
        body={
          <>
            This permanently removes the account and everything in it —{' '}
            {confirming?.user.people_count} people and {confirming?.user.transaction_count}{' '}
            transactions. It cannot be undone. Disabling the account keeps the data.
          </>
        }
      />
    </>
  );
}

/* -------------------------------------------------------------------------- */

function CreateUserModal({ open, onClose }: { open: boolean; onClose: () => void }) {
  const router = useRouter();
  const [state, formAction] = useActionState<ActionResult<{ id: string; email: string }> | null, FormData>(
    adminCreateUser,
    null,
  );

  // useActionState keeps the last result for the life of the component, so a
  // success effect must be keyed on the result's identity — otherwise simply
  // reopening this sheet replays the success it recorded last time.
  const handled = useRef<ActionResult<{ id: string; email: string }> | null>(null);

  useEffect(() => {
    if (!state?.ok || handled.current === state) return;
    handled.current = state;
    onClose();
    router.refresh();
  }, [state, onClose, router]);

  const fieldError = (field: string) =>
    state && !state.ok && state.field === field ? state.error : undefined;

  return (
    <Modal
      open={open}
      onClose={onClose}
      title="Add user"
      description="They can sign in immediately with this email and password."
      size="lg"
    >
      <form action={formAction} className="space-y-4" noValidate>
        {state && !state.ok && !state.field ? <ErrorNote>{state.error}</ErrorNote> : null}

        <div className="grid gap-4 sm:grid-cols-2">
          <Field label="Name" htmlFor="new-name" error={fieldError('name')}>
            <Input id="new-name" name="name" data-autofocus="true" maxLength={120} required />
          </Field>
          <Field label="Email" htmlFor="new-email" error={fieldError('email')}>
            <Input id="new-email" name="email" type="email" required />
          </Field>
        </div>

        <div className="grid gap-4 sm:grid-cols-2">
          <Field label="Business name" htmlFor="new-business" hint="Optional">
            <Input id="new-business" name="business_name" maxLength={120} />
          </Field>
          <Field label="Currency" htmlFor="new-currency" error={fieldError('currency')}>
            <Select id="new-currency" name="currency" defaultValue="INR">
              {CURRENCIES.map((code) => (
                <option key={code} value={code}>
                  {code}
                </option>
              ))}
            </Select>
          </Field>
        </div>

        <Field
          label="Temporary password"
          htmlFor="new-password"
          hint="At least 10 characters with upper case, lower case and a number. Share it privately."
          error={fieldError('password')}
        >
          <Input id="new-password" name="password" type="text" autoComplete="off" required />
        </Field>

        <SubmitRow label="Create user" onCancel={onClose} />
      </form>
    </Modal>
  );
}

function ResetPasswordModal({ user, onClose }: { user: AdminUser | null; onClose: () => void }) {
  const [state, formAction] = useActionState<ActionResult<null> | null, FormData>(
    adminResetPassword,
    null,
  );
  const [done, setDone] = useState(false);

  const handled = useRef<ActionResult<null> | null>(null);

  useEffect(() => {
    if (!state?.ok || handled.current === state) return;
    handled.current = state;
    setDone(true);
  }, [state]);

  useEffect(() => {
    if (user) setDone(false);
  }, [user]);

  if (!user) return null;

  return (
    <Modal
      open
      onClose={onClose}
      title={`Reset password for ${user.name || user.email}`}
      description="They are not emailed. Share the new password with them directly."
    >
      {done ? (
        <div className="space-y-4">
          <SuccessNote>The password has been changed.</SuccessNote>
          <Button full onClick={onClose}>
            Done
          </Button>
        </div>
      ) : (
        <form action={formAction} className="space-y-4" noValidate>
          {state && !state.ok && !state.field ? <ErrorNote>{state.error}</ErrorNote> : null}
          <input type="hidden" name="user_id" value={user.id} />

          <Field
            label="New password"
            htmlFor="reset-password"
            hint="At least 10 characters with upper case, lower case and a number."
            error={state && !state.ok && state.field === 'password' ? state.error : undefined}
          >
            <Input
              id="reset-password"
              name="password"
              type="text"
              data-autofocus="true"
              autoComplete="off"
              required
            />
          </Field>

          <SubmitRow label="Set password" onCancel={onClose} />
        </form>
      )}
    </Modal>
  );
}

export function InlineSpinner() {
  return <Spinner className="text-ink-faint" />;
}
