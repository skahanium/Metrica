import { beforeEach, describe, expect, it, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import { ResultFlow } from '../components/ResultFlow';
import { useMessageStore } from '../stores/messageStore';
import { useAppStore } from '../stores/appStore';

vi.mock('./../components/MessageToolbar', () => ({
  MessageToolbar: () => <div data-testid="message-toolbar" />,
}));

describe('ResultFlow', () => {
  beforeEach(() => {
    useMessageStore.setState({ messages: [], trash: [], selectedIds: new Set(), selectionMode: 'none' });
    useAppStore.setState({ dataFullscreen: false, trashVisible: false, dataHistoryVisible: false });
  });

  it('renders structured data command results', () => {
    useMessageStore.setState({
      messages: [{
        id: 'data-1',
        kind: 'data',
        command: 'summarize y',
        data_result: {
          kind: 'summarize',
          dataset_summary: { row_count: 2, column_count: 1 },
          variables: [{
            name: 'y', dtype: 'Float64', inferred_type: 'Float64',
            obs: 2, mean: 1.5, std_dev: 0.7, min: 1, max: 2,
            p25: 1.25, p50: 1.5, p75: 1.75,
          }],
        },
        created_at: '2026-05-10T00:00:00.000Z',
        is_deleted: false,
      }],
    });

    render(<ResultFlow />);

    expect(screen.getByText(/summarize y/)).toBeDefined();
    expect(screen.getAllByText('N').length).toBeGreaterThan(0);
    expect(screen.getAllByText('1.5000').length).toBeGreaterThan(0);
  });

  it('renders model results without legacy detection', () => {
    useMessageStore.setState({
      messages: [{
        id: 'model-1',
        kind: 'result',
        command: 'regress y x1',
        result: {
          glance: { model: 'ols', nobs: 100, dof: 97, metrics: { r2: 0.75 } },
          tidy: [{ term: 'x1', estimate: 2.5, std_error: 0.3, statistic: 8.33, p_value: 0.001 }],
          diagnostics: {},
          warnings: [],
        },
        created_at: '2026-05-10T00:00:00.000Z',
        is_deleted: false,
      }],
    });

    render(<ResultFlow />);

    expect(screen.getByText(/regress y x1/)).toBeDefined();
  });
});
