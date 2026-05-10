import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act, cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { App } from '../components/App';
import { useAppStore } from '../stores/appStore';
import { useCommandStore } from '../stores/commandStore';
import { useDatasetStore } from '../stores/datasetStore';
import { useModelStore } from '../stores/modelStore';
import { useTransformStore } from '../stores/transformStore';

const runtimeMocks = vi.hoisted(() => ({
  checkHealth: vi.fn(),
  fitModel: vi.fn(),
  inspectDataset: vi.fn(),
}));
const originalAppActions = useAppStore.getState();

vi.mock('../services/runtimeClient', () => ({
  checkHealth: (...args: unknown[]) => runtimeMocks.checkHealth(...args),
  fitModel: (...args: unknown[]) => runtimeMocks.fitModel(...args),
  inspectDataset: (...args: unknown[]) => runtimeMocks.inspectDataset(...args),
}));

vi.mock('../components/Header', () => ({
  Header: () => <div data-testid="header" />,
}));

vi.mock('../components/Sidebar', () => ({
  Sidebar: () => <div data-testid="sidebar" />,
}));

vi.mock('../components/ResultFlow', () => ({
  ResultFlow: () => <div data-testid="result-flow" />,
}));

vi.mock('../components/DataFullscreen', () => ({
  DataFullscreen: () => <div data-testid="data-fullscreen" />,
}));

describe('App command error classification', () => {
  beforeEach(() => {
    runtimeMocks.checkHealth.mockReset();
    runtimeMocks.fitModel.mockReset();
    runtimeMocks.inspectDataset.mockReset();
    runtimeMocks.checkHealth.mockReturnValue(new Promise(() => {}));
    useAppStore.setState({
      error: null,
      isLoading: false,
      juliaHealthy: true,
      restartCount: 0,
      healthPollingId: null,
      dataFullscreen: false,
      startHealthPolling: vi.fn(),
      stopHealthPolling: vi.fn(),
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
    });
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
    useAppStore.setState({
      startHealthPolling: originalAppActions.startHealthPolling,
      stopHealthPolling: originalAppActions.stopHealthPolling,
    });
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
});
