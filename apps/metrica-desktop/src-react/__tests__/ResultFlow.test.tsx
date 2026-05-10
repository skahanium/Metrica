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
    useAppStore.setState({ teachingEnabled: true });
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
          variables: [{ name: 'y', inferred_type: 'Float64', obs: 2, mean: 1.5, std_dev: 0.7, min: 1, max: 2 }],
        },
        created_at: '2026-05-10T00:00:00.000Z',
        is_deleted: false,
      }],
    });

    render(<ResultFlow onRerun={() => undefined} />);

    expect(screen.getByText(/summarize y/)).toBeDefined();
    expect(screen.getAllByText('Obs').length).toBeGreaterThan(0);
    expect(screen.getByText('1.5000')).toBeDefined();
  });

  it('blocks legacy model-style payloads for data viewing commands', () => {
    useMessageStore.setState({
      messages: [{
        id: 'legacy-data-1',
        kind: 'result',
        command: 'describe',
        result: {
          glance: { model: 'describe', nobs: 8, dof: 0, metrics: {} },
          tidy: [],
          diagnostics: {},
          warnings: [],
        },
        created_at: '2026-05-10T00:00:00.000Z',
        is_deleted: false,
      }],
    });

    render(<ResultFlow onRerun={() => undefined} />);

    expect(screen.getByText('检测到旧版错误结果')).toBeDefined();
    expect(screen.queryByText('模型')).toBeNull();
  });
});
