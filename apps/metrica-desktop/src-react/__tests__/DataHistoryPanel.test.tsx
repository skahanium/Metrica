import { beforeEach, describe, expect, it } from 'vitest';
import { fireEvent, render, screen } from '@testing-library/react';
import { DataHistoryPanel } from '../components/DataHistoryPanel';
import { useDatasetStore } from '../stores/datasetStore';
import { useAppStore } from '../stores/appStore';
import type { DataHistoryNode } from '../types/protocol';

const makeNode = (op: string, overrides?: Partial<DataHistoryNode>): DataHistoryNode => ({
  state_id: `state-${op}`,
  source_state_id: null,
  op_type: op,
  op_args: {},
  active_data_path: `/tmp/${op}.csv`,
  row_count_before: 100,
  row_count_after: 90,
  col_count_before: 5,
  col_count_after: 5,
  notes: [],
  warnings: [],
  created_at: '2025-01-01T00:00:00Z',
  ...overrides,
});

describe('DataHistoryPanel', () => {
  beforeEach(() => {
    useDatasetStore.setState({
      dataHistory: [],
      currentHistoryIndex: -1,
    });
    useAppStore.setState({ dataHistoryVisible: false });
  });

  it('shows empty state when no history', () => {
    useAppStore.setState({ dataHistoryVisible: true });
    render(<DataHistoryPanel />);
    expect(screen.getByText('暂无数据变换历史。')).toBeDefined();
  });

  it('renders timeline nodes with operation labels', () => {
    const nodes = [
      makeNode('filter'),
      makeNode('rename'),
    ];
    useDatasetStore.setState({
      dataHistory: nodes,
      currentHistoryIndex: 1,
    });
    useAppStore.setState({ dataHistoryVisible: true });

    render(<DataHistoryPanel />);
    expect(screen.getByText('筛选')).toBeDefined();
    expect(screen.getByText('重命名')).toBeDefined();
    expect(screen.getByText('当前')).toBeDefined();
  });

  it('highlights current state node', () => {
    const nodes = [makeNode('filter'), makeNode('rename')];
    useDatasetStore.setState({
      dataHistory: nodes,
      currentHistoryIndex: 0,
    });
    useAppStore.setState({ dataHistoryVisible: true });

    render(<DataHistoryPanel />);
    const currentTags = screen.getAllByText('当前');
    expect(currentTags.length).toBe(1);
  });

  it('shows restore button for non-current nodes', () => {
    const nodes = [makeNode('filter'), makeNode('rename')];
    useDatasetStore.setState({
      dataHistory: nodes,
      currentHistoryIndex: 1,
    });
    useAppStore.setState({ dataHistoryVisible: true });

    render(<DataHistoryPanel />);
    const restoreButtons = screen.getAllByText('恢复');
    expect(restoreButtons.length).toBe(1);
  });

  it('calls restoreToHistoryIndex and closes modal on restore', () => {
    const nodes = [makeNode('filter'), makeNode('rename')];
    useDatasetStore.setState({
      dataHistory: nodes,
      currentHistoryIndex: 1,
    });
    useAppStore.setState({ dataHistoryVisible: true });

    render(<DataHistoryPanel />);
    fireEvent.click(screen.getByText('恢复'));

    expect(useDatasetStore.getState().currentHistoryIndex).toBe(0);
    expect(useAppStore.getState().dataHistoryVisible).toBe(false);
  });

  it('displays row and column count changes', () => {
    const nodes = [makeNode('filter', {
      row_count_before: 100,
      row_count_after: 80,
      col_count_before: 5,
      col_count_after: 5,
    })];
    useDatasetStore.setState({
      dataHistory: nodes,
      currentHistoryIndex: 0,
    });
    useAppStore.setState({ dataHistoryVisible: true });

    render(<DataHistoryPanel />);
    expect(screen.getByText('100 → 80 行,5 → 5 列')).toBeDefined();
  });

  it('displays notes when present', () => {
    const nodes = [makeNode('filter', { notes: ['已筛选年份 >= 2020'] })];
    useDatasetStore.setState({
      dataHistory: nodes,
      currentHistoryIndex: 0,
    });
    useAppStore.setState({ dataHistoryVisible: true });

    render(<DataHistoryPanel />);
    expect(screen.getByText('已筛选年份 >= 2020')).toBeDefined();
  });

  it('falls back to raw op_type when label unknown', () => {
    const nodes = [makeNode('custom_op')];
    useDatasetStore.setState({
      dataHistory: nodes,
      currentHistoryIndex: 0,
    });
    useAppStore.setState({ dataHistoryVisible: true });

    render(<DataHistoryPanel />);
    expect(screen.getByText('custom_op')).toBeDefined();
  });
});
