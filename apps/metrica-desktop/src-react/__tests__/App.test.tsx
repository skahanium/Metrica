import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { useState } from 'react';
import { act, cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { App } from '../components/App';
import { useAppStore } from '../stores/appStore';
import { useCommandStore } from '../stores/commandStore';
import { useDatasetStore } from '../stores/datasetStore';
import { useMessageStore } from '../stores/messageStore';
import { useModelStore } from '../stores/modelStore';
import { useTransformStore } from '../stores/transformStore';

const localStorageMock = (() => {
  let store: Record<string, string> = {};
  return {
    getItem: vi.fn((key: string) => store[key] ?? null),
    setItem: vi.fn((key: string, value: string) => { store[key] = value; }),
    removeItem: vi.fn((key: string) => { delete store[key]; }),
    clear: vi.fn(() => { store = {}; }),
  };
})();
Object.defineProperty(globalThis, 'localStorage', { value: localStorageMock });

const runtimeMocks = vi.hoisted(() => ({
  checkHealth: vi.fn(),
  fitModel: vi.fn(),
  inspectDataset: vi.fn(),
  queryDataset: vi.fn(),
}));

vi.mock('../services/runtimeClient', () => ({
  checkHealth: (...args: unknown[]) => runtimeMocks.checkHealth(...args),
  fitModel: (...args: unknown[]) => runtimeMocks.fitModel(...args),
  inspectDataset: (...args: unknown[]) => runtimeMocks.inspectDataset(...args),
  runDataCommand: (...args: unknown[]) => runtimeMocks.queryDataset(...args),
}));

vi.mock('../services/healthPolling', () => ({
  startHealthPolling: vi.fn(),
  stopHealthPolling: vi.fn(),
  MAX_RESTARTS: 3,
}));

vi.mock('../components/ResultFlow', () => ({
  ResultFlow: () => <div data-testid="result-flow" />,
}));

vi.mock('../components/DataFullscreen', () => ({
  DataFullscreen: () => <div data-testid="data-fullscreen" />,
}));

vi.mock('../components/CommandLine', () => ({
  CommandLine: ({
    onExecute,
    feedback,
  }: {
    onExecute: (input: string) => void | boolean | Promise<void | boolean>;
    feedback?: { message: string } | null;
  }) => {
    const [value, setValue] = useState('');
    return (
      <div>
        <input
          placeholder="输入命令... (regress / summarize / describe / ...)"
          value={value}
          onChange={(event) => {
            setValue(event.target.value);
            useCommandStore.getState().setInput(event.target.value, event.target.value.length);
          }}
          onKeyDown={(event) => {
            if (event.key === 'Enter') {
              void onExecute(value);
            }
          }}
        />
        {feedback ? <div data-testid="cli-feedback">{feedback.message}</div> : null}
      </div>
    );
  },
}));

describe('App command error classification', () => {
  beforeEach(() => {
    runtimeMocks.checkHealth.mockReset();
    runtimeMocks.fitModel.mockReset();
    runtimeMocks.inspectDataset.mockReset();
    runtimeMocks.queryDataset.mockReset();
    runtimeMocks.checkHealth.mockReturnValue(new Promise(() => {}));
    useAppStore.setState({
      error: null,
      isLoading: false,
      juliaHealthy: true,
      healthChecked: true,
      restartCount: 0,
      healthPollingId: null,
      dataFullscreen: false,
    });
    useCommandStore.setState({
      input: '',
      cursorPos: 0,
      context: null,
      completions: [],
      selectedCompletionIdx: 0,
      ghostText: null,
      showCompletions: false,
      correction: null,
      history: [],
      historyIdx: -1,
      lastParsed: null,
      parseError: null,
    });
    useDatasetStore.setState({
      sourcePath: '',
      activePath: '',
      summary: null,
      browseColumns: null,
      browseReadonly: false,
    });
    useMessageStore.setState({ messages: [], trash: [], selectedIds: new Set(), selectionMode: 'none' });
    useModelStore.setState({
      lastResult: null,
      modelHistory: [],
    });
    useTransformStore.setState({
      operations: [],
      history: [],
      resultItems: [],
      lastTransformResult: null,
      isTransforming: false,
    });
  });

  afterEach(() => {
    cleanup();
  });

  it('shows unknown commands in cli feedback instead of the global error alert', async () => {
    render(<App />);

    const input = screen.getByPlaceholderText(/输入命令/) as HTMLInputElement;
    await act(async () => {
      fireEvent.change(input, { target: { value: 'zz' } });
      fireEvent.keyDown(input, { key: 'Enter' });
    });

    expect((await screen.findByTestId('cli-feedback')).textContent).toContain('未知命令：zz');
    expect(useAppStore.getState().error).toBeNull();
    expect(useCommandStore.getState().input).toBe('zz');
  });

  it('shows missing dataset guard in cli feedback', async () => {
    render(<App />);

    const input = screen.getByPlaceholderText(/输入命令/) as HTMLInputElement;
    await act(async () => {
      fireEvent.change(input, { target: { value: 'regress y x1' } });
      fireEvent.keyDown(input, { key: 'Enter' });
    });

    expect((await screen.findByTestId('cli-feedback')).textContent).toContain('请先加载数据集');
    expect(useAppStore.getState().error).toBeNull();
  });

  it('keeps model runtime failures in the global error channel', async () => {
    useDatasetStore.setState({
      sourcePath: '/tmp/demo.csv',
      activePath: '/tmp/demo.csv',
      summary: { nrows: 2, ncols: 0, columns: [], preview: [] },
    });
    runtimeMocks.fitModel.mockRejectedValue(new Error('模型拟合失败'));

    render(<App />);
    const input = screen.getByPlaceholderText(/输入命令/) as HTMLInputElement;
    await act(async () => {
      fireEvent.change(input, { target: { value: 'regress y x1' } });
      fireEvent.keyDown(input, { key: 'Enter' });
    });

    await waitFor(() => {
      expect(useAppStore.getState().error).toBe('模型拟合失败');
    });
    expect(screen.queryByTestId('cli-feedback')).toBeNull();
  });

  it('dispatches summarize through query_dataset and appends a data message', async () => {
    useDatasetStore.setState({
      sourcePath: '/tmp/demo.csv',
      activePath: '/tmp/demo.csv',
      summary: { nrows: 2, ncols: 1, columns: [{ name: 'y', inferred_type: 'Float64', missing_count: 0 }], preview: [{ y: 1 }, { y: 2 }] },
    });
    runtimeMocks.queryDataset.mockResolvedValue({
      kind: 'summarize',
      dataset_summary: { row_count: 2, column_count: 1 },
      variables: [{ name: 'y', inferred_type: 'Float64', obs: 2, mean: 1.5, std_dev: 0.7071, min: 1, max: 2 }],
    });

    render(<App />);
    const input = screen.getByPlaceholderText(/输入命令/) as HTMLInputElement;
    await act(async () => {
      fireEvent.change(input, { target: { value: 'summarize y' } });
      fireEvent.keyDown(input, { key: 'Enter' });
    });

    await waitFor(() => {
      expect(runtimeMocks.queryDataset).toHaveBeenCalled();
    });
    expect(useMessageStore.getState().messages[0].kind).toBe('data');
    expect(useMessageStore.getState().messages[0].data_result?.kind).toBe('summarize');
  });

  it('opens browse in readonly fullscreen mode with filtered columns', async () => {
    useDatasetStore.setState({
      sourcePath: '/tmp/demo.csv',
      activePath: '/tmp/demo.csv',
      summary: {
        nrows: 2,
        ncols: 2,
        columns: [
          { name: 'y', inferred_type: 'Float64', missing_count: 0 },
          { name: 'x1', inferred_type: 'Float64', missing_count: 0 },
        ],
        preview: [{ y: 1, x1: 3 }, { y: 2, x1: 4 }],
      },
    });
    runtimeMocks.queryDataset.mockResolvedValue({
      kind: 'browse',
      readonly: true,
      columns: [{ name: 'x1', inferred_type: 'Float64' }],
    });

    render(<App />);
    const input = screen.getByPlaceholderText(/输入命令/) as HTMLInputElement;
    await act(async () => {
      fireEvent.change(input, { target: { value: 'browse x1' } });
      fireEvent.keyDown(input, { key: 'Enter' });
    });

    await waitFor(() => {
      expect(runtimeMocks.queryDataset).toHaveBeenCalled();
    });
    expect(useAppStore.getState().dataFullscreen).toBe(true);
    expect(useDatasetStore.getState().browseReadonly).toBe(true);
    expect(useDatasetStore.getState().browseColumns).toEqual(['x1']);
  });
});
