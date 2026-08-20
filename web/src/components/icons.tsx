import type { SVGProps } from 'react';

/**
 * Icon set. Hand-rolled 24px strokes rather than an icon package: the app needs
 * a dozen glyphs, and shipping a whole library for them would cost more bundle
 * than the icons are worth (context.md §23).
 */

type IconProps = SVGProps<SVGSVGElement>;

function Icon({ children, ...props }: IconProps) {
  return (
    <svg
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={1.75}
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden
      className="size-5"
      {...props}
    >
      {children}
    </svg>
  );
}

export const HomeIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M3 10.5 12 3l9 7.5" />
    <path d="M5 9.5V20h14V9.5" />
    <path d="M9.5 20v-5.5h5V20" />
  </Icon>
);

export const PeopleIcon = (p: IconProps) => (
  <Icon {...p}>
    <circle cx="9" cy="8" r="3.25" />
    <path d="M2.75 19.25c.6-3.2 3.2-5 6.25-5s5.65 1.8 6.25 5" />
    <path d="M16.5 5.5a3 3 0 0 1 0 5.8" />
    <path d="M18 14.6c2 .6 3.4 2.2 3.8 4.65" />
  </Icon>
);

export const ActivityIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M3 12h4l2.5-6 5 12 2.5-6h4" />
  </Icon>
);

export const ProfileIcon = (p: IconProps) => (
  <Icon {...p}>
    <circle cx="12" cy="8" r="3.5" />
    <path d="M4.5 20c.9-3.6 3.8-5.5 7.5-5.5s6.6 1.9 7.5 5.5" />
  </Icon>
);

export const PlusIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M12 5v14M5 12h14" />
  </Icon>
);

export const SearchIcon = (p: IconProps) => (
  <Icon {...p}>
    <circle cx="10.5" cy="10.5" r="6.25" />
    <path d="m15.2 15.2 4.3 4.3" />
  </Icon>
);

export const ArrowDownIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M12 4.5v15M6.5 14l5.5 5.5L17.5 14" />
  </Icon>
);

export const ArrowUpIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M12 19.5v-15M6.5 10 12 4.5 17.5 10" />
  </Icon>
);

export const CheckIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="m4.5 12.5 5 5 10-11" />
  </Icon>
);

export const CloseIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="m6 6 12 12M18 6 6 18" />
  </Icon>
);

export const ChevronRightIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="m9 5 7 7-7 7" />
  </Icon>
);

export const SettleIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M4 8h13l-2.5-2.5" />
    <path d="M20 16H7l2.5 2.5" />
  </Icon>
);

export const AdminIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M12 3.5 5 6.5v5.2c0 4.2 2.8 7.3 7 8.8 4.2-1.5 7-4.6 7-8.8V6.5Z" />
    <path d="m9.2 12.2 2 2 3.6-3.8" />
  </Icon>
);

export const ArchiveIcon = (p: IconProps) => (
  <Icon {...p}>
    <rect x="3.5" y="4.5" width="17" height="4" rx="1" />
    <path d="M5 8.5V19a.5.5 0 0 0 .5.5h13a.5.5 0 0 0 .5-.5V8.5" />
    <path d="M10 12.5h4" />
  </Icon>
);

export const EditIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M4 20h4L19 9a2.1 2.1 0 0 0-3-3L5 17Z" />
    <path d="m14.5 6.5 3 3" />
  </Icon>
);

export const WalletIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M3.5 7.5A2 2 0 0 1 5.5 5.5H17a1 1 0 0 1 1 1v2" />
    <rect x="3.5" y="7.5" width="17" height="11" rx="2" />
    <circle cx="16.5" cy="13" r="1.15" fill="currentColor" stroke="none" />
  </Icon>
);

export const ArrowRightIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M4.5 12h15M13.5 6l6 6-6 6" />
  </Icon>
);

export const LockIcon = (p: IconProps) => (
  <Icon {...p}>
    <rect x="4.5" y="10" width="15" height="10" rx="2.5" />
    <path d="M8 10V7.5a4 4 0 0 1 8 0V10" />
  </Icon>
);

export const GlobeIcon = (p: IconProps) => (
  <Icon {...p}>
    <circle cx="12" cy="12" r="8.25" />
    <path d="M3.9 9.5h16.2M3.9 14.5h16.2" />
    <path d="M12 3.75c-4 5-4 11.5 0 16.5 4-5 4-11.5 0-16.5Z" />
  </Icon>
);

export const SignOutIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M14 4.5H6.5a2 2 0 0 0-2 2v11a2 2 0 0 0 2 2H14" />
    <path d="M17 8.5 20.5 12 17 15.5M20 12H10" />
  </Icon>
);

export const ChevronDownIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="m5 9 7 7 7-7" />
  </Icon>
);

export const TrendUpIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M3.5 16.5 9.5 10l3.5 3.5 7-7.5" />
    <path d="M15.5 6h5v5" />
  </Icon>
);

export const MenuIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M4 7h16M4 12h16M4 17h16" />
  </Icon>
);

export const SunIcon = (p: IconProps) => (
  <Icon {...p}>
    <circle cx="12" cy="12" r="4" />
    <path d="M12 2.75v2M12 19.25v2M4.22 4.22l1.42 1.42M18.36 18.36l1.42 1.42M2.75 12h2M19.25 12h2M4.22 19.78l1.42-1.42M18.36 5.64l1.42-1.42" />
  </Icon>
);

export const MoonIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M20 14.5A8.2 8.2 0 0 1 9.5 4 8.25 8.25 0 1 0 20 14.5Z" />
  </Icon>
);

export const MonitorIcon = (p: IconProps) => (
  <Icon {...p}>
    <rect x="3" y="4.5" width="18" height="12" rx="2" />
    <path d="M8.5 20h7M12 16.5V20" />
  </Icon>
);

export const CreditIcon = (p: IconProps) => (
  <Icon {...p}>
    <circle cx="12" cy="12" r="8.25" />
    <path d="M12 8v8M8.5 12.5 12 16l3.5-3.5" />
  </Icon>
);

export const DebitIcon = (p: IconProps) => (
  <Icon {...p}>
    <circle cx="12" cy="12" r="8.25" />
    <path d="M12 16V8M8.5 11.5 12 8l3.5 3.5" />
  </Icon>
);

export const SparkIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M12 3.5 13.7 9l5.5 1.7-5.5 1.7L12 18l-1.7-5.6L4.8 10.7 10.3 9Z" />
  </Icon>
);

export const ImportIcon = (p: IconProps) => (
  <Icon {...p}>
    <path d="M12 3.5v11M8 11l4 3.5 4-3.5" />
    <path d="M4.5 16.5v2a2 2 0 0 0 2 2h11a2 2 0 0 0 2-2v-2" />
  </Icon>
);

export const PersonPlusIcon = (p: IconProps) => (
  <Icon {...p}>
    <circle cx="10" cy="8" r="3.5" />
    <path d="M3.5 20c.8-3.4 3.4-5.2 6.5-5.2 1 0 1.9.2 2.7.5" />
    <path d="M17 14.5v6M14 17.5h6" />
  </Icon>
);
