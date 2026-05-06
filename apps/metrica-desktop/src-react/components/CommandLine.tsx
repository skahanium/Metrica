import React, { useRef, useEffect, useCallback } from 'react';
import { Input } from 'antd';
import { useCommandStore } from '../stores/commandStore';
import { useDatasetStore } from '../stores/datasetStore';
import { getContext, getCompletions, getCorrections, getGhostText } from '../services/autocomplete';
import type { ColumnSummary } from '../types/protocol';

/** Stable empty array to prevent Zustand infinite-loop from new [] each render. */
const EMPTY_COLUMNS: ColumnSummary[] = [];

interface CommandLineProps {
  onExecute: (input: string) => void;
}

export const CommandLine: React.FC<CommandLineProps> = ({ onExecute }) => {
  const inputRef = useRef<any>(null);

  const {
    input, setInput, completions, selectedCompletionIdx, ghostText,
    showCompletions, correction,
    acceptCompletion, selectNextCompletion, selectPrevCompletion,
    hideCompletions, addToHistory, navigateHistoryUp, navigateHistoryDown,
    setCompletions, setGhostText, setCorrection, clearInput,
  } = useCommandStore();

  const columns = useDatasetStore((s) => s.summary?.columns ?? EMPTY_COLUMNS);

  // Update completions whenever input changes
  const updateCompletions = useCallback(
    (value: string, cursorPos: number) => {
      const ctx = getContext(value, cursorPos);
      const partial = value.slice(
        Math.max(
          value.lastIndexOf(' ', cursorPos - 1),
          value.lastIndexOf(',', cursorPos - 1),
          value.lastIndexOf('(', cursorPos - 1)
        ) + 1,
        cursorPos
      ).trim();

      let items = getCompletions(ctx, columns, partial);

      // No results -> try correction for variable contexts
      if (items.length === 0 && (ctx.kind === 'depvar' || ctx.kind === 'indepvar' || ctx.kind === 'option_value') && partial.length >= 3) {
        const corrections = getCorrections(partial, columns, 3);
        if (corrections.length > 0) {
          setCorrection(corrections[0].text);
          items = corrections;
        }
      } else {
        setCorrection(null);
      }

      setCompletions(items, ctx);

      // Ghost text
      const ghost = getGhostText(ctx, columns, value, cursorPos);
      setGhostText(ghost);
    },
    [columns, setCompletions, setGhostText, setCorrection]
  );

  const handleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const value = e.target.value;
    const pos = e.target.selectionStart || 0;
    setInput(value, pos);
    updateCompletions(value, pos);
  };

  const handleKeyDown = (e: React.KeyboardEvent) => {
    // Completion menu navigation
    if (showCompletions) {
      if (e.key === 'ArrowDown') {
        e.preventDefault();
        selectNextCompletion();
        return;
      }
      if (e.key === 'ArrowUp') {
        e.preventDefault();
        selectPrevCompletion();
        return;
      }
      if (e.key === 'Tab') {
        e.preventDefault();
        const item = acceptCompletion();
        if (item) {
          const selStart = inputRef.current?.input?.selectionStart || input.length;
          const beforeCursor = input.slice(0, selStart);
          const afterCursor = input.slice(selStart);
          const lastDelim = Math.max(
            beforeCursor.lastIndexOf(' '),
            beforeCursor.lastIndexOf(','),
            beforeCursor.lastIndexOf('(')
          );
          const partialStart = lastDelim + 1;
          const spaceAfter = item.kind === 'verb' ? ' ' : '';
          const newInput = beforeCursor.slice(0, partialStart) + item.text + spaceAfter + afterCursor;
          setInput(newInput, partialStart + item.text.length + spaceAfter.length);
          hideCompletions();
          updateCompletions(newInput, partialStart + item.text.length + spaceAfter.length);
        }
        return;
      }
      if (e.key === 'Escape') {
        e.preventDefault();
        hideCompletions();
        return;
      }
    }

    // Ghost text acceptance
    if (e.key === 'Tab' && ghostText && !showCompletions) {
      e.preventDefault();
      const newInput = input + ghostText;
      setInput(newInput, newInput.length);
      updateCompletions(newInput, newInput.length);
      return;
    }

    // History navigation (when input is empty or at start of line)
    if (e.key === 'ArrowUp' && (!input || !showCompletions)) {
      const hist = navigateHistoryUp();
      if (hist !== null) {
        e.preventDefault();
        setInput(hist, hist.length);
        updateCompletions(hist, hist.length);
      }
      return;
    }
    if (e.key === 'ArrowDown' && !showCompletions) {
      const hist = navigateHistoryDown();
      if (hist !== null) {
        e.preventDefault();
        setInput(hist, hist.length);
        updateCompletions(hist, hist.length);
      }
      return;
    }

    // Execute on Enter
    if (e.key === 'Enter' && !showCompletions) {
      e.preventDefault();
      const trimmed = input.trim();
      if (trimmed) {
        addToHistory(trimmed);
        onExecute(trimmed);
        clearInput();
      }
    }
  };

  // Auto-focus the input
  useEffect(() => {
    inputRef.current?.focus();
  }, []);

  // Compute ghost text display: the full input + ghost suffix
  const ghostDisplay = ghostText && !showCompletions ? input + ghostText : null;

  return (
    <div
      style={{
        position: 'relative',
        padding: '8px 16px 4px',
        borderTop: '1px solid #f0f0f0',
        background: '#fafafa',
      }}
    >
      {/* Completion dropdown */}
      {showCompletions && completions.length > 0 && (
        <div
          style={{
            position: 'absolute',
            bottom: '100%',
            left: 16,
            right: 16,
            background: '#fff',
            border: '1px solid #d9d9d9',
            borderRadius: 6,
            maxHeight: 200,
            overflow: 'auto',
            zIndex: 1000,
            boxShadow: '0 2px 8px rgba(0,0,0,0.1)',
            marginBottom: 4,
          }}
        >
          {correction && (
            <div style={{ padding: '4px 12px', fontSize: 12, color: '#999', borderBottom: '1px solid #f0f0f0' }}>
              未找到。你的意思是？
            </div>
          )}
          {completions.map((item, idx) => (
            <div
              key={item.text}
              style={{
                padding: '6px 12px',
                cursor: 'pointer',
                background: idx === selectedCompletionIdx ? '#e6f4ff' : 'transparent',
                display: 'flex',
                justifyContent: 'space-between',
                alignItems: 'center',
              }}
              onMouseDown={(e) => {
                // Prevent blur before click
                e.preventDefault();
              }}
              onClick={() => {
                // Select and accept this item
                const selStart = inputRef.current?.input?.selectionStart || input.length;
                const beforeCursor = input.slice(0, selStart);
                const afterCursor = input.slice(selStart);
                const lastDelim = Math.max(
                  beforeCursor.lastIndexOf(' '),
                  beforeCursor.lastIndexOf(','),
                  beforeCursor.lastIndexOf('(')
                );
                const partialStart = lastDelim + 1;
                const spaceAfter = item.kind === 'verb' ? ' ' : '';
                const newInput = beforeCursor.slice(0, partialStart) + item.text + spaceAfter + afterCursor;
                setInput(newInput, partialStart + item.text.length + spaceAfter.length);
                hideCompletions();
                updateCompletions(newInput, partialStart + item.text.length + spaceAfter.length);
              }}
            >
              <span style={{ fontWeight: 500, fontSize: 13 }}>{item.text}</span>
              <span style={{ color: '#999', fontSize: 11 }}>{item.description}</span>
            </div>
          ))}
        </div>
      )}

      {/* Command input with ghost text */}
      <div style={{ position: 'relative' }}>
        {ghostDisplay && (
          <div
            style={{
              position: 'absolute',
              left: 0,
              top: 0,
              right: 0,
              bottom: 0,
              display: 'flex',
              alignItems: 'center',
              paddingLeft: 26, // align with text inside Input (prefix width)
              pointerEvents: 'none',
              zIndex: 1,
              fontFamily: 'monospace',
              fontSize: 14,
            }}
          >
            <span style={{ visibility: 'hidden' }}>{input}</span>
            <span style={{ color: '#bfbfbf' }}>{ghostText}</span>
          </div>
        )}
        <Input
          ref={inputRef}
          prefix={
            <span style={{ color: '#1677ff', fontWeight: 600, fontFamily: 'monospace' }}>
              &gt;
            </span>
          }
          placeholder="输入命令... (regress / summarize / describe / ...)"
          value={input}
          onChange={handleChange}
          onKeyDown={handleKeyDown}
          onBlur={() => setTimeout(hideCompletions, 200)}
          variant="borderless"
          style={{ fontFamily: 'monospace', fontSize: 14 }}
        />
      </div>

      {/* Hint bar */}
      <div
        style={{
          fontSize: 11,
          color: '#bbb',
          marginTop: 2,
          paddingLeft: 24,
          display: 'flex',
          justifyContent: 'space-between',
        }}
      >
        <span>Tab 补全 . ↑↓ 浏览 . Enter 执行 . Esc 关闭</span>
        {correction && (
          <span style={{ color: '#faad14' }}>建议: {correction}</span>
        )}
      </div>
    </div>
  );
};
