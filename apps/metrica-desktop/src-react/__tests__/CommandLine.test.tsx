import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { CommandLine } from '../components/CommandLine';
import { useCommandStore } from '../stores/commandStore';

describe('CommandLine', () => {
  beforeEach(() => {
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
    expect(screen.getByText(/Tab 补全/)).toBeDefined();
    expect(screen.getByText(/Enter 执行/)).toBeDefined();
  });
});
