import { create } from 'zustand';
import type { ParsedCommand } from '../services/commandParser';
import type { CompletionItem, AutocompleteContext } from '../services/autocomplete';

interface CommandState {
  // Current input
  input: string;
  cursorPos: number;

  // Completion state
  context: AutocompleteContext | null;
  completions: CompletionItem[];
  selectedCompletionIdx: number;
  ghostText: string | null;
  showCompletions: boolean;

  // Correction hint
  correction: string | null;

  // Command history
  history: string[];
  historyIdx: number; // -1 = not navigating history

  // Parse result of last submitted command
  lastParsed: ParsedCommand | null;
  parseError: string | null;

  // Actions
  setInput: (input: string, cursorPos: number) => void;
  setCompletions: (completions: CompletionItem[], context: AutocompleteContext) => void;
  setGhostText: (text: string | null) => void;
  setCorrection: (correction: string | null) => void;
  acceptCompletion: () => CompletionItem | null;
  selectNextCompletion: () => void;
  selectPrevCompletion: () => void;
  hideCompletions: () => void;
  addToHistory: (cmd: string) => void;
  navigateHistoryUp: () => string | null;
  navigateHistoryDown: () => string | null;
  setLastParsed: (parsed: ParsedCommand | null, error: string | null) => void;
  clearInput: () => void;
}

export const useCommandStore = create<CommandState>((set, get) => ({
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

  setInput: (input, cursorPos) =>
    set({ input, cursorPos, correction: null }),

  setCompletions: (completions, context) =>
    set({
      completions,
      context,
      selectedCompletionIdx: 0,
      showCompletions: completions.length > 0,
    }),

  setGhostText: (ghostText) => set({ ghostText }),

  setCorrection: (correction) => set({ correction }),

  acceptCompletion: () => {
    const { completions, selectedCompletionIdx } = get();
    if (completions.length === 0) return null;
    const idx = Math.min(selectedCompletionIdx, completions.length - 1);
    const item = completions[idx];
    set({ showCompletions: false, ghostText: null });
    return item;
  },

  selectNextCompletion: () =>
    set((s) => ({
      selectedCompletionIdx: Math.min(
        s.selectedCompletionIdx + 1,
        s.completions.length - 1
      ),
    })),

  selectPrevCompletion: () =>
    set((s) => ({
      selectedCompletionIdx: Math.max(s.selectedCompletionIdx - 1, 0),
    })),

  hideCompletions: () => set({ showCompletions: false, correction: null }),

  addToHistory: (cmd) =>
    set((s) => ({
      history: [cmd, ...s.history].slice(0, 100),
      historyIdx: -1,
    })),

  navigateHistoryUp: () => {
    const { historyIdx } = get();
    const hist = get().history;
    if (historyIdx >= hist.length - 1) return null;
    const newIdx = historyIdx + 1;
    set({ historyIdx: newIdx });
    return hist[newIdx];
  },

  navigateHistoryDown: () => {
    const { historyIdx } = get();
    const hist = get().history;
    if (historyIdx <= 0) {
      set({ historyIdx: -1 });
      return '';
    }
    const newIdx = historyIdx - 1;
    set({ historyIdx: newIdx });
    return hist[newIdx];
  },

  setLastParsed: (lastParsed, parseError) =>
    set({ lastParsed, parseError }),

  clearInput: () =>
    set({
      input: '',
      cursorPos: 0,
      ghostText: null,
      showCompletions: false,
      correction: null,
      completions: [],
      lastParsed: null,
      parseError: null,
    }),
}));
