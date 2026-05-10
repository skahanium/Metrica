import React, { useRef, useEffect, useLayoutEffect, useCallback, useState } from 'react';
import { Input } from 'antd';
import { useCommandStore } from '../stores/commandStore';
import { useDatasetStore } from '../stores/datasetStore';
import { getContext, getCompletions, getCorrections, getGhostText, getPartial, getUsedVariableNames } from '../services/autocomplete';
import { COMMAND_LIST } from '../services/commandGrammar';
import type { ColumnSummary } from '../types/protocol';

/** Stable empty array to prevent Zustand infinite-loop from new [] each render. */
const EMPTY_COLUMNS: ColumnSummary[] = [];
const EDITING_CONTROL_KEYS = new Set(['Backspace', 'Delete']);
const COMPLETION_MAX_WIDTH = 640;
const COMPLETION_MIN_READABLE_WIDTH = 320;
const COMPLETION_EDGE_PADDING = 16;

interface CompletionBoxState {
  left: number;
  width: number;
  anchorX: number;
  placement: 'inline' | 'flip' | 'compact';
}

function getTokenStart(value: string, cursorPos: number): number {
  const beforeCursor = value.slice(0, cursorPos);
  return Math.max(
    beforeCursor.lastIndexOf(' '),
    beforeCursor.lastIndexOf(','),
    beforeCursor.lastIndexOf('('),
  ) + 1;
}

function isRecognizedToken(value: string, cursorPos: number, columns: ColumnSummary[]): boolean {
  const tokenStart = getTokenStart(value, cursorPos);
  const token = value.slice(tokenStart, cursorPos).trim();
  if (!token) return true;

  const context = getContext(value, cursorPos);
  if (context.kind === 'verb') {
    return COMMAND_LIST.includes(token.toLowerCase());
  }
  if (context.kind === 'depvar' || context.kind === 'indepvar' || context.kind === 'option_value') {
    const matchesVariable = columns.some((col) => col.name === token);
    if (matchesVariable) return true;

    if (context.kind === 'option_value' && context.grammar && context.optionName) {
      const optionNode = context.grammar.syntax.find((node) => node.kind === 'option');
      const optionValueNode = optionNode?.children?.[context.optionName];
      return Boolean(optionValueNode?.values?.includes(token));
    }

    if (context.kind === 'indepvar' && context.grammar) {
      return context.grammar.syntax.some((node) => node.values?.includes(token));
    }

    return false;
  }
  if (context.kind === 'option' && context.grammar) {
    const optionNode = context.grammar.syntax.find((node) => node.kind === 'option');
    return Boolean(optionNode?.children?.[token]);
  }

  return false;
}

function getCompletionAnchorPos(value: string, cursorPos: number, columns: ColumnSummary[]): number {
  if (cursorPos <= 0) return 0;
  const prevChar = value[cursorPos - 1];
  if (!prevChar || /\s|,|\(/.test(prevChar)) return cursorPos;
  return isRecognizedToken(value, cursorPos, columns)
    ? cursorPos
    : getTokenStart(value, cursorPos);
}

interface CommandLineProps {
  onExecute: (input: string) => void | boolean | Promise<void | boolean>;
  feedback?: CliFeedback | null;
  onClearFeedback?: () => void;
}

export interface CliFeedback {
  level: 'error' | 'warning';
  message: string;
}

export const CommandLine: React.FC<CommandLineProps> = ({ onExecute, feedback = null, onClearFeedback }) => {
  const inputRef = useRef<any>(null);
  const shellRef = useRef<HTMLDivElement>(null);
  const measureRef = useRef<HTMLSpanElement>(null);
  const caretTextRef = useRef<HTMLSpanElement>(null);
  const completionBoxRef = useRef<CompletionBoxState>({
    left: COMPLETION_EDGE_PADDING,
    width: COMPLETION_MIN_READABLE_WIDTH,
    anchorX: COMPLETION_EDGE_PADDING,
    placement: 'inline',
  });
  const [completionBox, setCompletionBox] = useState<CompletionBoxState>({
    left: COMPLETION_EDGE_PADDING,
    width: COMPLETION_MIN_READABLE_WIDTH,
    anchorX: COMPLETION_EDGE_PADDING,
    placement: 'inline',
  });

  const {
    input, cursorPos, setInput, completions, selectedCompletionIdx, ghostText,
    showCompletions, correction,
    acceptCompletion, selectNextCompletion, selectPrevCompletion,
    hideCompletions, addToHistory, navigateHistoryUp, navigateHistoryDown,
    setCompletions, setGhostText, setCorrection, clearInput,
  } = useCommandStore();

  const columns = useDatasetStore((s) => s.summary?.columns ?? EMPTY_COLUMNS);

  useEffect(() => {
    if (!feedback || !onClearFeedback) return undefined;
    const timer = window.setTimeout(onClearFeedback, 5_000);
    return () => window.clearTimeout(timer);
  }, [feedback, onClearFeedback]);

  const updateCompletionBox = useCallback((value: string, cursorPos: number) => {
    const anchorPos = getCompletionAnchorPos(value, cursorPos, columns);
    if (caretTextRef.current) {
      caretTextRef.current.textContent = value.slice(0, anchorPos);
    }

    const shellWidth = shellRef.current?.clientWidth || 900;
    const inputEl = inputRef.current?.input as HTMLInputElement | undefined;
    const paddingRight = COMPLETION_EDGE_PADDING;

    let caretLeft = 42 + value.slice(0, anchorPos).length * 8.4;
    if (inputEl && shellRef.current) {
      const inputRect = inputEl.getBoundingClientRect();
      const shellRect = shellRef.current.getBoundingClientRect();
      const hasLayout = inputRect.width > 0 && shellRect.width > 0;
      if (hasLayout) {
        const style = window.getComputedStyle(inputEl);
        const measuredText = value.slice(0, anchorPos);
        let textWidth = measuredText.length * 8.4;
        if (measureRef.current) {
          measureRef.current.style.fontFamily = style.fontFamily;
          measureRef.current.style.fontSize = style.fontSize;
          measureRef.current.style.fontWeight = style.fontWeight;
          measureRef.current.style.fontStyle = style.fontStyle;
          measureRef.current.style.letterSpacing = style.letterSpacing;
          measureRef.current.textContent = measuredText || '';
          textWidth = measureRef.current.offsetWidth || textWidth;
        }
        const paddingLeft = parseFloat(style.paddingLeft || '0') || 0;
        caretLeft = inputRect.left - shellRect.left + paddingLeft + textWidth - inputEl.scrollLeft;
      }
    }

    const anchorX = Math.min(Math.max(COMPLETION_EDGE_PADDING, caretLeft), Math.max(COMPLETION_EDGE_PADDING, shellWidth - paddingRight));
    const maxPanelWidth = Math.max(0, shellWidth - COMPLETION_EDGE_PADDING * 2);
    const preferredWidth = Math.min(COMPLETION_MAX_WIDTH, maxPanelWidth);
    const compactThreshold = COMPLETION_MIN_READABLE_WIDTH + COMPLETION_EDGE_PADDING * 2;
    const rightSpace = Math.max(0, shellWidth - anchorX - paddingRight);
    const canInline = rightSpace >= Math.min(COMPLETION_MIN_READABLE_WIDTH, preferredWidth);
    const placement: CompletionBoxState['placement'] = shellWidth < compactThreshold
      ? 'compact'
      : canInline ? 'inline' : 'flip';
    const width = placement === 'compact'
      ? maxPanelWidth
      : placement === 'inline'
        ? Math.min(preferredWidth, rightSpace)
        : Math.min(preferredWidth, Math.max(COMPLETION_MIN_READABLE_WIDTH, anchorX - COMPLETION_EDGE_PADDING), maxPanelWidth);
    const left = placement === 'compact'
      ? COMPLETION_EDGE_PADDING
      : placement === 'inline'
        ? anchorX
        : Math.max(COMPLETION_EDGE_PADDING, shellWidth - paddingRight - width);
    if (shellRef.current) {
      shellRef.current.style.setProperty('--completion-left', `${left}px`);
      shellRef.current.style.setProperty('--completion-width', `${width}px`);
      shellRef.current.style.setProperty('--completion-anchor-x', `${anchorX}px`);
      shellRef.current.dataset.completionPlacement = placement;
    }
    const prev = completionBoxRef.current;
    if (
      Math.abs(prev.left - left) > 0.25 ||
      Math.abs(prev.width - width) > 0.25 ||
      Math.abs(prev.anchorX - anchorX) > 0.25 ||
      prev.placement !== placement
    ) {
      const next = { left, width, anchorX, placement };
      completionBoxRef.current = next;
      setCompletionBox(next);
    }
  }, [columns]);

  // Update completions whenever input changes
  const updateCompletions = useCallback(
    (value: string, cursorPos: number) => {
      const ctx = getContext(value, cursorPos);
      const partial = getPartial(value, cursorPos);
      const usedVariables = getUsedVariableNames(value, cursorPos, columns);

      let items = getCompletions(ctx, columns, partial, usedVariables);

      // No results -> try correction for variable contexts
      if (items.length === 0 && (ctx.kind === 'depvar' || ctx.kind === 'indepvar' || ctx.kind === 'option_value') && partial.length >= 3) {
        const corrections = getCorrections(
          partial,
          columns.filter(col => !usedVariables.has(col.name)),
          3,
        );
        if (corrections.length > 0) {
          setCorrection(corrections[0].text);
          items = corrections;
        }
      } else {
        setCorrection(null);
      }

      setCompletions(items, ctx);

      // Ghost text
      const ghost = getGhostText(ctx, columns, value, cursorPos, usedVariables);
      setGhostText(ghost);
    },
    [columns, setCompletions, setGhostText, setCorrection]
  );

  const measureInputTextWidth = useCallback((inputEl: HTMLInputElement, text: string): number => {
    const style = window.getComputedStyle(inputEl);
    let textWidth = text.length * 8.4;
    if (measureRef.current) {
      measureRef.current.style.fontFamily = style.fontFamily;
      measureRef.current.style.fontSize = style.fontSize;
      measureRef.current.style.fontWeight = style.fontWeight;
      measureRef.current.style.fontStyle = style.fontStyle;
      measureRef.current.style.letterSpacing = style.letterSpacing;
      measureRef.current.textContent = text;
      textWidth = measureRef.current.offsetWidth || textWidth;
    }
    return textWidth;
  }, []);

  const ensureCaretVisible = useCallback((value: string, nextCursor: number) => {
    const inputEl = inputRef.current?.input as HTMLInputElement | undefined;
    if (!inputEl) return;

    const style = window.getComputedStyle(inputEl);
    const paddingLeft = parseFloat(style.paddingLeft || '0') || 0;
    const paddingRight = parseFloat(style.paddingRight || '0') || 0;
    const visibleWidth = Math.max(0, inputEl.clientWidth - paddingLeft - paddingRight);
    const caretTextWidth = measureInputTextWidth(inputEl, value.slice(0, nextCursor));
    const caretX = paddingLeft + caretTextWidth;
    const currentLeft = inputEl.scrollLeft;
    const currentRight = currentLeft + visibleWidth;
    const margin = 24;

    if (caretX > currentRight - margin) {
      inputEl.scrollLeft = Math.max(0, caretX - visibleWidth + margin);
    } else if (caretX < currentLeft + margin) {
      inputEl.scrollLeft = Math.max(0, caretX - margin);
    }
  }, [measureInputTextWidth]);

  const applyCompletion = useCallback((item: { text: string; kind: string }) => {
    const selStart = inputRef.current?.input?.selectionStart ?? input.length;
    const beforeCursor = input.slice(0, selStart);
    const afterCursor = input.slice(selStart);
    const lastDelim = Math.max(
      beforeCursor.lastIndexOf(' '),
      beforeCursor.lastIndexOf(','),
      beforeCursor.lastIndexOf('(')
    );
    const partialStart = lastDelim + 1;
    const nextChar = afterCursor[0] || '';
    const shouldAddSpace = ![' ', '\t', '\n', ',', ')'].includes(nextChar);
    const spaceAfter = shouldAddSpace ? ' ' : '';
    const newInput = beforeCursor.slice(0, partialStart) + item.text + spaceAfter + afterCursor;
    const newCursor = partialStart + item.text.length + spaceAfter.length;
    setInput(newInput, newCursor);
    hideCompletions();
    updateCompletions(newInput, newCursor);
    window.requestAnimationFrame(() => {
      const el = inputRef.current?.input as HTMLInputElement | undefined;
      el?.setSelectionRange(newCursor, newCursor);
      ensureCaretVisible(newInput, newCursor);
      updateCompletionBox(newInput, newCursor);
    });
  }, [ensureCaretVisible, hideCompletions, input, setInput, updateCompletionBox, updateCompletions]);

  const applyManualEdit = useCallback((e: React.KeyboardEvent): boolean => {
    if (e.metaKey || e.ctrlKey || e.altKey || e.nativeEvent.isComposing) return false;

    const insertsText = e.key.length === 1 || e.key === 'Spacebar';
    const editsText = insertsText || EDITING_CONTROL_KEYS.has(e.key);
    if (!editsText) return false;

    const inputEl = inputRef.current?.input as HTMLInputElement | undefined;
    const value = inputEl?.value ?? input;
    const start = inputEl?.selectionStart ?? cursorPos;
    const end = inputEl?.selectionEnd ?? start;

    let nextValue = value;
    let nextCursor = start;

    if (insertsText) {
      const text = e.key === 'Spacebar' ? ' ' : e.key;
      nextValue = value.slice(0, start) + text + value.slice(end);
      nextCursor = start + text.length;
    } else if (e.key === 'Backspace') {
      if (start !== end) {
        nextValue = value.slice(0, start) + value.slice(end);
        nextCursor = start;
      } else if (start > 0) {
        nextValue = value.slice(0, start - 1) + value.slice(start);
        nextCursor = start - 1;
      }
    } else if (e.key === 'Delete') {
      if (start !== end) {
        nextValue = value.slice(0, start) + value.slice(end);
        nextCursor = start;
      } else if (start < value.length) {
        nextValue = value.slice(0, start) + value.slice(start + 1);
        nextCursor = start;
      }
    }

    setInput(nextValue, nextCursor);
    updateCompletionBox(nextValue, nextCursor);
    updateCompletions(nextValue, nextCursor);
    window.requestAnimationFrame(() => {
      const el = inputRef.current?.input as HTMLInputElement | undefined;
      el?.setSelectionRange(nextCursor, nextCursor);
      ensureCaretVisible(nextValue, nextCursor);
      updateCompletionBox(nextValue, nextCursor);
    });
    return true;
  }, [cursorPos, ensureCaretVisible, input, setInput, updateCompletionBox, updateCompletions]);

  const syncCaretFromDom = useCallback(() => {
    const inputEl = inputRef.current?.input as HTMLInputElement | undefined;
    const value = inputEl?.value ?? input;
    const pos = inputEl?.selectionStart ?? value.length;
    updateCompletionBox(value, pos);
    if (value === useCommandStore.getState().input) {
      setInput(value, pos);
    }
  }, [input, setInput, updateCompletionBox]);

  const handleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const value = e.target.value;
    const pos = e.target.selectionStart ?? value.length;
    setInput(value, pos);
    updateCompletionBox(value, pos);
    updateCompletions(value, pos);
    window.requestAnimationFrame(() => {
      ensureCaretVisible(value, pos);
      updateCompletionBox(value, pos);
    });
  };

  const handleCursorMove = () => {
    syncCaretFromDom();
  };

  const finishSubmit = useCallback((accepted: void | boolean, trimmed: string) => {
    if (accepted === false) return;
    addToHistory(trimmed);
    clearInput();
  }, [addToHistory, clearInput]);

  const submitCommand = useCallback((trimmed: string) => {
    try {
      const result = onExecute(trimmed);
      if (result && typeof (result as Promise<void | boolean>).then === 'function') {
        void (result as Promise<void | boolean>).then((accepted) => {
          finishSubmit(accepted, trimmed);
        });
        return;
      }
      finishSubmit(result as void | boolean, trimmed);
    } catch {
      // 执行入口自身抛错时保留输入，方便用户修正或重试。
    }
  }, [finishSubmit, onExecute]);

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (applyManualEdit(e)) {
      e.preventDefault();
      return;
    }

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
          applyCompletion(item);
        }
        return;
      }
      if (e.key === 'Enter') {
        e.preventDefault();
        const item = acceptCompletion();
        if (item) {
          applyCompletion(item);
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
        submitCommand(trimmed);
      }
    }
  };

  // Auto-focus the input
  useEffect(() => {
    inputRef.current?.focus();
  }, []);

  useLayoutEffect(() => {
    updateCompletionBox(input, cursorPos);
  }, [input, cursorPos, updateCompletionBox]);

  useEffect(() => {
    if (!showCompletions) return undefined;
    let frame = 0;
    const syncFrame = () => {
      const inputEl = inputRef.current?.input as HTMLInputElement | undefined;
      if (inputEl) {
        const value = inputEl.value;
        const pos = inputEl.selectionStart ?? value.length;
        updateCompletionBox(value, pos);
      }
      frame = window.requestAnimationFrame(syncFrame);
    };
    frame = window.requestAnimationFrame(syncFrame);
    return () => window.cancelAnimationFrame(frame);
  }, [showCompletions, updateCompletionBox]);

  useEffect(() => {
    const inputEl = inputRef.current?.input as HTMLInputElement | undefined;
    if (!inputEl) return undefined;
    const sync = () => {
      const value = inputEl.value;
      const pos = inputEl.selectionStart ?? value.length;
      updateCompletionBox(value, pos);
    };
    inputEl.addEventListener('input', sync);
    inputEl.addEventListener('keyup', sync);
    inputEl.addEventListener('click', sync);
    inputEl.addEventListener('select', sync);
    return () => {
      inputEl.removeEventListener('input', sync);
      inputEl.removeEventListener('keyup', sync);
      inputEl.removeEventListener('click', sync);
      inputEl.removeEventListener('select', sync);
    };
  }, [updateCompletionBox]);

  // Compute ghost text display: the full input + ghost suffix
  const ghostDisplay = ghostText && !showCompletions ? input + ghostText : null;
  const completionAnchorText = input.slice(0, getCompletionAnchorPos(input, cursorPos, columns));
  const anchorOffset = Math.min(
    Math.max(14, completionBox.anchorX - completionBox.left),
    Math.max(14, completionBox.width - 14),
  );
  const compactCompletion = completionBox.width < 420 || completionBox.placement === 'compact';
  const completionDropdown = showCompletions && completions.length > 0 ? (
    <div
      data-testid="completion-menu"
      style={{
        position: 'absolute',
        bottom: 44,
        left: `var(--completion-left, ${completionBox.left}px)`,
        width: `var(--completion-width, ${completionBox.width}px)`,
        maxWidth: `calc(100% - 32px)`,
        background: '#fff',
        border: '1px solid #d7e3f2',
        borderRadius: 10,
        maxHeight: 220,
        overflowX: 'hidden',
        overflowY: 'auto',
        zIndex: 1000,
        boxShadow: '0 16px 38px rgba(15, 23, 42, 0.16)',
        pointerEvents: 'auto',
      }}
    >
      <span
        data-testid="completion-anchor-marker"
        aria-hidden="true"
        style={{
          position: 'absolute',
          left: anchorOffset,
          bottom: -7,
          width: 12,
          height: 12,
          transform: 'translateX(-50%) rotate(45deg)',
          background: '#fff',
          borderRight: '1px solid #d7e3f2',
          borderBottom: '1px solid #d7e3f2',
          boxShadow: '8px 8px 18px rgba(15, 23, 42, 0.06)',
        }}
      />
      <span
        aria-hidden="true"
        style={{
          position: 'absolute',
          left: anchorOffset,
          bottom: 0,
          width: 2,
          height: 10,
          transform: 'translateX(-50%)',
          background: '#1677ff',
          borderRadius: 2,
          opacity: completionBox.placement === 'flip' || completionBox.placement === 'compact' ? 0.9 : 0,
        }}
      />
      {correction && (
        <div style={{ padding: '4px 12px', fontSize: 12, color: '#999', borderBottom: '1px solid #f0f0f0' }}>
          未找到。你的意思是？
        </div>
      )}
      {completions.map((item, idx) => (
        <div
          key={item.text}
          style={{
            padding: '9px 14px',
            cursor: 'pointer',
            background: idx === selectedCompletionIdx ? '#e6f4ff' : 'transparent',
            display: 'grid',
            gridTemplateColumns: compactCompletion ? 'minmax(0, 1fr)' : 'minmax(0, 1fr) minmax(72px, 42%)',
            rowGap: 2,
            columnGap: 16,
            alignItems: compactCompletion ? 'start' : 'center',
            minWidth: 0,
          }}
          onMouseDown={(e) => {
            e.preventDefault();
          }}
          onClick={() => {
            applyCompletion(item);
          }}
        >
          <span style={{ fontWeight: 600, fontSize: 13, minWidth: 0, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{item.text}</span>
          {item.description && (
            <span
              style={{
                color: '#7b8794',
                fontSize: 11,
                minWidth: 0,
                overflow: 'hidden',
                textOverflow: 'ellipsis',
                whiteSpace: 'nowrap',
                textAlign: compactCompletion ? 'left' : 'right',
              }}
            >
              {item.description}
            </span>
          )}
        </div>
      ))}
    </div>
  ) : null;
  const feedbackColors = feedback?.level === 'warning'
    ? {
      border: '#ffd591',
      background: '#fff7e6',
      text: '#874d00',
      iconBackground: '#fa8c16',
    }
    : {
      border: '#ffccc7',
      background: '#fff1f0',
      text: '#820014',
      iconBackground: '#ff4d4f',
    };

  return (
    <div
      data-testid="command-shell"
      style={{
        position: 'relative',
        padding: '10px 16px 6px',
        borderTop: '1px solid #e8e8e8',
        background: '#fafafa',
        flexShrink: 0,
      }}
      ref={shellRef}
    >
      {feedback && (
        <div
          data-testid="cli-feedback"
          role="status"
          style={{
            position: 'absolute',
            left: 0,
            right: 0,
            bottom: '100%',
            zIndex: 1100,
            minHeight: 44,
            padding: '10px 44px 10px 18px',
            display: 'flex',
            alignItems: 'center',
            gap: 12,
            borderTop: `1px solid ${feedbackColors.border}`,
            borderBottom: `1px solid ${feedbackColors.border}`,
            background: feedbackColors.background,
            color: feedbackColors.text,
            boxShadow: '0 -10px 28px rgba(15, 23, 42, 0.08)',
          }}
        >
          <span
            aria-hidden="true"
            style={{
              width: 18,
              height: 18,
              borderRadius: '50%',
              display: 'inline-flex',
              alignItems: 'center',
              justifyContent: 'center',
              flexShrink: 0,
              background: feedbackColors.iconBackground,
              color: '#fff',
              fontSize: 12,
              fontWeight: 700,
              lineHeight: 1,
            }}
          >
            {feedback.level === 'warning' ? '!' : '×'}
          </span>
          <span style={{ fontSize: 13, fontWeight: 600, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
            {feedback.message}
          </span>
          <button
            type="button"
            aria-label="关闭命令行提示"
            onClick={onClearFeedback}
            style={{
              position: 'absolute',
              right: 14,
              top: '50%',
              transform: 'translateY(-50%)',
              border: 0,
              background: 'transparent',
              color: feedbackColors.text,
              cursor: 'pointer',
              fontSize: 22,
              lineHeight: 1,
              padding: 4,
              opacity: 0.72,
            }}
          >
            ×
          </button>
        </div>
      )}
      {completionDropdown}
      <span
        ref={measureRef}
        aria-hidden="true"
        style={{
          position: 'absolute',
          visibility: 'hidden',
          whiteSpace: 'pre',
          pointerEvents: 'none',
          top: -9999,
          left: -9999,
        }}
      />

      {/* Command input with ghost text */}
      <div style={{ position: 'relative' }}>
        <div
          aria-hidden="true"
          style={{
            position: 'absolute',
            left: 0,
            top: 0,
            right: 0,
            bottom: 0,
            display: 'flex',
            alignItems: 'center',
            paddingLeft: 26,
            pointerEvents: 'none',
            zIndex: 3,
            fontFamily: 'monospace',
            fontSize: 14,
            fontWeight: 400,
            lineHeight: '32px',
            whiteSpace: 'pre',
          }}
        >
          <span ref={caretTextRef} style={{ visibility: 'hidden' }}>
            {completionAnchorText}
          </span>
          <span
            data-testid="completion-anchor"
            style={{
              position: 'relative',
              display: 'inline-block',
              width: 0,
              height: 0,
              visibility: 'visible',
            }}
          />
        </div>
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
          onKeyUp={handleCursorMove}
          onClick={handleCursorMove}
          onSelect={handleCursorMove}
          onBlur={() => setTimeout(hideCompletions, 200)}
          variant="borderless"
          style={{ fontFamily: 'monospace', fontSize: 14 }}
        />
      </div>

      {/* Hint bar */}
      <div
        style={{
          fontSize: 10,
          color: '#bbb',
          marginTop: 4,
          paddingLeft: 20,
          lineHeight: '16px',
        }}
      >
        Enter/Tab 接受补全 · ↑↓ 浏览 · Enter 执行命令 · Esc 关闭
        {correction && <span style={{ color: '#faad14', marginLeft: 12 }}>建议: {correction}</span>}
      </div>
    </div>
  );
};
