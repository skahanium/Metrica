import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, waitFor, act } from '@testing-library/react';
import { CommandLine } from '../components/CommandLine';
import { useCommandStore } from '../stores/commandStore';
import { useDatasetStore } from '../stores/datasetStore';

describe('CommandLine', () => {
  beforeEach(() => {
    vi.useRealTimers();
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
  });

  it('renders command prompt', () => {
    render(<CommandLine onExecute={vi.fn()} />);
    expect(screen.getByPlaceholderText(/输入命令/)).toBeDefined();
  });

  it('calls onExecute on Enter with non-empty input', () => {
    const onExecute = vi.fn();
    render(<CommandLine onExecute={onExecute} />);
    const input = screen.getByPlaceholderText(/输入命令/) as HTMLInputElement;
    fireEvent.change(input, { target: { value: 'regress y x' } });
    fireEvent.keyDown(input, { key: 'Enter' });
    expect(onExecute).toHaveBeenCalledWith('regress y x');
    // Input should be cleared after execution
    expect(useCommandStore.getState().input).toBe('');
  });

  it('does not call onExecute on Enter with empty input', () => {
    const onExecute = vi.fn();
    render(<CommandLine onExecute={onExecute} />);
    const input = screen.getByPlaceholderText(/输入命令/) as HTMLInputElement;
    fireEvent.keyDown(input, { key: 'Enter' });
    expect(onExecute).not.toHaveBeenCalled();
  });

  it('adds to history on execute', () => {
    const onExecute = vi.fn();
    render(<CommandLine onExecute={onExecute} />);
    const input = screen.getByPlaceholderText(/输入命令/) as HTMLInputElement;
    fireEvent.change(input, { target: { value: 'summarize y' } });
    fireEvent.keyDown(input, { key: 'Enter' });
    expect(useCommandStore.getState().history).toContain('summarize y');
  });

  it('shows ghost text hint bar', () => {
    render(<CommandLine onExecute={vi.fn()} />);
    expect(screen.getByText(/Tab 接受补全/)).toBeDefined();
    expect(screen.getByText(/Enter 执行/)).toBeDefined();
  });

  it('does not render cli feedback when there is no feedback', () => {
    render(<CommandLine onExecute={vi.fn()} />);
    expect(screen.queryByTestId('cli-feedback')).toBeNull();
  });

  it('renders cli feedback fixed to the command shell top edge', () => {
    render(<CommandLine onExecute={vi.fn()} feedback={{ level: 'error', message: '未知命令：x。请从补全列表选择可用命令。' }} />);

    const feedback = screen.getByTestId('cli-feedback');
    expect(feedback.textContent).toContain('未知命令：x');
    expect(feedback.style.position).toBe('absolute');
    expect(feedback.style.left).toBe('0px');
    expect(feedback.style.right).toBe('0px');
    expect(feedback.style.bottom).toBe('100%');
  });

  it('auto hides cli feedback after five seconds', () => {
    vi.useFakeTimers();
    const onClearFeedback = vi.fn();
    render(<CommandLine onExecute={vi.fn()} feedback={{ level: 'warning', message: '请先加载数据集' }} onClearFeedback={onClearFeedback} />);

    act(() => {
      vi.advanceTimersByTime(4_999);
    });
    expect(onClearFeedback).not.toHaveBeenCalled();

    act(() => {
      vi.advanceTimersByTime(1);
    });
    expect(onClearFeedback).toHaveBeenCalledTimes(1);
  });

  it('closes cli feedback without clearing command input', () => {
    const onClearFeedback = vi.fn();
    useCommandStore.setState({ input: 'x', cursorPos: 1 });

    render(<CommandLine onExecute={vi.fn()} feedback={{ level: 'error', message: '未知命令：x' }} onClearFeedback={onClearFeedback} />);
    fireEvent.click(screen.getByLabelText('关闭命令行提示'));

    expect(onClearFeedback).toHaveBeenCalledTimes(1);
    expect(useCommandStore.getState().input).toBe('x');
  });

  it('accepts highlighted completion on Enter without executing command', () => {
    const onExecute = vi.fn();
    useCommandStore.setState({
      input: 'reg',
      cursorPos: 3,
      completions: [{ text: 'regress', label: 'regress', description: '', kind: 'verb', priority: 1 }],
      selectedCompletionIdx: 0,
      showCompletions: true,
    });

    render(<CommandLine onExecute={onExecute} />);
    const input = screen.getByPlaceholderText(/输入命令/) as HTMLInputElement;
    fireEvent.keyDown(input, { key: 'Enter' });

    expect(onExecute).not.toHaveBeenCalled();
    expect(useCommandStore.getState().input).toBe('regress');
    expect(useCommandStore.getState().showCompletions).toBe(false);
  });

  it('accepts highlighted completion on Tab without appending a space', () => {
    const onExecute = vi.fn();
    useCommandStore.setState({
      input: 'reg',
      cursorPos: 3,
      completions: [{ text: 'regress', label: 'regress', description: '', kind: 'verb', priority: 1 }],
      selectedCompletionIdx: 0,
      showCompletions: true,
    });

    render(<CommandLine onExecute={onExecute} />);
    const input = screen.getByPlaceholderText(/输入命令/) as HTMLInputElement;
    fireEvent.keyDown(input, { key: 'Tab' });

    expect(onExecute).not.toHaveBeenCalled();
    expect(useCommandStore.getState().input).toBe('regress');
    expect(useCommandStore.getState().showCompletions).toBe(false);
  });

  it('keeps space editable while completion menu is open', () => {
    const onExecute = vi.fn();
    useCommandStore.setState({
      input: 'reg',
      cursorPos: 3,
      completions: [{ text: 'regress', label: 'regress', description: '', kind: 'verb', priority: 1 }],
      selectedCompletionIdx: 0,
      showCompletions: true,
    });

    render(<CommandLine onExecute={onExecute} />);
    const input = screen.getByPlaceholderText(/输入命令/) as HTMLInputElement;
    input.setSelectionRange(3, 3);
    const allowed = fireEvent.keyDown(input, { key: ' ' });

    expect(allowed).toBe(false);
    expect(onExecute).not.toHaveBeenCalled();
    expect(useCommandStore.getState().input).toBe('reg ');
    expect(useCommandStore.getState().showCompletions).toBe(false);
  });

  it('keeps backspace editable while completion menu is open', () => {
    const onExecute = vi.fn();
    useCommandStore.setState({
      input: 'reg',
      cursorPos: 3,
      completions: [{ text: 'regress', label: 'regress', description: '', kind: 'verb', priority: 1 }],
      selectedCompletionIdx: 0,
      showCompletions: true,
    });

    render(<CommandLine onExecute={onExecute} />);
    const input = screen.getByPlaceholderText(/输入命令/) as HTMLInputElement;
    input.setSelectionRange(3, 3);
    const allowed = fireEvent.keyDown(input, { key: 'Backspace' });

    expect(allowed).toBe(false);
    expect(onExecute).not.toHaveBeenCalled();
    expect(useCommandStore.getState().input).toBe('re');
  });

  it('keeps delete editable while completion menu is open', () => {
    const onExecute = vi.fn();
    useCommandStore.setState({
      input: 'reg',
      cursorPos: 2,
      completions: [{ text: 'regress', label: 'regress', description: '', kind: 'verb', priority: 1 }],
      selectedCompletionIdx: 0,
      showCompletions: true,
    });

    render(<CommandLine onExecute={onExecute} />);
    const input = screen.getByPlaceholderText(/输入命令/) as HTMLInputElement;
    input.setSelectionRange(2, 2);
    const allowed = fireEvent.keyDown(input, { key: 'Delete' });

    expect(allowed).toBe(false);
    expect(onExecute).not.toHaveBeenCalled();
    expect(useCommandStore.getState().input).toBe('re');
  });

  it('manual editing removes selected text while completion menu is open', () => {
    const onExecute = vi.fn();
    useCommandStore.setState({
      input: 'regress',
      cursorPos: 2,
      completions: [{ text: 'regress', label: 'regress', description: '', kind: 'verb', priority: 1 }],
      selectedCompletionIdx: 0,
      showCompletions: true,
    });

    render(<CommandLine onExecute={onExecute} />);
    const input = screen.getByPlaceholderText(/输入命令/) as HTMLInputElement;
    input.setSelectionRange(2, 5);
    fireEvent.keyDown(input, { key: 'Backspace' });

    expect(onExecute).not.toHaveBeenCalled();
    expect(useCommandStore.getState().input).toBe('ress');
  });

  it('manual editing can type variable suffix digits while completions are open', () => {
    useDatasetStore.setState({
      sourcePath: '/tmp/demo.csv',
      activePath: '/tmp/demo.csv',
      summary: {
        nrows: 2,
        ncols: 3,
        columns: [
          { name: 'y', type: 'Int64', inferred_type: 'Int64' },
          { name: 'x1', type: 'Int64', inferred_type: 'Int64' },
          { name: 'x2', type: 'Int64', inferred_type: 'Int64' },
        ],
        preview: [],
      },
    });
    useCommandStore.setState({
      input: 'regress x',
      cursorPos: 9,
      completions: [
        { text: 'x1', label: 'x1', description: '', kind: 'variable', priority: 1 },
        { text: 'x2', label: 'x2', description: '', kind: 'variable', priority: 1 },
      ],
      selectedCompletionIdx: 0,
      showCompletions: true,
    });

    render(<CommandLine onExecute={vi.fn()} />);
    const input = screen.getByPlaceholderText(/输入命令/) as HTMLInputElement;
    input.setSelectionRange(9, 9);
    fireEvent.keyDown(input, { key: '1' });

    expect(useCommandStore.getState().input).toBe('regress x1');
    expect(useCommandStore.getState().cursorPos).toBe(10);
  });

  it('scrolls the single-line input to keep long command typing visible', async () => {
    const longInput = 'regress ' + 'x1 '.repeat(24);
    useCommandStore.setState({
      input: longInput,
      cursorPos: longInput.length,
      completions: [],
      selectedCompletionIdx: 0,
      showCompletions: false,
    });

    render(<CommandLine onExecute={vi.fn()} />);
    const input = screen.getByPlaceholderText(/输入命令/) as HTMLInputElement;
    Object.defineProperty(input, 'clientWidth', { configurable: true, value: 120 });
    input.setSelectionRange(longInput.length, longInput.length);
    fireEvent.keyDown(input, { key: 'y' });

    expect(useCommandStore.getState().input).toBe(`${longInput}y`);
    await waitFor(() => {
      expect(input.scrollLeft).toBeGreaterThan(0);
    });
  });

  it('manual editing deletes trailing spaces after all variables are used', () => {
    useDatasetStore.setState({
      sourcePath: '/tmp/demo.csv',
      activePath: '/tmp/demo.csv',
      summary: {
        nrows: 2,
        ncols: 3,
        columns: [
          { name: 'y', type: 'Int64', inferred_type: 'Int64' },
          { name: 'x1', type: 'Int64', inferred_type: 'Int64' },
          { name: 'x2', type: 'Int64', inferred_type: 'Int64' },
        ],
        preview: [],
      },
    });
    useCommandStore.setState({
      input: 'regress x1 x2 y ',
      cursorPos: 16,
      completions: [],
      selectedCompletionIdx: 0,
      showCompletions: false,
    });

    render(<CommandLine onExecute={vi.fn()} />);
    const input = screen.getByPlaceholderText(/输入命令/) as HTMLInputElement;
    input.setSelectionRange(16, 16);
    fireEvent.keyDown(input, { key: 'Backspace' });

    expect(useCommandStore.getState().input).toBe('regress x1 x2 y');
    expect(useCommandStore.getState().cursorPos).toBe(15);
  });

  it('manual editing works after moving the caret into a completed command', () => {
    useCommandStore.setState({
      input: 'regress x1 x2 y ',
      cursorPos: 7,
      completions: [],
      selectedCompletionIdx: 0,
      showCompletions: false,
    });

    render(<CommandLine onExecute={vi.fn()} />);
    const input = screen.getByPlaceholderText(/输入命令/) as HTMLInputElement;
    input.setSelectionRange(7, 7);
    fireEvent.keyDown(input, { key: 'Backspace' });

    expect(useCommandStore.getState().input).toBe('regres x1 x2 y ');
    expect(useCommandStore.getState().cursorPos).toBe(6);
  });

  it('does not append duplicate space when completion is followed by punctuation', () => {
    const onExecute = vi.fn();
    useCommandStore.setState({
      input: 'cluster(reg)',
      cursorPos: 11,
      completions: [{ text: 'region', label: 'region', description: '', kind: 'variable', priority: 1 }],
      selectedCompletionIdx: 0,
      showCompletions: true,
    });

    render(<CommandLine onExecute={onExecute} />);
    const input = screen.getByPlaceholderText(/输入命令/) as HTMLInputElement;
    input.setSelectionRange(11, 11);
    fireEvent.keyDown(input, { key: 'Enter' });

    expect(useCommandStore.getState().input).toBe('cluster(region)');
  });

  it('positions completion menu near current token and omits already used variables', () => {
    useDatasetStore.setState({
      sourcePath: '/tmp/demo.csv',
      activePath: '/tmp/demo.csv',
      summary: {
        nrows: 2,
        ncols: 3,
        columns: [
          { name: 'y', type: 'Int64', inferred_type: 'Int64' },
          { name: 'x1', type: 'Int64', inferred_type: 'Int64' },
          { name: 'x2', type: 'Int64', inferred_type: 'Int64' },
        ],
        preview: [],
      },
    });

    render(<CommandLine onExecute={vi.fn()} />);
    const input = screen.getByPlaceholderText(/输入命令/) as HTMLInputElement;
    fireEvent.change(input, { target: { value: 'regress y ' } });

    expect(screen.queryByText('y')).toBeNull();
    expect(screen.getByText('x1')).toBeDefined();
    const shell = screen.getByTestId('command-shell');
    expect(shell.style.getPropertyValue('--completion-left')).not.toBe('16px');
    expect(shell.dataset.completionPlacement).toBe('inline');
    const menu = screen.getByTestId('completion-menu');
    expect(menu?.style.left).toBeTruthy();
    expect(menu?.style.width).not.toBe('');
  });

  it('shows next-position completions only after the user manually types a space after a complete token', () => {
    useDatasetStore.setState({
      sourcePath: '/tmp/demo.csv',
      activePath: '/tmp/demo.csv',
      summary: {
        nrows: 2,
        ncols: 3,
        columns: [
          { name: 'y', type: 'Int64', inferred_type: 'Int64' },
          { name: 'x1', type: 'Int64', inferred_type: 'Int64' },
          { name: 'x2', type: 'Int64', inferred_type: 'Int64' },
        ],
        preview: [],
      },
    });
    render(<CommandLine onExecute={vi.fn()} />);
    const input = screen.getByPlaceholderText(/输入命令/) as HTMLInputElement;

    fireEvent.change(input, { target: { value: 'reg', selectionStart: 3 } });
    expect(useCommandStore.getState().showCompletions).toBe(true);

    fireEvent.keyDown(input, { key: 'Enter' });
    expect(useCommandStore.getState().input).toBe('regress');
    expect(useCommandStore.getState().showCompletions).toBe(false);

    input.setSelectionRange(7, 7);
    fireEvent.keyDown(input, { key: ' ' });

    expect(useCommandStore.getState().input).toBe('regress ');
    expect(useCommandStore.getState().showCompletions).toBe(true);
    expect(screen.getByText('y')).toBeDefined();
  });

  it('does not trigger the next-position completion when space follows an incomplete token', () => {
    render(<CommandLine onExecute={vi.fn()} />);
    const input = screen.getByPlaceholderText(/输入命令/) as HTMLInputElement;

    fireEvent.change(input, { target: { value: 'reg', selectionStart: 3 } });
    expect(useCommandStore.getState().showCompletions).toBe(true);

    input.setSelectionRange(3, 3);
    fireEvent.keyDown(input, { key: ' ' });

    expect(useCommandStore.getState().input).toBe('reg ');
    expect(useCommandStore.getState().showCompletions).toBe(false);
    expect(screen.queryByTestId('completion-menu')).toBeNull();
  });

  it('cycles downward from the last completion back to the first', () => {
    useCommandStore.setState({
      input: 'regress ',
      cursorPos: 8,
      completions: [
        { text: 'x1', label: 'x1', description: '', kind: 'variable', priority: 1 },
        { text: 'x2', label: 'x2', description: '', kind: 'variable', priority: 1 },
      ],
      selectedCompletionIdx: 1,
      showCompletions: true,
    });

    render(<CommandLine onExecute={vi.fn()} />);
    const input = screen.getByPlaceholderText(/输入命令/) as HTMLInputElement;
    fireEvent.keyDown(input, { key: 'ArrowDown' });

    expect(useCommandStore.getState().selectedCompletionIdx).toBe(0);
  });

  it('cycles upward from the first completion to the last', () => {
    useCommandStore.setState({
      input: 'regress ',
      cursorPos: 8,
      completions: [
        { text: 'x1', label: 'x1', description: '', kind: 'variable', priority: 1 },
        { text: 'x2', label: 'x2', description: '', kind: 'variable', priority: 1 },
      ],
      selectedCompletionIdx: 0,
      showCompletions: true,
    });

    render(<CommandLine onExecute={vi.fn()} />);
    const input = screen.getByPlaceholderText(/输入命令/) as HTMLInputElement;
    fireEvent.keyDown(input, { key: 'ArrowUp' });

    expect(useCommandStore.getState().selectedCompletionIdx).toBe(1);
  });

  it('flips completion menu near the right edge while keeping the anchor at the caret', () => {
    useDatasetStore.setState({
      sourcePath: '/tmp/demo.csv',
      activePath: '/tmp/demo.csv',
      summary: {
        nrows: 2,
        ncols: 3,
        columns: [
          { name: 'y', type: 'Int64', inferred_type: 'Int64' },
          { name: 'x1', type: 'Int64', inferred_type: 'Int64' },
          { name: 'x2', type: 'Int64', inferred_type: 'Int64' },
        ],
        preview: [],
      },
    });

    render(<CommandLine onExecute={vi.fn()} />);
    const shell = screen.getByTestId('command-shell');
    Object.defineProperty(shell, 'clientWidth', { configurable: true, value: 520 });

    const input = screen.getByPlaceholderText(/输入命令/) as HTMLInputElement;
    const longInput = `regress ${'x1 '.repeat(42)},`;
    fireEvent.change(input, { target: { value: longInput, selectionStart: longInput.length } });

    const left = parseFloat(shell.style.getPropertyValue('--completion-left'));
    const width = parseFloat(shell.style.getPropertyValue('--completion-width'));
    const anchorX = parseFloat(shell.style.getPropertyValue('--completion-anchor-x'));

    expect(shell.dataset.completionPlacement).toBe('flip');
    expect(anchorX).toBeGreaterThan(left);
    expect(anchorX).toBeLessThanOrEqual(left + width);
    expect(left + width).toBe(520 - 16);
    expect(width).toBeGreaterThanOrEqual(320);
    expect(screen.getByTestId('completion-anchor-marker')).toBeDefined();
  });

  it('uses full-width compact completion menu when the shell is too narrow', () => {
    useDatasetStore.setState({
      sourcePath: '/tmp/demo.csv',
      activePath: '/tmp/demo.csv',
      summary: {
        nrows: 2,
        ncols: 3,
        columns: [
          { name: 'y', type: 'Int64', inferred_type: 'Int64' },
          { name: 'x1', type: 'Int64', inferred_type: 'Int64' },
          { name: 'x2', type: 'Int64', inferred_type: 'Int64' },
        ],
        preview: [],
      },
    });

    render(<CommandLine onExecute={vi.fn()} />);
    const shell = screen.getByTestId('command-shell');
    Object.defineProperty(shell, 'clientWidth', { configurable: true, value: 300 });

    const input = screen.getByPlaceholderText(/输入命令/) as HTMLInputElement;
    fireEvent.change(input, { target: { value: 'regress y ', selectionStart: 10 } });

    const left = parseFloat(shell.style.getPropertyValue('--completion-left'));
    const width = parseFloat(shell.style.getPropertyValue('--completion-width'));
    const anchorX = parseFloat(shell.style.getPropertyValue('--completion-anchor-x'));

    expect(shell.dataset.completionPlacement).toBe('compact');
    expect(left).toBe(16);
    expect(width).toBe(300 - 32);
    expect(anchorX).toBeGreaterThanOrEqual(left);
    expect(anchorX).toBeLessThanOrEqual(left + width);
  });

  it('keeps completion menu anchored during a partial token and advances after recognition', () => {
    render(<CommandLine onExecute={vi.fn()} />);
    const input = screen.getByPlaceholderText(/输入命令/) as HTMLInputElement;

    fireEvent.change(input, { target: { value: 'r', selectionStart: 1 } });
    const shell = screen.getByTestId('command-shell');
    const leftAfterR = parseFloat(shell.style.getPropertyValue('--completion-left'));

    fireEvent.change(input, { target: { value: 're', selectionStart: 2 } });
    const leftAfterRe = parseFloat(shell.style.getPropertyValue('--completion-left'));

    fireEvent.change(input, { target: { value: 'regress', selectionStart: 7 } });
    const leftAfterRegress = parseFloat(shell.style.getPropertyValue('--completion-left'));

    expect(leftAfterRe).toBe(leftAfterR);
    expect(leftAfterRegress).toBeGreaterThan(leftAfterRe);
  });

  it('applies recognition anchoring to other built-in command tokens', () => {
    render(<CommandLine onExecute={vi.fn()} />);
    const input = screen.getByPlaceholderText(/输入命令/) as HTMLInputElement;

    fireEvent.change(input, { target: { value: 's', selectionStart: 1 } });
    const shell = screen.getByTestId('command-shell');
    const leftAfterS = parseFloat(shell.style.getPropertyValue('--completion-left'));

    fireEvent.change(input, { target: { value: 'summ', selectionStart: 4 } });
    const leftAfterSumm = parseFloat(shell.style.getPropertyValue('--completion-left'));

    fireEvent.change(input, { target: { value: 'summarize', selectionStart: 9 } });
    const leftAfterSummarize = parseFloat(shell.style.getPropertyValue('--completion-left'));

    expect(leftAfterSumm).toBe(leftAfterS);
    expect(leftAfterSummarize).toBeGreaterThan(leftAfterSumm);
  });

  it('applies recognition anchoring to built-in option names and values', () => {
    useDatasetStore.setState({
      sourcePath: '/tmp/demo.csv',
      activePath: '/tmp/demo.csv',
      summary: {
        nrows: 2,
        ncols: 3,
        columns: [
          { name: 'y', type: 'Int64', inferred_type: 'Int64' },
          { name: 'x1', type: 'Int64', inferred_type: 'Int64' },
          { name: 'x2', type: 'Int64', inferred_type: 'Int64' },
        ],
        preview: [],
      },
    });
    render(<CommandLine onExecute={vi.fn()} />);
    const input = screen.getByPlaceholderText(/输入命令/) as HTMLInputElement;

    fireEvent.change(input, { target: { value: 'regress y x1, rob', selectionStart: 17 } });
    const shell = screen.getByTestId('command-shell');
    const leftAfterRob = parseFloat(shell.style.getPropertyValue('--completion-left'));

    fireEvent.change(input, { target: { value: 'regress y x1, robust', selectionStart: 20 } });
    const leftAfterRobust = parseFloat(shell.style.getPropertyValue('--completion-left'));

    expect(leftAfterRobust).toBeGreaterThan(leftAfterRob);

    fireEvent.change(input, { target: { value: 'reshape lo', selectionStart: 10 } });
    const leftAfterLo = parseFloat(shell.style.getPropertyValue('--completion-left'));

    fireEvent.change(input, { target: { value: 'reshape long', selectionStart: 12 } });
    const leftAfterLong = parseFloat(shell.style.getPropertyValue('--completion-left'));

    expect(leftAfterLong).toBeGreaterThan(leftAfterLo);
  });

  it('advances completion menu only after a variable token is recognized', () => {
    useDatasetStore.setState({
      sourcePath: '/tmp/demo.csv',
      activePath: '/tmp/demo.csv',
      summary: {
        nrows: 2,
        ncols: 3,
        columns: [
          { name: 'y', type: 'Int64', inferred_type: 'Int64' },
          { name: 'x1', type: 'Int64', inferred_type: 'Int64' },
          { name: 'x2', type: 'Int64', inferred_type: 'Int64' },
        ],
        preview: [],
      },
    });
    render(<CommandLine onExecute={vi.fn()} />);
    const input = screen.getByPlaceholderText(/输入命令/) as HTMLInputElement;

    fireEvent.change(input, { target: { value: 'regress y x', selectionStart: 11 } });
    const shell = screen.getByTestId('command-shell');
    const leftAfterPartialX = parseFloat(shell.style.getPropertyValue('--completion-left'));

    fireEvent.change(input, { target: { value: 'regress y x1', selectionStart: 12 } });
    const leftAfterX1 = parseFloat(shell.style.getPropertyValue('--completion-left'));

    expect(leftAfterX1).toBeGreaterThan(leftAfterPartialX);
  });
});
