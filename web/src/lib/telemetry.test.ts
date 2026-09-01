import { describe, expect, it } from 'vitest';

import {
  fingerprint,
  sanitiseContext,
  sanitiseMessage,
  sanitiseRoute,
} from './telemetry';

/**
 * What a crash report is allowed to say (Phase 2).
 *
 * The whole point of these: a report has to answer "where did it fail and what
 * was the user doing" without answering "what are this user's financial
 * records". Every case below is a way the second could leak through the first.
 */

describe('sanitiseMessage', () => {
  it('keeps the sentence', () => {
    expect(sanitiseMessage('Failed to load the dashboard')).toBe(
      'Failed to load the dashboard',
    );
  });

  it('strips anything money-shaped', () => {
    expect(sanitiseMessage('Could not settle 12,500.00')).toBe(
      'Could not settle [amount]',
    );
    expect(sanitiseMessage('balance 1234.56 remains')).toBe('balance [amount] remains');
    expect(sanitiseMessage('₹1,00,000 outstanding')).toContain('[amount]');
  });

  it('strips an email address', () => {
    expect(sanitiseMessage('rejected for rahul.kumar@example.com')).toBe(
      'rejected for [email]',
    );
  });

  it('strips a phone number and any long digit run', () => {
    expect(sanitiseMessage('called +919812345678')).toBe('called +[number]');
  });

  it('strips an entry or person id', () => {
    expect(sanitiseMessage('person 3f1a2b4c-5d6e-4f70-8901-abcdef123456 missing')).toBe(
      'person [id] missing',
    );
  });

  it('strips anything token-shaped', () => {
    expect(
      sanitiseMessage('Authorization failed: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9abcdef'),
    ).toBe('Authorization failed: [token]');
  });

  it('takes an Error as readily as a string', () => {
    expect(sanitiseMessage(new Error('boom 4,000.00'))).toBe('boom [amount]');
  });

  it('never grows without limit', () => {
    expect(sanitiseMessage('x'.repeat(900)).length).toBe(500);
  });

  it('leaves a note-shaped string with no numbers in it — which is why context is a whitelist', () => {
    // A note IS private, and sanitising cannot detect that. It never reaches
    // here: `sanitiseContext` drops the key, and so does the RPC.
    expect(sanitiseContext({ screen: 'person' } as never)).toEqual({ screen: 'person' });
    expect(sanitiseContext({ note: 'rent for August' } as never)).toEqual({});
  });
});

describe('sanitiseContext', () => {
  it('keeps the whitelisted keys, and only scalars', () => {
    expect(
      sanitiseContext({
        screen: 'dashboard',
        status_code: 500,
        is_offline: true,
        attempt: 2,
      }),
    ).toEqual({ screen: 'dashboard', status_code: 500, is_offline: true, attempt: 2 });
  });

  it('drops everything else, whatever it is called', () => {
    expect(
      sanitiseContext({
        amount_minor: 1250000,
        person_name: 'Rahul Kumar',
        note: 'rent',
        access_token: 'secret',
      } as never),
    ).toEqual({});
  });

  it('sanitises the values it does keep', () => {
    expect(sanitiseContext({ screen: 'settle 12,500.00' })).toEqual({
      screen: 'settle [amount]',
    });
  });

  it('skips null and undefined rather than sending them', () => {
    expect(sanitiseContext({ screen: null, action: undefined })).toEqual({});
  });
});

describe('sanitiseRoute', () => {
  it('keeps the screen and loses the person', () => {
    expect(sanitiseRoute('/people/3f1a2b4c-5d6e-4f70-8901-abcdef123456')).toBe(
      '/people/[id]',
    );
  });

  it('drops the query string, which is where filters and search terms live', () => {
    expect(sanitiseRoute('/activity?q=rahul&from=2026-01-01')).toBe('/activity');
  });

  it('passes a plain route through', () => {
    expect(sanitiseRoute('/profile')).toBe('/profile');
    expect(sanitiseRoute(null)).toBeNull();
  });
});

describe('fingerprint', () => {
  it('is the same for two occurrences of one fault', () => {
    const a = fingerprint({
      errorType: 'PostgrestException',
      message: 'Failed to settle 12,500.00 for rahul@example.com',
      operation: 'create_settlement',
    });
    const b = fingerprint({
      errorType: 'PostgrestException',
      message: 'Failed to settle 300.00 for priya@example.com',
      operation: 'create_settlement',
    });

    expect(a).toBe(b);
  });

  it('differs for a different fault', () => {
    const settle = fingerprint({
      errorType: 'PostgrestException',
      message: 'Failed to settle',
      operation: 'create_settlement',
    });
    const load = fingerprint({
      errorType: 'TypeError',
      message: 'Cannot read properties of undefined',
      operation: 'load_dashboard',
    });

    expect(settle).not.toBe(load);
  });

  it('carries nothing private itself', () => {
    const value = fingerprint({
      errorType: 'Error',
      message: 'settle 12,500.00 for rahul@example.com on +919812345678',
      operation: 'create_settlement',
    });

    expect(value).not.toMatch(/\d{3,}|@/);
    expect(value.length).toBeLessThanOrEqual(64);
  });
});
