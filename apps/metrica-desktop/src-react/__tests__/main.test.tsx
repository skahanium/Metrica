import { describe, expect, it, vi } from 'vitest';

describe('main', () => {
  it('registers AG Grid Community modules before rendering the app', async () => {
    vi.resetModules();

    const allCommunityModule = { moduleName: 'AllCommunityModule' };
    const registerModules = vi.fn();
    vi.doMock('ag-grid-community', () => ({
      AllCommunityModule: allCommunityModule,
      ModuleRegistry: { registerModules },
    }));

    const render = vi.fn();
    vi.doMock('react-dom/client', () => ({
      createRoot: vi.fn(() => ({ render })),
    }));
    vi.doMock('../components/App', () => ({
      App: () => null,
    }));

    document.body.innerHTML = '<div id="root"></div>';

    await import('../main');

    expect(registerModules).toHaveBeenCalledWith([allCommunityModule]);
  });
});
